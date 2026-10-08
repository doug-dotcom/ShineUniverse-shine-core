import test from 'node:test';
import assert from 'node:assert/strict';
import {createVeteranCareRevocationService as create} from './veteran-care-revocation-v1.mjs';
import {VETERAN_CARE_ISSUER as issuer} from './veteran-care-identity-v1.mjs';
import {VETERAN_CARE_PROJECT_URL as url} from './veteran-care-project-boundary-v1.mjs';
const appId='shine.veteran-care',providerId='supabase:veteran-care';
const shineId='11111111-1111-4111-8111-111111111111',authSubject='22222222-2222-4222-8222-222222222222',sessionId='33333333-3333-4333-8333-333333333333';
const grantId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',requestId='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',eventId='cccccccc-cccc-4ccc-8ccc-cccccccccccc',revocationId='dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const now=Date.parse('2026-10-08T01:30:00.000Z');
const input=()=>({authContext:{appToken:'synthetic',jwt:'e30.'+Buffer.from(JSON.stringify({iss:issuer})).toString('base64url')+'.c2ln'},request:{grantId,revoke:true}});
function fixture({descriptor={},outcome={},write,session='active',aud='authenticated',options={}}={}){
  const writes=[],reads=[],ids=[requestId,eventId,revocationId];
  const service=create({appId,providerId,clock:()=>now,revocationClock:()=>now,idFactory:()=>ids.shift(),
    configuration:{mode:'veteran_care',issuer,authProjectUrl:url,databaseProjectUrl:url,storageProjectUrl:url},
    verifyAppCaller:async()=>({appId}),verifyIdentity:async()=>({shineId,authSubject,providerId}),
    auth:{getClaims:async()=>({data:{claims:{iss:issuer,aud,role:'authenticated',sub:authSubject,session_id:sessionId,exp:now/1000+3600}}})},
    getSessionState:async()=>({status:session,sessionId,authSubject,issuer,expiresAt:null}),
    getGrantDescriptor:async q=>{reads.push(q);return {grantId,appId,ownerShineId:shineId,scope:'veteran-care.record.read',purpose:'veteran-care.appointment-preparation',...descriptor};},
    revokeAccessGrant:async q=>{writes.push(q);if(write)return write(q);return {grantId,requestId,outcome:'revoked',reason_code:'grant-revoked-by-user',outboxRecorded:true,...outcome};},...options});
  return {service,writes,reads};
}
test('verified VC withdrawal reaches generic Foundation mutation with server identifiers',async()=>{
  const {service,writes,reads}=fixture();const result=await service(input());
  assert.equal(result.status,'revoked');assert.equal(result.propagationStatus,'outbox-recorded');assert.equal(result.consumerEnforcementVerified,false);
  assert.deepEqual(reads,[{appId,ownerShineId:shineId,grantId}]);
  assert.deepEqual(writes,[{eventId,revocationId,requestId,grantId,ownerShineId:shineId,appId,occurredAt:new Date(now).toISOString()}]);
  assert.equal(Object.hasOwn(result,'grantId'),false);assert.equal(Object.hasOwn(result,'ownerShineId'),false);
});
test('withdrawal requires explicit true and exact plain grant request',async()=>{
  const accessor={revoke:true};Object.defineProperty(accessor,'grantId',{get(){throw Error('not evaluated');}});
  for(const request of [undefined,{grantId},{grantId,revoke:false},{grantId,revoke:true,appId},{grantId:'bad',revoke:true},accessor,Object.create({grantId,revoke:true}),{grantId,revoke:true,[Symbol('extra')]:true}]){
    const f=fixture();assert.equal((await f.service({...input(),request})).status,'denied');assert.equal(f.reads.length,0);assert.equal(f.writes.length,0);
  }
});
test('inactive session and wrong audience stop before grant metadata or mutation',async()=>{
  for(const options of [{session:'inactive'},{aud:'other'}]){const f=fixture(options);assert.equal((await f.service(input())).status,'denied');assert.equal(f.reads.length,0);assert.equal(f.writes.length,0);}
});
test('cross owner app grant scope and purpose cannot reach mutation',async()=>{
  for(const descriptor of [{ownerShineId:eventId},{appId:'shine.other'},{grantId:eventId},{scope:'veteran-care.record.write'},{purpose:'other'}]){
    const f=fixture({descriptor});assert.equal((await f.service(input())).status,'denied');assert.equal(f.writes.length,0);
  }
});
test('caller cannot override verified owner server dates or request identifiers',async()=>{
  const f=fixture();const q=input();q.ownerShineId=eventId;q.appId='shine.other';q.requestId=eventId;q.requestedAt='2999-01-01';
  assert.equal((await f.service(q)).status,'revoked');assert.equal(f.writes[0].ownerShineId,shineId);assert.equal(f.writes[0].requestId,requestId);
});
test('expired and already revoked target can still be withdrawn without access grant evaluation',async()=>{
  const f=fixture({descriptor:{status:'revoked',expiresAt:'2020-01-01T00:00:00.000Z'},outcome:{outcome:'already-revoked',reason_code:'grant-already-revoked'}});
  assert.equal((await f.service(input())).status,'already-revoked');assert.equal(f.writes.length,1);
});
test('no consumer acknowledgement or enforcement is inferred from durable outbox confirmation',async()=>{
  const f=fixture({outcome:{consumerEnforcementVerified:true,acknowledged:true}});const r=await f.service(input());
  assert.equal(r.consumerEnforcementVerified,false);assert.equal(r.acknowledged,undefined);assert.equal(r.revocationId,undefined);
});
test('missing or wrong persistence correlation withholds success',async()=>{
  for(const outcome of [{grantId:undefined},{grantId:eventId},{requestId:undefined},{requestId:eventId},{outboxRecorded:false},{outboxRecorded:undefined},{outcome:'denied'},{reason_code:''}]){
    const f=fixture({outcome});const r=await f.service(input());assert.equal(r.status,'unavailable');assert.equal(r.propagationStatus,'not-verified');assert.equal(r.requestId,undefined);
  }
});
test('write failure and unknown commit do not claim withdrawal succeeded',async()=>{
  for(const write of [async()=>{throw Error('timeout');},async()=>null]){const f=fixture({write});assert.equal((await f.service(input())).status,'unavailable');}
});
test('metadata outage stops before mutation',async()=>{
  const f=fixture({options:{getGrantDescriptor:async()=>{throw Error('offline');}}});assert.equal((await f.service(input())).status,'unavailable');assert.equal(f.writes.length,0);
});
test('invalid server identifiers and clock stop before writes',async()=>{
  for(const options of [{idFactory:()=> 'bad'},{revocationClock:()=>NaN},{revocationClock:()=>-1}]){
    const f=fixture({options});assert.equal((await f.service(input())).status,'unavailable');assert.equal(f.writes.length,0);
  }
});
test('grant input is captured before awaiting metadata',async()=>{
  const q=input();const f=fixture({options:{getGrantDescriptor:async()=>{q.request.grantId=eventId;return {grantId,appId,ownerShineId:shineId,scope:'veteran-care.record.read',purpose:'veteran-care.appointment-preparation'};}}});
  assert.equal((await f.service(q)).status,'revoked');assert.equal(f.writes[0].grantId,grantId);
});
test('concurrent invocations keep identity target request and confirmations isolated',async()=>{
  const {service}=fixture({options:{idFactory:()=>crypto.randomUUID(),revokeAccessGrant:async q=>{await Promise.resolve();return {grantId:q.grantId,requestId:q.requestId,outcome:'revoked',reason_code:'ok',outboxRecorded:true};}}});
  const results=await Promise.all([service(input()),service(input())]);assert.equal(results.every(r=>r.status==='revoked'),true);assert.notEqual(results[0].requestId,results[1].requestId);
});
test('mandatory authorities cannot be omitted and withdrawal has no Defence or AI gate',()=>{
  assert.throws(()=>create({}),TypeError);assert.doesNotThrow(()=>fixture());
});
