import test from 'node:test';
import assert from 'node:assert/strict';
import {createVeteranCareRevocationStatusReader as create} from './veteran-care-revocation-status-v1.mjs';
import {VETERAN_CARE_ISSUER as issuer} from './veteran-care-identity-v1.mjs';
import {VETERAN_CARE_PROJECT_URL as url} from './veteran-care-project-boundary-v1.mjs';
const appId='shine.veteran-care',providerId='supabase:veteran-care';
const shineId='11111111-1111-4111-8111-111111111111',authSubject='22222222-2222-4222-8222-222222222222',sessionId='33333333-3333-4333-8333-333333333333';
const grantId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',deliveryId='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',requestId='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const base=()=>({complete:true,grantId,appId,ownerShineId:shineId,scope:'veteran-care.record.read',purpose:'veteran-care.appointment-preparation',
  withdrawal:{status:'recorded',sequenceNo:9},delivery:{deliveryId,appId,afterSequence:3,sequenceNos:[5,9,12]},
  acknowledgement:{deliveryId,appId,requestId,outcome:'advanced',sequenceNo:12,checkpointSequence:12}});
const input=()=>({authContext:{appToken:'synthetic',jwt:'e30.'+Buffer.from(JSON.stringify({iss:issuer})).toString('base64url')+'.c2ln'},request:{grantId}});
function fixture({evidence=base(),session='active',aud='authenticated',projection}={}){
  const queries=[];
  return {queries,read:create({appId,providerId,clock:()=>1500000,
    configuration:{mode:'veteran_care',issuer,authProjectUrl:url,databaseProjectUrl:url,storageProjectUrl:url},
    verifyAppCaller:async()=>({appId}),verifyIdentity:async()=>({shineId,authSubject,providerId}),
    auth:{getClaims:async()=>({data:{claims:{iss:issuer,aud,role:'authenticated',sub:authSubject,session_id:sessionId,exp:3000}}})},
    getSessionState:async()=>({status:session,sessionId,authSubject,issuer,expiresAt:null}),
    getGrantRevocationEvidence:async q=>{queries.push(q);return projection?projection(q):evidence;}})};
}
test('correlated withdrawal delivered batch and acknowledgement yield bounded acknowledged status',async()=>{
  const f=fixture();const r=await f.read(input());assert.equal(r.status,'acknowledged');assert.equal(r.acknowledgementVerified,true);assert.equal(r.consumerEnforcementVerified,false);
  assert.deepEqual(f.queries,[{appId,ownerShineId:shineId,grantId}]);
  for(const key of ['grantId','ownerShineId','deliveryId','requestId','sequenceNo','checkpointSequence'])assert.equal(Object.hasOwn(r,key),false);
});
test('not recorded withdrawal delivered and acknowledged are distinct states',async()=>{
  for(const [extra,status] of [[{withdrawal:{status:'not-recorded'},delivery:null,acknowledgement:null},'not-recorded'],[{delivery:null,acknowledgement:null},'withdrawal-recorded'],[{acknowledgement:null},'delivered'],[{},'acknowledged']]){
    const r=await fixture({evidence:{...base(),...extra}}).read(input());assert.equal(r.status,status);assert.equal(r.acknowledgementVerified,status==='acknowledged');
  }
});
test('missing incomplete evidence cannot imply that no withdrawal exists',async()=>{
  for(const evidence of [null,{}, {...base(),complete:false},{...base(),withdrawal:undefined},{...base(),delivery:undefined},{...base(),acknowledgement:undefined}]){
    const r=await fixture({evidence}).read(input());assert.equal(r.acknowledgementVerified,false);assert.ok(['denied','unavailable'].includes(r.status));
  }
});
test('current identity and audience failures stop before private evidence lookup',async()=>{
  for(const config of [{session:'inactive'},{aud:'other'}]){const f=fixture(config);assert.equal((await f.read(input())).status,'denied');assert.equal(f.queries.length,0);}
});
test('cross owner app grant scope and purpose evidence cannot be reported',async()=>{
  for(const extra of [{ownerShineId:requestId},{appId:'shine.other'},{grantId:requestId},{scope:'veteran-care.record.write'},{purpose:'other'}])assert.equal((await fixture({evidence:{...base(),...extra}}).read(input())).status,'denied');
});
test('exact plain grant input rejects forged routing and accessors before lookup',async()=>{
  const accessor={};Object.defineProperty(accessor,'grantId',{get(){throw Error('must not execute');}});
  for(const request of [null,{},{grantId:'bad'},{grantId,appId},{grantId,[Symbol('extra')]:true},accessor,Object.create({grantId})]){
    const f=fixture();assert.equal((await f.read({...input(),request})).status,'denied');assert.equal(f.queries.length,0);
  }
});
test('delivery must be ordered scoped and contain the exact withdrawal sequence',async()=>{
  for(const extra of [{appId:'shine.other'},{deliveryId:'bad'},{afterSequence:9},{sequenceNos:[5,12]},{sequenceNos:[9,5,12]},{sequenceNos:[5,9,9]},{sequenceNos:[5,NaN,12]},{sequenceNos:[]},{sequenceNos:new Array(101).fill(9)}]){
    const e=base();e.delivery={...e.delivery,...extra};const r=await fixture({evidence:e}).read(input());assert.equal(r.status,'unavailable');assert.equal(r.acknowledgementVerified,false);
  }
});
test('ack must match app delivery terminal sequence and durable checkpoint',async()=>{
  for(const extra of [{appId:'shine.other'},{deliveryId:requestId},{requestId:'bad'},{outcome:'denied'},{sequenceNo:9},{checkpointSequence:9},{checkpointSequence:Infinity}]){
    const e=base();e.acknowledgement={...e.acknowledgement,...extra};assert.equal((await fixture({evidence:e}).read(input())).status,'unavailable');
  }
});
test('ack without matching delivery and withdrawal is not trusted',async()=>{
  for(const extra of [{delivery:null},{withdrawal:{status:'not-recorded'}},{withdrawal:{status:'recorded',sequenceNo:0}}])assert.equal((await fixture({evidence:{...base(),...extra}}).read(input())).status,'unavailable');
});
test('already acked with later checkpoint still needs matching receipt coverage',async()=>{
  const e=base();e.acknowledgement.outcome='already-acked';e.acknowledgement.checkpointSequence=20;
  assert.equal((await fixture({evidence:e}).read(input())).status,'acknowledged');
});
test('consumer enforcement flags and caller evidence cannot upgrade output',async()=>{
  const e={...base(),consumerEnforcementVerified:true};const q=input();q.acknowledged=true;q.ownerShineId=requestId;q.evidence=e;
  const r=await fixture({evidence:{...e,acknowledgement:null}}).read(q);assert.equal(r.status,'delivered');assert.equal(r.consumerEnforcementVerified,false);
});
test('outage withholds status and input target is captured before await',async()=>{
  assert.equal((await fixture({projection:async()=>{throw Error('offline');}}).read(input())).status,'unavailable');
  const q=input();const f=fixture({projection:async lookup=>{q.request.grantId=requestId;assert.equal(lookup.grantId,grantId);return base();}});
  assert.equal((await f.read(q)).status,'acknowledged');
});
test('projection data accessors are rejected without running them',async()=>{
  const e=base();Object.defineProperty(e.acknowledgement,'checkpointSequence',{get(){throw Error('unexpected');}});
  assert.equal((await fixture({evidence:e}).read(input())).status,'unavailable');
});
test('read requires authoritative projection and has no mutation or model adapters',()=>{
  assert.throws(()=>create({}),TypeError);assert.doesNotThrow(()=>fixture());
});
