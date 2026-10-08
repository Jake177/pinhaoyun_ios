import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const backend=resolve(root,'../PinHaoYun_backend');
const profile='pinhaoyun', region='ap-southeast-2', prefix='pinhaoyun-ios-dev';
function run(command,args,options={}) {
 const result=spawnSync(command,args,{encoding:'utf8',maxBuffer:16*1024*1024,...options});
 if(result.status!==0) throw new Error(`${command} failed: ${(result.stderr || result.stdout || '').slice(0,2000)}`);
 return result.stdout;
}
function aws(service,operation,input={}) {
 const temporary=mkdtempSync('/private/tmp/pinhaoyun-aws-');
 try {
  const file=temporary+'/request.json';writeFileSync(file,JSON.stringify(input),{mode:0o600});
  const output=run('aws',[service,operation,'--profile',profile,'--region',region,'--no-cli-pager','--output','json','--cli-input-json','file://'+file]);
  return output.trim()?JSON.parse(output):{};
 } finally { rmSync(temporary,{recursive:true,force:true}); }
}
function outputs(name) { return Object.fromEntries(aws('cloudformation','describe-stacks',{StackName:name}).Stacks[0].Outputs.map(v=>[v.OutputKey,v.OutputValue])); }
function deploy(name,template,parameters=[]) {
 const request={StackName:name,TemplateBody:JSON.stringify(template),Capabilities:['CAPABILITY_NAMED_IAM'],Parameters:parameters,Tags:[{Key:'Project',Value:'PinHaoYun'},{Key:'Environment',Value:'ios-development'}]};
 let exists=false;
 try { aws('cloudformation','describe-stacks',{StackName:name});exists=true; } catch(e) { if(!/does not exist/.test(e.message)) throw e; }
 try { aws('cloudformation',exists?'update-stack':'create-stack',request); }
 catch(e) { if(/No updates are to be performed/.test(e.message)) return; throw e; }
 console.log(`Waiting for ${name} ${exists?'update':'creation'}...`);
 run('aws',['cloudformation','wait',exists?'stack-update-complete':'stack-create-complete','--stack-name',name,'--profile',profile,'--region',region]);
}
const identity=aws('sts','get-caller-identity');
if(identity.Account!=='883086653724') throw new Error('Unexpected AWS account; refusing to deploy');
const artifactName=`${prefix}-artifacts-${identity.Account}`;
deploy(prefix+'-artifacts',{AWSTemplateFormatVersion:'2010-09-09',Resources:{Artifacts:{Type:'AWS::S3::Bucket',DeletionPolicy:'Retain',Properties:{BucketName:artifactName,BucketEncryption:{ServerSideEncryptionConfiguration:[{ServerSideEncryptionByDefault:{SSEAlgorithm:'AES256'}}]},PublicAccessBlockConfiguration:{BlockPublicAcls:true,BlockPublicPolicy:true,IgnorePublicAcls:true,RestrictPublicBuckets:true},LifecycleConfiguration:{Rules:[{Id:'expire-builds',Status:'Enabled',ExpirationInDays:30}]}}}},Outputs:{Bucket:{Value:{Ref:'Artifacts'}}}});
const stamp=new Date().toISOString().replace(/[:.]/g,'-');
const artifactPrefix='lambda/'+stamp;
const sources=['postConfirmation','photoIngest','transcodeVideo','enrichLocation','deleteVideo','deleteAccount','cleanupUploads'];
for(const name of sources) {
 const folder=resolve(root,'infra/artifacts',name);mkdirSync(folder,{recursive:true});
 run('node',[resolve(backend,'node_modules/esbuild/bin/esbuild'),resolve(backend,`aws/lambda/${name}.js`),'--bundle','--platform=node','--target=node24','--external:@aws-sdk/*',`--outfile=${folder}/index.js`],{cwd:backend});
 run('zip',['-q','-j',folder+'/function.zip',folder+'/index.js']);
 run('aws',['s3','cp',folder+'/function.zip',`s3://${artifactName}/${artifactPrefix}/${name}.zip`,'--profile',profile,'--region',region,'--only-show-errors']);
 console.log('Packaged '+name);
}
const template=JSON.parse(readFileSync(resolve(root,'infra/development.template.json'),'utf8'));
const photoConfig=aws('lambda','get-function-configuration',{FunctionName:'pinhaoyun-photoIngest'}).Environment?.Variables || {};
for(const name of ['MAGICK_HOME','LD_LIBRARY_PATH','MAGICK_CONFIGURE_PATH','MAGICK_CODER_MODULE_PATH','IMAGEMAGICK_IDENTIFY_PATH','IMAGEMAGICK_CONVERT_PATH']) if(photoConfig[name]) template.Resources.PhotoIngest.Properties.Environment.Variables[name]=photoConfig[name];
const locationConfig=aws('lambda','get-function-configuration',{FunctionName:'pinhaoyun-enrichLocation'}).Environment?.Variables || {};
deploy(prefix,template,[{ParameterKey:'ArtifactBucket',ParameterValue:artifactName},{ParameterKey:'ArtifactPrefix',ParameterValue:artifactPrefix},{ParameterKey:'MapboxToken',ParameterValue:locationConfig.MAPBOX_TOKEN || locationConfig.NEXT_PUBLIC_MAPBOX_TOKEN || ''}]);
for(const name of sources) {
 const logGroupName=`/aws/lambda/${prefix}-${name}`;
 try { aws('logs','create-log-group',{logGroupName,tags:{Project:'PinHaoYun',Environment:'ios-development'}}); }
 catch(error) { if(!error.message.includes('ResourceAlreadyExistsException')) throw error; }
 aws('logs','put-retention-policy',{logGroupName,retentionInDays:14});
}
const values=outputs(prefix);
for(const client of ['Web','Mobile']) {
 const secret=aws('cognito-idp','describe-user-pool-client',{UserPoolId:values.UserPoolId,ClientId:values[client+'ClientId']}).UserPoolClient.ClientSecret;
 if(!secret) throw new Error('Expected confidential client');
 aws('secretsmanager','put-secret-value',{SecretId:values[client+'SecretArn'],SecretString:JSON.stringify({COGNITO_CLIENT_SECRET:secret})});
}
const env={AWS_PROFILE:profile,COGNITO_REGION:region,COGNITO_USER_POOL_ID:values.UserPoolId,COGNITO_CLIENT_ID:values.WebClientId,COGNITO_SECRET_ID:values.WebSecretArn,COGNITO_MOBILE_CLIENT_ID:values.MobileClientId,COGNITO_MOBILE_SECRET_ID:values.MobileSecretArn,VIDEOS_TABLE:values.MediaTable,USERS_TABLE:values.MediaTable,S3_ORIGINAL_BUCKET:values.OriginalBucket,S3_THUMBNAIL_BUCKET:values.ThumbnailBucket,S3_PROFILE_BUCKET:values.ProfileBucket,VIDEOS_DELETE_QUEUE_URL:values.MediaDeleteQueueUrl,LOCATION_ENRICH_QUEUE_URL:values.LocationQueueUrl,ACCOUNT_DELETE_QUEUE_URL:values.AccountDeleteQueueUrl,ACCOUNT_DELETIONS_TABLE:values.DeletionsTable,TIMELINE_INDEX_NAME:'TimelineIndex',APP_ENV:'development',POLICIES_APPROVED:'false',ACCOUNT_ID:identity.Account,NEXT_PUBLIC_APP_URL:'http://localhost:3000'};
writeFileSync(resolve(backend,'.env.local'),Object.entries(env).map(([k,v])=>`${k}=${v}`).join('\n')+'\n',{mode:0o600});
writeFileSync(resolve(root,'infra/outputs.local.json'),JSON.stringify({...values,region,artifactBucket:artifactName},null,2)+'\n',{mode:0o600});
console.log('Isolated development resources ready. Wrote ignored local config; no secret values printed.');
