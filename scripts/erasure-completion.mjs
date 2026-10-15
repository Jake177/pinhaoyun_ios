import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdtempSync,rmSync} from 'node:fs';
import assert from 'node:assert/strict';
const root=new URL('../',import.meta.url),config=JSON.parse(readFileSync(new URL('infra/outputs.local.json',root))),state=JSON.parse(readFileSync(new URL('infra/erasure-state.local.json',root))),fixture=JSON.parse(readFileSync(new URL('infra/test-credentials.local.json',root)))[0];
if(!config.MediaTable.startsWith('pinhaoyun-ios-dev-') || !/^ios-qa-.*@example\.invalid$/.test(state.email))throw new Error('Disposable development fixtures only');
function aws(service,operation,input) {
 const folder=mkdtempSync('/private/tmp/pinhaoyun-proof-');
 try {
  const path=folder+'/input.json';writeFileSync(path,JSON.stringify(input),{mode:0o600});
  const p=spawnSync('aws',[service,operation,'--profile','pinhaoyun','--region','ap-southeast-2','--output','json','--no-cli-pager','--cli-input-json','file://'+path],{encoding:'utf8'});
  if(p.status!==0)throw new Error(p.stderr.slice(0,1500));return p.stdout.trim()?JSON.parse(p.stdout):{};
 }finally{rmSync(folder,{recursive:true,force:true});}
}
const headers=token=>({Authorization:'Bearer '+token.idToken,'X-Access-Token':token.accessToken});
async function api(path,body,token) {
 const res=await fetch('http://127.0.0.1:3000'+path,{method:body===undefined?'GET':'POST',headers:{...(token?headers(token):{}),...(body?{'Content-Type':'application/json'}:{})},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(60000)});
 return {status:res.status,json:await res.json()};
}
let completed=false;
for(let i=0;i<100;i++) {
 const response=await api('/api/user/deletion-status',{requestId:state.deletion.requestId,receipt:state.deletion.receipt});assert.equal(response.status,200);
 if(response.json.state==='COMPLETE'){completed=true;break;}
 await new Promise(r=>setTimeout(r,5000));
}
assert.ok(completed,'Deletion did not finish in the accelerated test window');
const partition=aws('dynamodb','query',{TableName:config.MediaTable,KeyConditionExpression:'email = :email',ExpressionAttributeValues:{':email':{S:state.email}},Select:'COUNT',ConsistentRead:true});assert.equal(partition.Count,0);
for(const bucket of [config.OriginalBucket,config.ThumbnailBucket,config.ProfileBucket]) {
 for(const email of [state.email,encodeURIComponent(state.email)])for(const prefix of ['photo/','video/','profile-signature/'])assert.equal((aws('s3api','list-objects-v2',{Bucket:bucket,Prefix:prefix+email+'/'}).Contents || []).length,0);
}
try {aws('cognito-idp','admin-get-user',{UserPoolId:config.UserPoolId,Username:state.email});throw new Error('Account still exists');}catch(error){assert.match(error.message,/UserNotFoundException/);}
assert.equal((await api('/api/user/profile',undefined,state.owner)).status,401);
assert.equal((await api('/api/user/profile',undefined,state.other)).status,200);
const receipt=aws('dynamodb','get-item',{TableName:config.DeletionsTable,Key:{requestId:{S:state.deletion.requestId}},ConsistentRead:true}).Item;
assert.ok(!receipt.email && !receipt.userSub && !receipt.username,'Completed receipt retains personal identifiers');
console.log('Verified completed erasure: Cognito account, entire data partition, original/thumbnail/profile objects removed; other account unaffected; receipt anonymized.');
// Recreate the same synthetic email with a new identity, without sending messages.
const attrs=[['email',state.email],['email_verified','true'],['preferred_username','iOS QA'],['given_name','Generation'],['family_name','Test'],['gender','Other']].map(([Name,Value])=>({Name,Value}));
const user=aws('cognito-idp','admin-create-user',{UserPoolId:config.UserPoolId,Username:state.email,MessageAction:'SUPPRESS',UserAttributes:attrs}).User;
aws('cognito-idp','admin-set-user-password',{UserPoolId:config.UserPoolId,Username:user.Username,Password:fixture.password,Permanent:true});
const newSub=user.Attributes.find(a=>a.Name==='sub').Value;
aws('dynamodb','put-item',{TableName:config.MediaTable,Item:{email:{S:state.email},sk:{S:'PROFILE'},userSub:{S:newSub},accountStatus:{S:'ACTIVE'},requiresOwnerMetadata:{BOOL:true},quotaBytes:{N:String(10*1024*1024*1024)},usedBytes:{N:'0'},reservedBytes:{N:'0'},photoBytes:{N:'0'},videoBytes:{N:'0'},photoCount:{N:'0'},videosCount:{N:'0'},createdAt:{S:new Date().toISOString()}}});
assert.notEqual(newSub,state.owner.sub);
assert.equal((await api('/api/user/profile',undefined,state.owner)).status,401);
const signed=await api('/api/mobile/auth/sign-in',fixture);assert.equal(signed.status,200);assert.equal(signed.json.requiresConsent,true);
const policy=(await api('/api/mobile/policies')).json;
assert.equal((await api('/api/mobile/consent',{acceptedTerms:true,acknowledgedPrivacy:true,termsVersion:policy.version,privacyVersion:policy.version},signed.json)).status,200);
const old=JSON.parse(readFileSync(new URL('infra/integration-state.local.json',root)));
const upload=spawnSync('aws',['s3api','put-object','--bucket',config.OriginalBucket,'--key',old.key,'--body',new URL('App/Resources/Assets.xcassets/AppIcon.appiconset/icon.png',root).pathname,'--metadata','owner-sub='+state.owner.sub,'--profile','pinhaoyun','--region','ap-southeast-2','--output','json'],{encoding:'utf8'});assert.equal(upload.status,0,upload.stderr);
let lateRemoved=false;
for(let i=0;i<20;i++) {
 await new Promise(r=>setTimeout(r,2000));
 const items=aws('s3api','list-objects-v2',{Bucket:config.OriginalBucket,Prefix:old.key}).Contents || [];
 if(!items.length){lateRemoved=true;break;}
}
assert.ok(lateRemoved,'A late upload belonging to the erased subject survived');
const ghost=aws('dynamodb','get-item',{TableName:config.MediaTable,Key:{email:{S:state.email},sk:{S:'PHOTO#'+old.photoId}},ConsistentRead:true});assert.ok(!ghost.Item);
writeFileSync(new URL('infra/new-generation-session.local.json',root),JSON.stringify(signed.json),{mode:0o600});
console.log('Verified same-email re-registration isolation: old tokens denied and a late object from the erased identity removed without recreating media.');
