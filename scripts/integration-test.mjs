import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdtempSync,rmSync} from 'node:fs';
import {randomBytes,randomUUID,createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const root=new URL('../',import.meta.url);
const config=JSON.parse(readFileSync(new URL('infra/outputs.local.json',root),'utf8'));
if(!config.MediaTable.startsWith('pinhaoyun-ios-dev-') || !config.OriginalBucket.startsWith('pinhaoyun-ios-dev-'))throw new Error('Only isolated development resources may be tested');
const base=process.env.TEST_API_BASE_URL || 'http://127.0.0.1:3000';
function aws(service,operation,input,extra=[]) {
 const folder=mkdtempSync('/private/tmp/pinhaoyun-test-');
 try {
  const path=folder+'/input.json';writeFileSync(path,JSON.stringify(input),{mode:0o600});
  const p=spawnSync('aws',[service,operation,...extra,'--profile','pinhaoyun','--region','ap-southeast-2','--output','json','--no-cli-pager','--cli-input-json','file://'+path],{encoding:'utf8'});
  if(p.status!==0)throw new Error(`${service}/${operation}: ${p.stderr.slice(0,1500)}`);
  return p.stdout.trim()?JSON.parse(p.stdout):{};
 } finally {rmSync(folder,{recursive:true,force:true});}
}
async function request(path,body,tokens,expected=200,headers={}) {
 const res=await fetch(base+path,{method:body===undefined?'GET':'POST',headers:{...(body?{'Content-Type':'application/json'}:{}),...(tokens?{Authorization:'Bearer '+tokens.idToken,'X-Access-Token':tokens.accessToken}:{}),...headers},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(60000)});
 const json=await res.json();assert.equal(res.status,expected,`${path}: ${JSON.stringify(json).slice(0,700)}`);return json;
}
const credentials=[];
for(let i=0;i<2;i++) {
 const email=`ios-qa-${randomUUID()}@example.invalid`,password='Qa1!'+randomBytes(20).toString('hex');
 const attrs=[['email',email],['email_verified','true'],['preferred_username','iOS QA'],['given_name','Integration'],['family_name','Test'],['gender','Other']].map(([Name,Value])=>({Name,Value}));
 const user=aws('cognito-idp','admin-create-user',{UserPoolId:config.UserPoolId,Username:email,MessageAction:'SUPPRESS',UserAttributes:attrs}).User;
 aws('cognito-idp','admin-set-user-password',{UserPoolId:config.UserPoolId,Username:user.Username,Password:password,Permanent:true});
 const output='/private/tmp/pinhaoyun-confirm-'+randomUUID()+'.json';
 try {
  const event={version:'1',region:'ap-southeast-2',userPoolId:config.UserPoolId,userName:user.Username,triggerSource:'PostConfirmation_ConfirmSignUp',request:{userAttributes:Object.fromEntries(attrs.map(a=>[a.Name,a.Value]).concat([['sub',user.Attributes.find(a=>a.Name==='sub').Value]]))},response:{}};
  const payload=output+'.payload';writeFileSync(payload,JSON.stringify(event),{mode:0o600});
  const invocation=spawnSync('aws',['lambda','invoke','--function-name','pinhaoyun-ios-dev-postConfirmation','--payload','fileb://'+payload,'--profile','pinhaoyun','--region','ap-southeast-2','--output','json','--no-cli-pager',output],{encoding:'utf8'});
  rmSync(payload,{force:true});
  if(invocation.status!==0)throw new Error(invocation.stderr);
  const result=JSON.parse(invocation.stdout);
  if(result.FunctionError)throw new Error('Post-confirmation function failed: '+readFileSync(output,'utf8').slice(0,700));
 } finally {rmSync(output,{force:true});}
 credentials.push({email,password});
 writeFileSync(new URL('infra/test-credentials.local.json',root),JSON.stringify(credentials,null,2)+'\n',{mode:0o600});
}
writeFileSync(new URL('infra/test-credentials.local.json',root),JSON.stringify(credentials,null,2)+'\n',{mode:0o600});
console.log('Created two isolated QA accounts; email sending suppressed.');
const policy=await request('/api/mobile/policies');assert.equal(policy.version,'2026-10-09-beta-2');
const consent={acceptedTerms:true,acknowledgedPrivacy:true,termsVersion:policy.version,privacyVersion:policy.version};
const sessions=[];
for(const c of credentials) {
 const token=await request('/api/mobile/auth/sign-in',c);assert.equal(token.requiresConsent,true);
 await request('/api/user/profile',undefined,token,401);
 await request('/api/mobile/consent',consent,token);sessions.push(token);
}
let [owner,other]=sessions;
owner=await request('/api/mobile/auth/refresh',{refreshToken:owner.refreshToken,username:owner.username});assert.equal(owner.requiresConsent,false);
const browser=await fetch(base+'/api/auth/sign-in',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(credentials[0]),signal:AbortSignal.timeout(60000)});
assert.equal(browser.status,200,'Legacy browser sign-in');
const cookie=browser.headers.getSetCookie().map(value=>value.split(';')[0]).join('; ');
await request('/api/user/profile',undefined,undefined,200,{Cookie:cookie});
await request('/api/user/profile',undefined,undefined,401,{Cookie:cookie,Authorization:'Bearer forged'});
await request('/api/user/profile',undefined,{...owner,accessToken:other.accessToken},401);
console.log('Verified mobile consent/refresh, browser Cookie compatibility, forged Bearer rejection and token identity binding.');
const bytes=readFileSync(new URL('App/Resources/Assets.xcassets/AppIcon.appiconset/icon.png',root));
const hash=createHash('sha256').update(bytes.subarray(0,10*1024*1024)).digest('hex')+'-'+bytes.length;
const photoId=randomUUID();
const initial=await request('/api/videos/multipart/init',{fileName:'QA-original.png',contentType:'image/png',size:bytes.length,contentHash:hash,mediaType:'PHOTO',mediaRole:'image',photoId},owner);
assert.equal(initial.duplicate,false);
const url=await request('/api/videos/multipart/part',{key:initial.key,uploadId:initial.uploadId,partNumber:1},owner);
const upload=await fetch(url.uploadUrl,{method:'PUT',body:bytes,signal:AbortSignal.timeout(60000)});
assert.equal(upload.status,200,'Presigned upload failed');const etag=upload.headers.get('etag');assert.ok(etag);
const before=await request('/api/videos/multipart/status',{key:initial.key,uploadId:initial.uploadId},owner);assert.equal(before.parts[0].etag,etag);
await request('/api/videos/multipart/complete',{key:initial.key,uploadId:initial.uploadId,parts:[{partNumber:1,etag}]},owner);
const after=await request('/api/videos/multipart/status',{key:initial.key,uploadId:initial.uploadId},owner);assert.equal(after.completed,true);
const notify={bucket:initial.bucket,key:initial.key,originalName:'QA-original.png',contentType:'image/png',size:bytes.length,contentHash:hash,mediaType:'PHOTO',mediaRole:'image',photoId};
await request('/api/videos/notify',notify,owner);await request('/api/videos/notify',notify,owner);
const profile=await request('/api/user/profile',undefined,owner);assert.equal(profile.usedBytes,bytes.length);assert.equal(profile.photoCount,1);
const duplicate=await request('/api/videos/multipart/init',{fileName:'QA-original.png',contentType:'image/png',size:bytes.length,contentHash:hash,mediaType:'PHOTO',photoId:randomUUID()},owner);assert.equal(duplicate.duplicate,true);
await request('/api/media/urls',{id:photoId,type:'PHOTO'},other,404);
await request('/api/videos/multipart/status',{key:initial.key,uploadId:initial.uploadId},other,403);
const links=await request('/api/media/urls',{id:photoId,type:'PHOTO'},owner);assert.ok(links.originalPhotoUrl);
const downloaded=Buffer.from(await (await fetch(links.originalPhotoUrl)).arrayBuffer());assert.deepEqual(downloaded,bytes);
const list=await request('/api/videos/list?limit=20',undefined,owner);assert.ok(list.videos.some(item=>item.id===photoId));
console.log('Verified real multipart upload, resume status, idempotent accounting, duplicate detection, download integrity and cross-account isolation.');
writeFileSync(new URL('infra/integration-state.local.json',root),JSON.stringify({photoId,key:initial.key,owner,other,bytes:bytes.length},null,2)+'\n',{mode:0o600});
console.log('Fixtures remain available for native UI testing. Delete them using the account-erasure integration check afterwards.');
