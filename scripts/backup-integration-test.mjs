import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdtempSync,rmSync} from 'node:fs';
import {randomBytes,randomUUID,createHash} from 'node:crypto';
import {deflateSync} from 'node:zlib';
import assert from 'node:assert/strict';
const root=new URL('../',import.meta.url);
const config=JSON.parse(readFileSync(new URL('infra/outputs.local.json',root),'utf8'));
const deployment=JSON.parse(readFileSync(new URL('infra/api-output.local.json',root),'utf8'));
const base=process.env.TEST_API_BASE_URL||'https://'+deployment.ServiceUrl;
assert.ok(config.MediaTable.startsWith('pinhaoyun-ios-dev-')&&config.OriginalBucket.startsWith('pinhaoyun-ios-dev-'));
assert.ok(['http://127.0.0.1:3000','https://'+deployment.ServiceUrl].includes(base),'Only known development endpoints');
const credentials=JSON.parse(readFileSync(new URL('infra/test-credentials.local.json',root),'utf8'));
assert.ok(credentials.length>=2&&credentials.every(value=>value.email.startsWith('ios-qa-')&&value.email.endsWith('@example.invalid')));
function aws(service,operation,input,extra=[]) {
 const folder=mkdtempSync('/private/tmp/pinhaoyun-backup-');
 try {
  const path=folder+'/input.json';writeFileSync(path,JSON.stringify(input),{mode:0o600});
  // Lambda invoke uses a streaming CLI command without --cli-input-json support.
  const jsonInput=service==='lambda'&&operation==='invoke'?[]:['--cli-input-json','file://'+path];
  const result=spawnSync('aws',[service,operation,...extra,'--profile','pinhaoyun','--region','ap-southeast-2','--output','json','--no-cli-pager',...jsonInput],{encoding:'utf8'});
  if(result.status!==0)throw new Error(`${service}/${operation} failed`);
  return result.stdout.trim()?JSON.parse(result.stdout):{};
 } finally {rmSync(folder,{recursive:true,force:true});}
}
assert.equal(aws('sts','get-caller-identity',{}).Account,'883086653724');
async function request(path,body,tokens,expected=200,extra={}) {
 const response=await fetch(base+path,{method:body===undefined?'GET':'POST',headers:{...(body?{'Content-Type':'application/json'}:{}),...(tokens?{Authorization:'Bearer '+tokens.idToken,'X-Access-Token':tokens.accessToken}:{}),...extra},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(60000)});
 assert.equal(response.status,expected,`${path}: unexpected HTTP status (response body intentionally omitted)`);
 return response.json();
}
function png() {
 function chunk(name,data) {
  const body=Buffer.concat([Buffer.from(name),data]);let crc=0xffffffff;
  for(const value of body){crc^=value;for(let bit=0;bit<8;bit++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}
  const length=Buffer.alloc(4);length.writeUInt32BE(data.length);const tail=Buffer.alloc(4);tail.writeUInt32BE((crc^0xffffffff)>>>0);return Buffer.concat([length,body,tail]);
 }
 const header=Buffer.alloc(13);header.writeUInt32BE(16);header.writeUInt32BE(16,4);header[8]=8;header[9]=2;
 const pixels=Buffer.concat(Array.from({length:16},()=>Buffer.concat([Buffer.from([0]),randomBytes(48)])));
 return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',header),chunk('IDAT',deflateSync(pixels)),chunk('IEND',Buffer.alloc(0))]);
}
const policy=await request('/api/mobile/policies');assert.equal(policy.version,'2026-10-09-beta-2');
const sessions=[];
for(const credential of credentials.slice(0,2)) {
 const token=await request('/api/mobile/auth/sign-in',credential);
 assert.equal(JSON.parse(Buffer.from(token.idToken.split('.')[1],'base64url')).iss,`https://cognito-idp.ap-southeast-2.amazonaws.com/${config.UserPoolId}`);
 if(token.requiresConsent)await request('/api/mobile/consent',{acceptedTerms:true,acknowledgedPrivacy:true,termsVersion:policy.version,privacyVersion:policy.version},token);
 sessions.push(token);
}
const [owner,other]=sessions;
const before=await request('/api/user/profile',undefined,owner);
function reservedBytes() {
 const result=aws('dynamodb','get-item',{TableName:config.MediaTable,Key:{email:{S:owner.email},sk:{S:'PROFILE'}},ConsistentRead:true});
 return Number(result.Item?.reservedBytes?.N||0);
}
const beforeReserved=reservedBytes();
const bytes=png(),hash=createHash('sha256').update(bytes).digest('hex')+'-'+bytes.length;
const initBody={fileName:'QA-backup.png',contentType:'image/png',size:bytes.length,contentHash:hash,mediaType:'PHOTO',mediaRole:'image',uploadSource:'automatic'};
await request('/api/videos/multipart/init',{...initBody,size:0.5},owner,400);
const firstBody={...initBody,photoId:randomUUID(),requestId:randomUUID()};
const first=await request('/api/videos/multipart/init',firstBody,owner);
const replay=await request('/api/videos/multipart/init',firstBody,owner);
assert.equal(replay.uploadId,first.uploadId);assert.equal(replay.key,first.key);assert.equal(replay.resumed,true);
const pending=await request('/api/videos/multipart/init',{...initBody,photoId:randomUUID()},owner);
async function put(start,data=bytes) {
 const part=await request('/api/videos/multipart/part',{key:start.key,uploadId:start.uploadId,partNumber:1},owner);
 const response=await fetch(part.uploadUrl,{method:'PUT',body:data,signal:AbortSignal.timeout(60000)});
 assert.equal(response.status,200);return {partNumber:1,etag:response.headers.get('etag')};
}
async function commit(start,part,payload=initBody) {
 await request('/api/videos/multipart/complete',{key:start.key,uploadId:start.uploadId,parts:[part]},owner);
 const body={...payload,bucket:start.bucket,key:start.key,photoId:start.photoId,originalName:payload.fileName,fileLastModified:'2008-05-01T02:00:00Z'};
 const result=await request('/api/videos/notify',body,owner);await request('/api/videos/notify',body,owner);return result;
}
const firstPart=await put(first),pendingPart=await put(pending);await commit(first,firstPart);
let links=await request('/api/media/urls',{id:first.photoId,type:'PHOTO'},owner);
assert.deepEqual(Buffer.from(await(await fetch(links.originalPhotoUrl||links.originalUrl)).arrayBuffer()),bytes);
await request('/api/media/urls',{id:first.photoId,type:'PHOTO'},other,404);
await request('/api/user/profile',undefined,{...owner,accessToken:other.accessToken},401);
await request('/api/videos/delete',{mediaId:first.photoId,mediaType:'PHOTO'},owner);
const stopped=await request('/api/videos/multipart/complete',{key:pending.key,uploadId:pending.uploadId,parts:[pendingPart]},owner,410);assert.equal(stopped.code,'CLOUD_DELETED');
const skipped=await request('/api/videos/multipart/init',{...initBody,photoId:randomUUID()},owner);assert.equal(skipped.skipped,true);
const temp=mkdtempSync('/private/tmp/pinhaoyun-late-');
try {
 const file=temp+'/late.png';writeFileSync(file,bytes,{mode:0o600});
 aws('s3api','put-object',{Bucket:config.OriginalBucket,Key:pending.key,ContentType:'image/png',Metadata:{'owner-sub':owner.sub,'upload-source':'automatic','backup-hash':hash}},['--body',file]);
 const deadline=Date.now()+60000;let gone=false;
 while(Date.now()<deadline) {
  const found=aws('s3api','list-objects-v2',{Bucket:config.OriginalBucket,Prefix:pending.key}).Contents||[];
  if(!found.some(value=>value.Key===pending.key)){gone=true;break;}
  await new Promise(done=>setTimeout(done,1000));
 }
 assert.ok(gone,'Late automatic original must be removed');
 const result=aws('dynamodb','get-item',{TableName:config.MediaTable,Key:{email:{S:owner.email},sk:{S:'PHOTO#'+pending.photoId}},ConsistentRead:true});
 assert.ok(!result.Item||result.Item.status?.S==='DELETED');
} finally {rmSync(temp,{recursive:true,force:true});}
const deadline=Date.now()+60000;let settled;
while(Date.now()<deadline) {
 settled=await request('/api/user/profile',undefined,owner);
 if(settled.usedBytes===before.usedBytes&&reservedBytes()===beforeReserved)break;
 await new Promise(done=>setTimeout(done,1000));
}
assert.equal(settled.usedBytes,before.usedBytes);assert.equal(reservedBytes(),beforeReserved);
const restored=await request('/api/videos/multipart/init',{...initBody,uploadSource:'manual',photoId:randomUUID()},owner);
assert.equal(restored.duplicate,false);await commit(restored,await put(restored));
const duplicate=await request('/api/videos/multipart/init',{...initBody,photoId:randomUUID()},owner);assert.equal(duplicate.duplicate,true);
const after=await request('/api/user/profile',undefined,owner);assert.equal(after.usedBytes-before.usedBytes,bytes.length);assert.equal(reservedBytes(),beforeReserved);
links=await request('/api/media/urls',{id:restored.photoId,type:'PHOTO'},owner);assert.deepEqual(Buffer.from(await(await fetch(links.originalPhotoUrl||links.originalUrl)).arrayBuffer()),bytes);
// The localhost Web surface shares only the isolated pool with this API.
const browser=await fetch('http://127.0.0.1:3000/api/auth/sign-in',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(credentials[0]),signal:AbortSignal.timeout(60000)});
assert.equal(browser.status,200);const cookie=browser.headers.getSetCookie().map(value=>value.split(';')[0]).join('; ');
await request('/api/user/profile',undefined,undefined,200,{Cookie:cookie});
await request('/api/user/profile',undefined,undefined,401,{Cookie:cookie,Authorization:'Bearer forged'});
// Two requests admitted before either content hash was committed must charge once.
const concurrentBytes=png(),concurrentHash=createHash('sha256').update(concurrentBytes).digest('hex')+'-'+concurrentBytes.length;
const concurrentBody={...initBody,contentHash:concurrentHash,size:concurrentBytes.length};
const concurrentA=await request('/api/videos/multipart/init',{...concurrentBody,photoId:randomUUID(),requestId:randomUUID()},owner);
const concurrentB=await request('/api/videos/multipart/init',{...concurrentBody,photoId:randomUUID(),requestId:randomUUID()},owner);
const partA=await put(concurrentA,concurrentBytes),partB=await put(concurrentB,concurrentBytes);
await commit(concurrentA,partA,concurrentBody);
const joined=await commit(concurrentB,partB,concurrentBody);assert.equal(joined.duplicate,true);assert.equal(joined.photoId,concurrentA.photoId);
assert.equal((await request('/api/user/profile',undefined,owner)).usedBytes-after.usedBytes,concurrentBytes.length);
assert.equal(reservedBytes(),beforeReserved);
await request('/api/videos/delete',{mediaId:concurrentA.photoId,mediaType:'PHOTO'},owner);
// Preserve a completed-but-unfinalized original across the reservation expiry,
// then verify explicit cancellation releases its quota and drops late events.
const cancelledBytes=png(),cancelledHash=createHash('sha256').update(cancelledBytes).digest('hex')+'-'+cancelledBytes.length;
const cancelledBody={...initBody,contentHash:cancelledHash,size:cancelledBytes.length,photoId:randomUUID(),requestId:randomUUID()};
const cancelled=await request('/api/videos/multipart/init',cancelledBody,owner);
try {
const cancelledPart=await put(cancelled,cancelledBytes);
await request('/api/videos/multipart/complete',{key:cancelled.key,uploadId:cancelled.uploadId,parts:[cancelledPart]},owner);
aws('dynamodb','update-item',{TableName:config.MediaTable,Key:{email:{S:owner.email},sk:{S:'RESERVE#PHOTO#'+cancelled.photoId}},UpdateExpression:'SET expiresAt = :past',ExpressionAttributeValues:{':past':{N:String(Math.floor(Date.now()/1000)-3600)}}});
const invocationDir=mkdtempSync('/private/tmp/pinhaoyun-sweep-');
try {
 const payload=invocationDir+'/event.json',output=invocationDir+'/response.json';writeFileSync(payload,'{}',{mode:0o600});
 const functionName='pinhaoyun-ios-dev-cleanupUploads';
 const result=aws('lambda','invoke',{},['--function-name',functionName,'--payload','fileb://'+payload,output]);assert.equal(result.FunctionError,undefined);
} finally {rmSync(invocationDir,{recursive:true,force:true});}
const lease=aws('dynamodb','get-item',{TableName:config.MediaTable,Key:{email:{S:owner.email},sk:{S:'RESERVE#PHOTO#'+cancelled.photoId}},ConsistentRead:true});
assert.ok(Number(lease.Item?.expiresAt?.N)>Date.now()/1000);
} finally {
 await request('/api/videos/multipart/abort',{key:cancelled.key,uploadId:cancelled.uploadId},owner);
}
assert.equal(aws('dynamodb','get-item',{TableName:config.MediaTable,Key:{email:{S:owner.email},sk:{S:'RESERVE#PHOTO#'+cancelled.photoId}},ConsistentRead:true}).Item,undefined);
const finalDeadline=Date.now()+60000;
while(Date.now()<finalDeadline) {
 if((await request('/api/user/profile',undefined,owner)).usedBytes===after.usedBytes&&reservedBytes()===beforeReserved)break;
 await new Promise(done=>setTimeout(done,1000));
}
assert.equal((await request('/api/user/profile',undefined,owner)).usedBytes,after.usedBytes);assert.equal(reservedBytes(),beforeReserved);
const proof={checkedAt:new Date().toISOString(),endpoint:base,source:'script-and-isolated-AWS',physicalDevice:false,bytes:bytes.length,passed:['automatic-upload','byte-integrity','idempotent-quota','cross-owner','identity-binding','deleted-content-skip','in-flight-cleanup','late-event-cleanup','manual-restore','duplicate-after-restore','shared-Web-cookie','invalid-bearer-no-fallback']};
proof.passed.push('lost-init-response-replay','concurrent-duplicate-finalization','completed-original-expiry-recovery','cancel-after-remote-completion');
writeFileSync(new URL('infra/backup-proof.local.json',root),JSON.stringify(proof,null,2)+'\n',{mode:0o600});
console.log('Passed isolated backup lifecycle, exact quota, late-event cleanup, manual restore, Web Cookie and Bearer isolation. No credentials printed.');
