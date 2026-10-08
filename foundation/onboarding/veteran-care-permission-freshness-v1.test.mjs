import test from 'node:test';
import assert from 'node:assert/strict';
import {createVeteranCareFreshPermissionEvaluator as create} from './veteran-care-permission-freshness-v1.mjs';
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
function fixture({snapshot=context(),current=stamp(),lookup,options={}}={}){
  const calls=[];
  const evaluate=create({appId,providerId:'supabase:veteran-care',clock:()=>1500000,permissionClock:()=>1500000,idFactory:()=>grantId,
    configuration:{mode:'veteran_care',issuer,authProjectUrl:url,databaseProjectUrl:url,storageProjectUrl:url},
    auth:{getClaims:async()=>({data:{claims:{iss:issuer,aud:'authenticated',role:'authenticated',sub:authSubject,session_id:sessionId,exp:3000}}})},
    verifyAppCaller:async()=>({appId}),verifyIdentity:async()=>({shineId,authSubject,providerId:'supabase:veteran-care'}),
    getSessionState:async()=>({status:'active',sessionId,authSubject,issuer,expiresAt:null}),
    getResourceDescriptor:async()=>({resourceId:recordId,resourceVersion:3,ownerShineId:shineId,category:resourceCategory}),
    getPreparationContext:async()=>({status:'available',preparationId,ownerShineId:shineId,purpose}),
    getPermissionContext:async()=>snapshot,
    getCurrentPermissionRevision:async q=>{calls.push(q);return lookup?lookup(q):current;},...options});
  return {evaluate,calls};
}
test('matching independent current revision allows exact finite purpose-bound grant',async()=>{
  const f=fixture();const r=await f.evaluate(input());assert.equal(r.decision,'allow');assert.equal(r.permissionValidUntil,end);assert.equal(r.executionPerformed,false);
  assert.deepEqual(f.calls,[{appId,ownerShineId:shineId}]);
});
test('cached active grant cannot survive authoritative revision advancement',async()=>{
  let revision=1;const f=fixture({lookup:async()=>stamp(revision)});
  assert.equal((await f.evaluate(input())).decision,'allow');revision=2;
  const r=await f.evaluate(input());assert.equal(r.reasonCode,'vc-permission-snapshot-stale');assert.equal(r.decision,'deny');assert.equal(r.grantId,undefined);assert.equal(f.calls.length,2);
});
test('older current revision also withholds permission rather than trusting regression',async()=>{
  const f=fixture({snapshot:{...context(),permissionSnapshot:stamp(2)},current:stamp(1)});assert.equal((await f.evaluate(input())).decision,'deny');
});
test('missing malformed cross owner and cross app snapshot revisions fail closed',async()=>{
  for(const permissionSnapshot of [undefined,null,{},stamp(-1),stamp(1.5),{...stamp(),appId:'shine.other'},{...stamp(),ownerShineId:grantId},{...stamp(),extra:true}]){
    const f=fixture({snapshot:{...context(),permissionSnapshot}});const r=await f.evaluate(input());assert.equal(r.decision,'deny');assert.equal(f.calls.length,0);
  }
});
test('malformed cross owner and cross app current revision fail closed',async()=>{
  for(const current of [undefined,null,{},stamp(NaN),stamp(Infinity),{...stamp(),appId:'shine.other'},{...stamp(),ownerShineId:grantId}])assert.equal((await fixture({lookup:async()=>current}).evaluate(input())).decision,'deny');
});
test('revision authority outage never falls back to cached allow',async()=>{
  const r=await fixture({lookup:async()=>{throw Error('offline');}}).evaluate(input());assert.equal(r.status,'unavailable');assert.equal(r.reasonCode,'vc-permission-freshness-unavailable');
});
test('caller freshness fields cannot replace authoritative mismatch',async()=>{
  const q=input();q.permissionSnapshot=stamp(2);q.currentRevision=2;q.cachedAllow=true;
  assert.equal((await fixture({current:stamp(2)}).evaluate(q)).decision,'deny');
});
test('snapshot is captured before awaiting revision and remains unmodified',async()=>{
  const snapshot=context();snapshot.grants[0].status='revoked';
  const f=fixture({snapshot,lookup:async()=>{snapshot.grants[0].status='active';return stamp();}});
  assert.equal((await f.evaluate(input())).decision,'deny');assert.equal(snapshot.grants[0].status,'active');
});
test('revision stamp mutation during lookup cannot upgrade stale snapshot',async()=>{
  const snapshot=context();const f=fixture({snapshot,lookup:async()=>{snapshot.permissionSnapshot.revision=2;return stamp(2);}});
  assert.equal((await f.evaluate(input())).reasonCode,'vc-permission-snapshot-stale');
});
test('freshness does not replace expiry purpose or revocation semantics',async()=>{
  for(const mutate of [s=>{s.grants[0].status='revoked';},s=>{s.grants[0].purposeBinding.preparationId=grantId;},s=>{s.grants[0].expiresAt=null;}]){
    const snapshot=context();mutate(snapshot);assert.equal((await fixture({snapshot}).evaluate(input())).decision,'deny');
  }
});
test('no mutation of original snapshot and zero initial revision is valid',async()=>{
  const snapshot=context();snapshot.permissionSnapshot=stamp(0);const before=structuredClone(snapshot);
  assert.equal((await fixture({snapshot,current:stamp(0)}).evaluate(input())).decision,'allow');assert.deepEqual(snapshot,before);
});
test('snapshot nested accessors cycles arrays and oversized data withhold permission',async()=>{
  let invoked=false;const accessor=context();Object.defineProperty(accessor.grants[0],'status',{get(){invoked=true;return 'active';}});
  const cycle=context();cycle.extra=cycle;
  const sparse=context();sparse.grants=new Array(1);
  const oversized=context();oversized.extra=new Array(101).fill(1);
  for(const snapshot of [accessor,cycle,sparse,oversized])assert.equal((await fixture({snapshot}).evaluate(input())).decision,'deny');assert.equal(invoked,false);
});
test('required current authority and fixed factory cannot be overridden',async()=>{
  assert.throws(()=>create({}),TypeError);
  const f=fixture({current:stamp(2),options:{verifyPermissionFreshness:async()=>({status:'current',context:context()})}});
  assert.equal((await f.evaluate(input())).decision,'deny');
});
