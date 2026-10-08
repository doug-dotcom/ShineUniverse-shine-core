import test from 'node:test';
import assert from 'node:assert/strict';
import {createVeteranCareGuardedRead as create} from './veteran-care-guarded-read-v1.mjs';
import {VETERAN_CARE_ISSUER as issuer} from './veteran-care-identity-v1.mjs';
import {VETERAN_CARE_PROJECT_URL as url} from './veteran-care-project-boundary-v1.mjs';
const start='1970-01-01T00:16:40.000Z',end='1970-01-01T00:33:20.000Z';
const timed=()=>({notBefore:start,expiresAt:end,consentWindow:{startsAt:start,expiresAt:end}});
const appId='shine.veteran-care',recordId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',preparationId='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',grantId='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const shineId='11111111-1111-4111-8111-111111111111',authSubject='22222222-2222-4222-8222-222222222222',sessionId='33333333-3333-4333-8333-333333333333';
const purpose='veteran-care.appointment-preparation',scope='veteran-care.record.read',resourceCategory='veteran-care.record';
const grant=()=>({grantId,appId,ownerShineId:shineId,scope,purpose,status:'active',resourceSelector:{resourceId:recordId,resourceVersion:3},purposeBinding:{kind:'appointment-preparation',preparationId},...timed()});
const input=()=>({authContext:{appToken:'synthetic',jwt:'e30.'+Buffer.from(JSON.stringify({iss:issuer})).toString('base64url')+'.c2ln'},request:{capabilityId:'veteran-care.selected_record_read',input:{recordId,recordVersion:3}},purposeContext:{preparationId}});
const stamp=(revision=1)=>({appId,ownerShineId:shineId,revision});
const context=()=>({complete:true,appManifest:{appId,foundation:{requestedScopes:[{scope,purpose,resourceCategory}]}},grants:[grant()],defenceDecision:'allow',permissionSnapshot:stamp()});
function fixture({snapshot=context(),current=stamp(),lookup,prepare,options={}}={}){
  const calls=[],preparations=[];
  const evaluate=create({prepareResult:async q=>{preparations.push(q);if(prepare)await prepare(q);return {summary:'synthetic private result'};},releaseClock:()=>1500000,appId,providerId:'supabase:veteran-care',clock:()=>1500000,permissionClock:()=>1500000,idFactory:()=>grantId,
    configuration:{mode:'veteran_care',issuer,authProjectUrl:url,databaseProjectUrl:url,storageProjectUrl:url},
    auth:{getClaims:async()=>({data:{claims:{iss:issuer,aud:'authenticated',role:'authenticated',sub:authSubject,session_id:sessionId,exp:3000}}})},
    verifyAppCaller:async()=>({appId}),verifyIdentity:async()=>({shineId,authSubject,providerId:'supabase:veteran-care'}),
    getSessionState:async()=>({status:'active',sessionId,authSubject,issuer,expiresAt:null}),
    getResourceDescriptor:async()=>({resourceId:recordId,resourceVersion:3,ownerShineId:shineId,category:resourceCategory}),
    getPreparationContext:async()=>({status:'available',preparationId,ownerShineId:shineId,purpose}),
    getPermissionContext:async()=>snapshot,
    getCurrentPermissionRevision:async q=>{calls.push(q);return lookup?lookup(q):current;},...options});
  return {evaluate,calls,preparations};
}
test('stable authority returns prepared result only after two independent full evaluations',async()=>{
  const f=fixture();const r=await f.evaluate(input());assert.equal(r.status,'release-ready');assert.equal(r.resultReturned,true);assert.deepEqual(r.result,{summary:'synthetic private result'});
  assert.equal(f.calls.length,2);assert.equal(f.preparations.length,1);assert.equal(f.preparations[0].request.resourceId,recordId);
});
test('initial refusal never prepares private result',async()=>{
  const snapshot=context();snapshot.grants=[];const f=fixture({snapshot});const r=await f.evaluate(input());assert.equal(r.resultReturned,false);assert.equal(f.preparations.length,0);
});
test('revocation during private preparation withholds all result data',async()=>{
  const snapshot=context();const f=fixture({snapshot,prepare:async()=>{snapshot.grants[0].status='revoked';snapshot.permissionSnapshot.revision=2;},lookup:async()=>snapshot.permissionSnapshot});
  const r=await f.evaluate(input());assert.equal(r.resultReturned,false);assert.equal(r.preparationPerformed,true);assert.equal(r.result,undefined);
});
test('cached snapshot stale after preparation cannot release result',async()=>{
  let current=1;const f=fixture({prepare:async()=>{current=2;},lookup:async()=>stamp(current)});const r=await f.evaluate(input());assert.equal(r.reasonCode,'vc-permission-snapshot-stale');assert.equal(r.result,undefined);
});
test('session deactivation during preparation is checked again',async()=>{
  let status='active';const f=fixture({prepare:async()=>{status='inactive';},options:{getSessionState:async()=>({status,sessionId,authSubject,issuer,expiresAt:null})}});
  const r=await f.evaluate(input());assert.equal(r.reasonCode,'vc-session-not-current');assert.equal(r.result,undefined);
});
test('changed resource version and preparation ownership prevent return',async()=>{
  for(const mode of ['resource','preparation']){
    let changed=false;const f=fixture({prepare:async()=>{changed=true;},options:{
      getResourceDescriptor:async()=>({resourceId:recordId,resourceVersion:changed&&mode==='resource'?4:3,ownerShineId:shineId,category:resourceCategory}),
      getPreparationContext:async()=>({status:'available',preparationId,ownerShineId:changed&&mode==='preparation'?grantId:shineId,purpose})}});
    assert.equal((await f.evaluate(input())).resultReturned,false);
  }
});
test('replacement otherwise valid grant cannot authorise already prepared result',async()=>{
  const snapshot=context();const f=fixture({snapshot,prepare:async()=>{snapshot.grants[0].grantId=preparationId;}});assert.equal((await f.evaluate(input())).reasonCode,'vc-in-flight-authority-changed');
});
test('current authority outage after preparation has no result fallback',async()=>{
  let changed=false;const f=fixture({prepare:async()=>{changed=true;},lookup:async()=>{if(changed)throw Error('offline');return stamp();}});
  const r=await f.evaluate(input());assert.equal(r.status,'unavailable');assert.equal(r.result,undefined);
});
test('expiry at final synchronous return boundary withholds result',async()=>{
  let calls=0;const f=fixture({options:{releaseClock:()=>calls++===0?1500000:2000000}});const r=await f.evaluate(input());assert.equal(r.reasonCode,'vc-grant-expired');assert.equal(r.resultReturned,false);
});
test('invalid release clock and failed preparation withhold result',async()=>{
  for(const releaseClock of [()=>NaN,()=>-1])assert.equal((await fixture({options:{releaseClock}}).evaluate(input())).resultReturned,false);
  let calls=0;assert.equal((await fixture({options:{releaseClock:()=>calls++===0?1500000:1499999}}).evaluate(input())).resultReturned,false);
  const r=await fixture({prepare:async()=>{throw Error('private error');}}).evaluate(input());assert.equal(r.status,'unavailable');assert.equal(r.result,undefined);assert.equal(r.preparationPerformed,true);
});
test('caller mutation cannot switch target token or purpose after admission',async()=>{
  const q=input();const f=fixture({prepare:async()=>{q.request.input.recordId=grantId;q.authContext.jwt='bad';q.purposeContext.preparationId=grantId;}});
  assert.equal((await f.evaluate(q)).resultReturned,true);assert.equal(f.calls.length,2);
});
test('malformed input stops before preparation and factories require authority',async()=>{
  const q=input();Object.defineProperty(q.request.input,'recordId',{get(){throw Error('must not execute');}});const f=fixture();assert.equal((await f.evaluate(q)).status,'denied');assert.equal(f.preparations.length,0);
  assert.throws(()=>create({}),TypeError);
});
