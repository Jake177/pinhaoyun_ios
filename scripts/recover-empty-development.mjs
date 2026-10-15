// Recover ONLY a failed, never-used initial development stack. Never empties a bucket/table.
import {spawnSync} from 'node:child_process';
import {existsSync} from 'node:fs';
if(!process.argv.includes('--empty-initial-stack')) throw new Error('Explicit initial-stack recovery flag required');
if(existsSync(new URL('../infra/outputs.local.json',import.meta.url))) throw new Error('An initialized environment must not use this recovery script');
const profile='pinhaoyun',region='ap-southeast-2',stack='pinhaoyun-ios-dev';
function aws(service,operation,args=[]) {
 const result=spawnSync('aws',[service,operation,...args,'--profile',profile,'--region',region,'--output','json','--no-cli-pager'],{encoding:'utf8'});
 if(result.status!==0) throw new Error(result.stderr);
 return result.stdout.trim()?JSON.parse(result.stdout):{};
}
if(aws('sts','get-caller-identity').Account!=='883086653724') throw new Error('Unexpected account');
if(aws('cloudformation','describe-stacks',['--stack-name',stack]).Stacks[0].StackStatus!=='ROLLBACK_COMPLETE') throw new Error('Only a rolled-back initial stack can be recovered');
const retained=aws('cloudformation','list-stack-resources',['--stack-name',stack]).StackResourceSummaries.filter(r=>r.ResourceStatus==='DELETE_SKIPPED');
for(const r of retained) {
 const id=r.PhysicalResourceId;
 if(r.ResourceType==='AWS::DynamoDB::Table') {
  if(!['pinhaoyun-ios-dev-media','pinhaoyun-ios-dev-deletions'].includes(id))throw new Error('Unexpected table');
  if(aws('dynamodb','scan',['--table-name',id,'--select','COUNT','--limit','1','--consistent-read']).Count!==0)throw new Error('Table contains data; refusing recovery');
 } else if(r.ResourceType==='AWS::S3::Bucket') {
  if(!/^pinhaoyun-ios-dev-(original|thumbnail|profile)-883086653724$/.test(id))throw new Error('Unexpected bucket');
  if(aws('s3api','list-objects-v2',['--bucket',id,'--max-keys','1']).Contents?.length)throw new Error('Bucket contains data; refusing recovery');
  if(aws('s3api','list-multipart-uploads',['--bucket',id,'--max-uploads','1']).Uploads?.length)throw new Error('Bucket contains uploads; refusing recovery');
  const versions=aws('s3api','list-object-versions',['--bucket',id,'--max-keys','1']);if(versions.Versions?.length || versions.DeleteMarkers?.length)throw new Error('Bucket contains versions; refusing recovery');
 } else if(r.ResourceType==='AWS::SecretsManager::Secret') {
  if(!/^arn:aws:secretsmanager:ap-southeast-2:883086653724:secret:pinhaoyun\/ios-dev\/(mobile|web)-cognito-/.test(id))throw new Error('Unexpected secret');
 } else throw new Error('Unexpected retained resource '+r.ResourceType);
}
console.log('Confirmed all retained development tables and buckets are empty.');
for(const r of retained) {
 const id=r.PhysicalResourceId;
 if(r.ResourceType==='AWS::DynamoDB::Table') {aws('dynamodb','delete-table',['--table-name',id]);aws('dynamodb','wait',['table-not-exists','--table-name',id]);}
 if(r.ResourceType==='AWS::S3::Bucket')aws('s3api','delete-bucket',['--bucket',id]);
 if(r.ResourceType==='AWS::SecretsManager::Secret')aws('secretsmanager','delete-secret',['--secret-id',id,'--force-delete-without-recovery']);
}
aws('cloudformation','delete-stack',['--stack-name',stack]);aws('cloudformation','wait',['stack-delete-complete','--stack-name',stack]);
console.log('Removed only the failed initial development stack and its confirmed unused resources.');
