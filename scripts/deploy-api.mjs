// Explicit deployment only. Never embeds local credentials or production config.
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..'), backend=resolve(root,'../PinHaoYun_backend');
const profile='pinhaoyun', region='ap-southeast-2', prefix='pinhaoyun-ios-dev-api';
function run(cmd,args,options={}) {
 const result=spawnSync(cmd,args,{encoding:'utf8',maxBuffer:8*1024*1024,...options});
 if(result.status!==0) throw new Error(`${cmd}: ${(result.stderr||result.stdout||'failed').slice(-2400)}`);
 return result.stdout;
}
function aws(service,operation,input={}) {
 const dir=mkdtempSync('/private/tmp/pinhaoyun-api-');
 try {const file=dir+'/request.json';writeFileSync(file,JSON.stringify(input),{mode:0o600});return JSON.parse(run('aws',[service,operation,'--profile',profile,'--region',region,'--no-cli-pager','--output','json','--cli-input-json','file://'+file])||'{}');}
 finally {rmSync(dir,{recursive:true,force:true});}
}
function outputs(name) {return Object.fromEntries(aws('cloudformation','describe-stacks',{StackName:name}).Stacks[0].Outputs.map(value=>[value.OutputKey,value.OutputValue]));}
function deploy(name,template,values) {
 let exists=false;let status;
 try {status=aws('cloudformation','describe-stacks',{StackName:name}).Stacks[0].StackStatus;exists=true;}catch(error){if(!error.message.includes('does not exist'))throw error;}
 if(status==='ROLLBACK_COMPLETE') {
  const remaining=aws('cloudformation','list-stack-resources',{StackName:name}).StackResourceSummaries.filter(value=>value.ResourceStatus!=='DELETE_COMPLETE');
  if(remaining.length)throw new Error('Failed stack still has resources; preserving it for inspection');
  aws('cloudformation','delete-stack',{StackName:name});
  run('aws',['cloudformation','wait','stack-delete-complete','--stack-name',name,'--profile',profile,'--region',region]);exists=false;
 }
 const request={StackName:name,TemplateBody:JSON.stringify(template),Capabilities:['CAPABILITY_NAMED_IAM'],Parameters:Object.keys(template.Parameters).map(key=>({ParameterKey:key,ParameterValue:String(values[key]??'')})),Tags:[{Key:'Project',Value:'PinHaoYun'},{Key:'Environment',Value:'ios-development'}]};
 if(!exists && name.endsWith('-service'))request.DisableRollback=true;
 if(status==='CREATE_FAILED')request.DisableRollback=true;
 try {aws('cloudformation',exists?'update-stack':'create-stack',request);}catch(error){if(error.message.includes('No updates are to be performed'))return;throw error;}
 console.log('Waiting for '+name);
 run('aws',['cloudformation','wait',exists?'stack-update-complete':'stack-create-complete','--stack-name',name,'--profile',profile,'--region',region]);
}
if(aws('sts','get-caller-identity').Account!=='883086653724')throw new Error('Unexpected AWS account');
const core=outputs('pinhaoyun-ios-dev');
if(!core.MediaTable?.startsWith('pinhaoyun-ios-dev-')||!core.OriginalBucket?.startsWith('pinhaoyun-ios-dev-'))throw new Error('Refusing non-development resources');
const privateConfig=JSON.parse(readFileSync(resolve(root,'infra/api.local.json'),'utf8'));
if(!privateConfig.allowedTestEmails?.length)throw new Error('Set allowedTestEmails in ignored infra/api.local.json');
const dir=resolve(root,'infra/artifacts/api');mkdirSync(dir,{recursive:true});
const zip=resolve(dir,'source.zip');
run('python3',['-c',`import pathlib,subprocess,zipfile
root=pathlib.Path.cwd()
paths=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z']).decode().split('\\0')
with zipfile.ZipFile(${JSON.stringify(zip)},'w',zipfile.ZIP_DEFLATED) as archive:
 for name in paths:
  p=root/name
  if name and p.is_file() and not p.is_symlink() and not any(part.startswith('.env') for part in p.parts): archive.write(p,name)
`],{cwd:backend});
const reuseIndex=process.argv.indexOf('--image-tag');
const reuseTag=reuseIndex>=0?process.argv[reuseIndex+1]:null;
if(reuseTag&&!/^backup-[a-f0-9]{16}$/.test(reuseTag))throw new Error('Invalid immutable image tag');
const tag=reuseTag||'backup-'+createHash('sha256').update(readFileSync(zip)).digest('hex').slice(0,16);
console.log(reuseTag?'Using verified image: '+tag:'Source snapshot prepared: '+tag);
const ArtifactBucket='pinhaoyun-ios-dev-artifacts-883086653724';
const base=JSON.parse(run('python3',[resolve(root,'infra/api-template.py')]));
aws('cloudformation','validate-template',{TemplateBody:JSON.stringify(base)});
deploy(prefix,base,{...core,ArtifactBucket});
const infra=outputs(prefix), key='api/'+tag+'.zip';
let build;
if(reuseTag)aws('ecr','describe-images',{repositoryName:prefix,imageIds:[{imageTag:tag}]});
else {
run('aws',['s3','cp',zip,`s3://${ArtifactBucket}/${key}`,'--profile',profile,'--region',region,'--only-show-errors']);
build=aws('codebuild','start-build',{projectName:infra.BuildName,sourceLocationOverride:`${ArtifactBucket}/${key}`,environmentVariablesOverride:[{name:'IMAGE_TAG',value:tag,type:'PLAINTEXT'}]}).build;
console.log('Build started: '+build.id);
let phase='';
for(;;) {
 const state=aws('codebuild','batch-get-builds',{ids:[build.id]}).builds[0];
 if(state.currentPhase!==phase){phase=state.currentPhase;console.log('Build phase: '+phase);}
 if(state.buildComplete){if(state.buildStatus!=='SUCCEEDED')throw new Error('Build '+state.buildStatus+'; inspect scoped CodeBuild logs');break;}
 await new Promise(done=>setTimeout(done,15000));
}
}
const service=JSON.parse(run('python3',[resolve(root,'infra/api-template.py'),'service']));
try {deploy(prefix+'-service',service,{...core,...infra,AccessRoleArn:infra.AccessRole,InstanceRoleArn:infra.InstanceRole,ImageIdentifier:infra.RepositoryUri+':'+tag,TestEmails:privateConfig.allowedTestEmails.join(',')});}
finally {
 for(const group of aws('logs','describe-log-groups',{logGroupNamePrefix:'/aws/apprunner/'+prefix+'/'}).logGroups||[]) aws('logs','put-retention-policy',{logGroupName:group.logGroupName,retentionInDays:14});
}
const result=outputs(prefix+'-service');
writeFileSync(resolve(root,'infra/api-output.local.json'),JSON.stringify({...result,imageTag:tag,buildId:build?.id},null,2)+'\n',{mode:0o600});
const url='https://'+result.ServiceUrl;
for(const suffix of ['application','service']) {
 const group=`/aws/apprunner/${prefix}/${result.ServiceArn.split('/').pop()}/${suffix}`;
 try {aws('logs','put-retention-policy',{logGroupName:group,retentionInDays:14});}catch {console.log('Log retention pending for '+suffix);}
}
console.log('Isolated API ready: '+url);
