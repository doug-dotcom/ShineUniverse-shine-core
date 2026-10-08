import test from 'node:test';
import assert from 'node:assert/strict';
import {createVeteranCarePermissionEvaluator as create} from './veteran-care-permission-v1.mjs';
import {VETERAN_CARE_ISSUER as issuer} from './veteran-care-identity-v1.mjs';
import {VETERAN_CARE_PROJECT_URL as url} from './veteran-care-project-boundary-v1.mjs';
const appId='shine.veteran-care',recordId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',grantId='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',requestId='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const shineId='11111111-1111-4111-8111-111111111111',authSubject='22222222-2222-4222-8222-222222222222',sessionId='33333333-3333-4333-8333-333333333333';
const scope='veteran-care.record.read',purpose='veteran-care.appointment-preparation',resourceCategory='veteran-care.record';
const grant=()=>({grantId,ownerShineId:shineId,appId,scope,purpose,status:'active',expiresAt:'1970-01-01T00:33:20.000Z',resourceSelector:{resourceId:recordId,resourceVersion:3}});
const context=()=>({complete:true,appManifest:{appId,foundation:{requestedScopes:[{scope,purpose,resourceCategory}]}},grants:[grant()],defenceDecision:'allow'});
const input=()=>({authContext:{appToken:'synthetic',jwt:'e30.'+Buffer.from(JSON.stringify({iss:issuer})).toString('base64url')+'.c2ln'},request:{capabilityId:'veteran-care.selected_record_read',input:{recordId,recordVersion:3}}});
function fixture({policy=context(),lookup,session=true,permissionClock=()=>1000000}={}){
  const calls=[];
  const evaluate=create({appId,providerId:'supabase:veteran-care',clock:()=>1000000,permissionClock,idFactory:()=>requestId,
    configuration:{mode:'veteran_care',issuer,authProjectUrl:url,databaseProjectUrl:url,storageProjectUrl:url},
    auth:{getClaims:async()=>({data:{claims:{iss:issuer,aud:'authenticated',role:'authenticated',sub:authSubject,session_id:sessionId,exp:3000}}})},
    verifyAppCaller:async()=>({appId}),verifyIdentity:async()=>({shineId,authSubject,providerId:'supabase:veteran-care'}),
    getSessionState:async()=>session?{status:'active',sessionId,authSubject,issuer,expiresAt:null}:null,
    getResourceDescriptor:async()=>({resourceId:recordId,resourceVersion:3,ownerShineId:shineId,category:resourceCategory}),
    getPermissionContext:async query=>{calls.push(query);return lookup?lookup(query):policy;}});
  return {evaluate,calls};
}
test('one exact current grant and explicit Defence allow produce a bound decision without execution',async()=>{
  const f=fixture(),r=await f.evaluate(input());assert.equal(r.status,'permission-allowed');assert.equal(r.decision,'allow');assert.equal(r.grantId,grantId);assert.equal(r.executionPerformed,false);assert.equal(r.authorizationApplied,true);assert.equal(f.calls[0].request.resourceVersion,3);assert.equal(Object.isFrozen(f.calls[0].request),true);
});
test('missing malformed and sparse permission data cannot allow',async()=>{
  for(const policy of [null,{}, {...context(),complete:undefined},{...context(),complete:false},{...context(),grants:null},{...context(),grants:[null]},{...context(),grants:new Array(1)},{...context(),grants:Array(101).fill(grant())}]){
    const r=await fixture({policy}).evaluate(input());assert.equal(r.decision,'deny');assert.equal(r.reasonCode,'vc-permission-context-invalid');
  }
});
test('empty grants and undeclared or foreign manifest deny',async()=>{
  for(const policy of [{...context(),grants:[]},{...context(),appManifest:{appId,foundation:{requestedScopes:[]}}},{...context(),appManifest:{...context().appManifest,appId:'shine.travel'}}])
    assert.equal((await fixture({policy}).evaluate(input())).reasonCode,'vc-permission-missing');
});
test('unevaluated missing denied and malformed Defence states never default to allow',async()=>{
  for(const defenceDecision of [undefined,null,'not-evaluated','deny','unknown',true,{}]) assert.equal((await fixture({policy:{...context(),defenceDecision}}).evaluate(input())).reasonCode,'vc-defence-not-allowed');
});
test('multiple effective grants deny regardless of order',async()=>{
  const second={...grant(),grantId:'dddddddd-dddd-4ddd-8ddd-dddddddddddd'};
  for(const grants of [[grant(),second],[second,grant()]])assert.equal((await fixture({policy:{...context(),grants}}).evaluate(input())).reasonCode,'vc-permission-ambiguous');
});
test('duplicate IDs with conflicting statuses deny rather than selecting a row',async()=>{
  const grants=[grant(),{...grant(),status:'revoked'}];assert.equal((await fixture({policy:{...context(),grants}}).evaluate(input())).reasonCode,'vc-permission-ambiguous');
});
test('inactive historical grants do not compete with one effective distinct grant',async()=>{
  const old={...grant(),grantId:'dddddddd-dddd-4ddd-8ddd-dddddddddddd',status:'revoked'};
  assert.equal((await fixture({policy:{...context(),grants:[old,grant()]}}).evaluate(input())).decision,'allow');
});
test('wrong owner app scope and purpose cannot authorise',async()=>{
  for(const [key,value] of [['ownerShineId','44444444-4444-4444-8444-444444444444'],['appId','shine.travel'],['scope','*'],['purpose','unrestricted']])
    assert.equal((await fixture({policy:{...context(),grants:[{...grant(),[key]:value}]}}).evaluate(input())).reasonCode,'vc-permission-missing');
});
test('category broad mixed missing and wrong-version selectors deny',async()=>{
  for(const resourceSelector of [{resourceCategory},{resourceId:recordId},{resourceId:recordId,resourceVersion:4},{resourceId:'*',resourceVersion:3},{resourceId:recordId,resourceVersion:3,resourceCategory}])
    assert.equal((await fixture({policy:{...context(),grants:[{...grant(),resourceSelector}]}}).evaluate(input())).reasonCode,'vc-permission-missing');
});
test('revoked expired future and malformed-time grants reuse generic denial',async()=>{
  for(const extra of [{status:'revoked'},{revokedAt:'1970-01-01T00:01:00Z'},{expiresAt:'1970-01-01T00:16:40Z'},{notBefore:'1970-01-01T00:33:20Z'},{expiresAt:'bad'}])
    assert.equal((await fixture({policy:{...context(),grants:[{...grant(),...extra}]}}).evaluate(input())).reasonCode,'vc-permission-missing');
});
test('caller-provided policy cannot replace server permission context',async()=>{
  const f=fixture({policy:{...context(),grants:[]}}),r=input();r.permissionContext=context();r.grants=[grant()];assert.equal((await f.evaluate(r)).decision,'deny');assert.equal(f.calls.length,1);
});
test('session denial stops permission lookup',async()=>{
  const f=fixture({session:false});assert.equal((await f.evaluate(input())).decision,'deny');assert.deepEqual(f.calls,[]);
});
test('permission lookup outage and invalid clock fail closed without detail',async()=>{
  for(const options of [{lookup:async()=>{throw new Error('synthetic-secret');}},{permissionClock:()=>NaN}])
    assert.deepEqual(await fixture(options).evaluate(input()),{status:'unavailable',decision:'deny',reasonCode:'vc-permission-authority-unavailable',executionPerformed:false});
});
test('grant time is evaluated after permission lookup, not at request start',async()=>{
  let now=1000000;const f=fixture({permissionClock:()=>now,lookup:async()=>{now=2000000;return context();}});assert.equal((await f.evaluate(input())).decision,'deny');
});
test('permission authority rechecks each call and concurrent results remain isolated',async()=>{
  let n=0;const f=fixture({lookup:async()=>n++===0?context():{...context(),grants:[]}});
  const [good,bad]=await Promise.all([f.evaluate(input()),f.evaluate(input())]);assert.equal(good.decision,'allow');assert.equal(bad.decision,'deny');assert.equal(f.calls.length,2);
});
test('permission authority is mandatory',()=>{assert.throws(()=>create({}),TypeError);});
