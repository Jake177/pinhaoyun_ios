import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdtempSync,rmSync} from 'node:fs';
import {randomUUID,randomBytes} from 'node:crypto';
import assert from 'node:assert/strict';
const root=new URL('../',import.meta.url),config=JSON.parse(readFileSync(new URL('infra/outputs.local.json',root))),fixtures=JSON.parse(readFileSync(new URL('infra/test-credentials.local.json',root))),state=JSON.parse(readFileSync(new URL('infra/integration-state.local.json',root)));
if(!config.MediaTable.startsWith('pinhaoyun-ios-dev-') || !fixtures.every(v=>/^ios-qa-.*@example\.invalid$/.test(v.email)))throw new Error('Disposable development fixtures only');
const base='http://127.0.0.1:3000';
async function api(path,body,token,expected=200) {
 const res=await fetch(base+path,{method:body===undefined?'GET':'POST',headers:{...(body?{'Content-Type':'application/json'}:{}),...(token?{Authorization:'Bearer '+token.idToken,'X-Access-Token':token.accessToken}:{})},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(60000)});
 const json=await res.json();assert.equal(res.status,expected,`${path}: ${JSON.stringify(json).slice(0,500)}`);return json;
}
function aws(service,operation,input,extra=[]) {
 const dir=mkdtempSync('/private/tmp/pinhaoyun-erasure-');
 try {
  const path=dir+'/input.json';writeFileSync(path,JSON.stringify(input),{mode:0o600});
  const r=spawnSync('aws',[service,operation,...extra,'--profile','pinhaoyun','--region','ap-southeast-2','--no-cli-pager','--output','json','--cli-input-json','file://'+path],{encoding:'utf8'});
  if(r.status!==0)throw new Error(r.stderr.slice(0,1000));return r.stdout.trim()?JSON.parse(r.stdout):{};
 } finally {rmSync(dir,{recursive:true,force:true});}
}
const owner=await api('/api/mobile/auth/sign-in',fixtures[0]);
await api('/api/videos/delete',{mediaId:state.photoId,mediaType:'PHOTO'},owner);
await api('/api/videos/delete',{mediaId:state.photoId,mediaType:'PHOTO'},owner);
let removed=false;
for(let i=0;i<20;i++) {
 await new Promise(r=>setTimeout(r,2000));
 const row=aws('dynamodb','get-item',{TableName:config.MediaTable,Key:{email:{S:fixtures[0].email},sk:{S:'PHOTO#'+state.photoId}},ConsistentRead:true});
 if(row.Item?.status?.S==='DELETED'){removed=true;break;}
}
assert.ok(removed,'Media deletion worker did not finish');
const profile=await api('/api/user/profile',undefined,owner);assert.equal(profile.usedBytes,0);assert.equal(profile.photoCount,0);
await api('/api/media/urls',{id:state.photoId,type:'PHOTO'},owner,404);
console.log('Verified repeated media deletion, quota accounting and hidden tombstone.');
const requestId=randomUUID(),receipt=randomBytes(32).toString('base64url');
const request={confirm:true,requestId,receipt};
const deletion=await api('/api/user/delete-account',request,owner,202);
const again=await api('/api/user/delete-account',request,owner,202);assert.equal(again.requestId,requestId);assert.equal(again.receipt,receipt);
await api('/api/user/profile',undefined,owner,401);
await api('/api/user/deletion-status',{requestId,receipt:'x'.repeat(43)},undefined,404);
const proof=await api('/api/user/deletion-status',{requestId,receipt});assert.notEqual(proof.state,'COMPLETE');
writeFileSync(new URL('infra/erasure-state.local.json',root),JSON.stringify({deletion,owner,other:state.other,email:fixtures[0].email},null,2),{mode:0o600});
console.log('Verified repeat-safe erasure receipt, immediate access revocation and proof isolation.');
console.log('Server-side purge is running; check completion with scripts/erasure-completion.mjs.');
