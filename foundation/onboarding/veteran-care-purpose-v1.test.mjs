import test from 'node:test';
import assert from 'node:assert/strict';
import {createVeteranCarePurposePermissionEvaluator as create} from './veteran-care-purpose-v1.mjs';
import {VETERAN_CARE_ISSUER as issuer} from './veteran-care-identity-v1.mjs';
import {VETERAN_CARE_PROJECT_URL as url} from './veteran-care-project-boundary-v1.mjs';
const appId='shine.veteran-care',recordId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',preparationId='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',otherPreparationId='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const shineId='11111111-1111-4111-8111-111111111111',authSubject='22222222-2222-4222-8222-222222222222',sessionId='33333333-3333-4333-8333-333333333333';
const purpose='veteran-care.appointment-preparation',scope='veteran-care.record.read',resourceCategory='veteran-care.record';
const binding=()=>({kind:'appointment-preparation',preparationId});
const preparation=()=>({status:'available',preparationId,ownerShineId:shineId,purpose});
const grant=()=>({grantId:'dddddddd-dddd-4ddd-8ddd-dddddddddddd',appId,ownerShineId:shineId,scope,purpose,status:'active',expiresAt:'1970-01-01T00:33:20Z',resourceSelector:{resourceId:recordId,resourceVersion:3},purposeBinding:binding()});
const input=()=>({authContext:{appToken:'synthetic',jwt:'e30.'+Buffer.from(JSON.stringify({iss:issuer})).toString('base64url')+'.c2ln'},request:{capabilityId:'veteran-care.selected_record_read',input:{recordId,recordVersion:3}},purposeContext:{preparationId}});
function fixture({context=preparation(),lookup,grants=[grant()],session=true}={}){
  const calls=[];
  const evaluate=create({appId,providerId:'supabase:veteran-care',clock:()=>1000000,permissionClock:()=>1000000,idFactory:()=>otherPreparationId,
    configuration:{mode:'veteran_care',issuer,authProjectUrl:url,databaseProjectUrl:url,storageProjectUrl:url},
    auth:{getClaims:async()=>({data:{claims:{iss:issuer,aud:'authenticated',role:'authenticated',sub:authSubject,session_id:sessionId,exp:3000}}})},
    verifyAppCaller:async()=>({appId}),verifyIdentity:async()=>({shineId,authSubject,providerId:'supabase:veteran-care'}),
    getSessionState:async()=>session?{status:'active',sessionId,authSubject,issuer,expiresAt:null}:null,
    getResourceDescriptor:async()=>({resourceId:recordId,resourceVersion:3,ownerShineId:shineId,category:resourceCategory}),
    getPreparationContext:async query=>{calls.push(['preparation',query]);return lookup?lookup(query):context;},
    getPermissionContext:async query=>{calls.push(['permission',query]);return {complete:true,appManifest:{appId,foundation:{requestedScopes:[{scope,purpose,resourceCategory}]}},grants,defenceDecision:'allow'};}});
  return {evaluate,calls};
}
test('exact current preparation binding reaches permission authority and immutable result',async()=>{
  const f=fixture(),r=await f.evaluate(input());assert.equal(r.decision,'allow');assert.deepEqual(r.request.purposeBinding,binding());assert.equal(r.request.contract,'shine-foundation/veteran-care-purpose-request-v1');assert.equal(Object.isFrozen(r.request.purposeBinding),true);assert.deepEqual(f.calls[0],['preparation',{preparationId,ownerShineId:shineId,appId,purpose}]);assert.deepEqual(f.calls[1][1].request.purposeBinding,binding());assert.equal(r.executionPerformed,false);
});
test('same purpose label cannot reuse another preparation grant',async()=>{
  const f=fixture({grants:[{...grant(),purposeBinding:{...binding(),preparationId:otherPreparationId}}]});assert.equal((await f.evaluate(input())).reasonCode,'vc-permission-missing');
});
test('legacy broad wrong-kind and extra-field purpose bindings deny',async()=>{
  for(const purposeBinding of [undefined,null,{kind:'appointment-preparation'},{kind:'general-retrieval',preparationId},{...binding(),allowAll:true},{...binding(),preparationId:'*'}])assert.equal((await fixture({grants:[{...grant(),purposeBinding}]}).evaluate(input())).decision,'deny');
});
test('missing deleted unavailable foreign-owner and mismatched context deny before permission',async()=>{
  for(const context of [null,{...preparation(),status:'deleted'},{...preparation(),preparationId:otherPreparationId},{...preparation(),ownerShineId:'44444444-4444-4444-8444-444444444444'},{...preparation(),purpose:'unrestricted'}]){
    const f=fixture({context});assert.equal((await f.evaluate(input())).reasonCode,'vc-purpose-binding-unverified');assert.equal(f.calls.length,1);
  }
});
test('malformed caller purpose context fails before any authority',async()=>{
  for(const purposeContext of [undefined,null,{preparationId:'*'},{preparationId,purpose:'unrestricted'},Object.create({preparationId}),[]]){
    const f=fixture(),r=input();r.purposeContext=purposeContext;assert.equal((await f.evaluate(r)).reasonCode,'vc-purpose-context-invalid');assert.deepEqual(f.calls,[]);
  }
});
test('accessors and symbol fields cannot supply purpose context',async()=>{
  const accessor={};Object.defineProperty(accessor,'preparationId',{get(){throw Error('must not execute');}});
  for(const purposeContext of [accessor,{preparationId,[Symbol('extra')]:true}]){
    const f=fixture(),r=input();r.purposeContext=purposeContext;assert.equal((await f.evaluate(r)).decision,'deny');assert.deepEqual(f.calls,[]);
  }
});
test('caller free text and grant declarations never replace server binding',async()=>{
  const f=fixture({context:null}),r=input();r.purpose='appointment preparation';r.preparation=preparation();r.grants=[grant()];assert.equal((await f.evaluate(r)).decision,'deny');
});
test('canonical UUID matching preserves purpose record identity',async()=>{
  const f=fixture({context:{...preparation(),preparationId:preparationId.toUpperCase()},grants:[{...grant(),purposeBinding:{...binding(),preparationId:preparationId.toUpperCase()}}]}),r=input();r.purposeContext.preparationId=preparationId.toUpperCase();assert.equal((await f.evaluate(r)).request.purposeBinding.preparationId,preparationId);
});
test('purpose selection is snapshotted across asynchronous context lookup',async()=>{
  let release,arrived;const reached=new Promise(r=>{arrived=r;});const f=fixture({lookup:async()=>{arrived();return new Promise(r=>{release=r;});}}),r=input();
  const pending=f.evaluate(r);await reached;r.purposeContext.preparationId=otherPreparationId;release(preparation());assert.deepEqual((await pending).request.purposeBinding,binding());
});
test('concurrent preparations cannot borrow matching permission',async()=>{
  const f=fixture({lookup:async q=>({...preparation(),preparationId:q.preparationId})}),other=input();other.purposeContext.preparationId=otherPreparationId;
  const [good,bad]=await Promise.all([f.evaluate(input()),f.evaluate(other)]);assert.equal(good.decision,'allow');assert.equal(bad.decision,'deny');
});
test('context outage and revoked session withhold purpose access',async()=>{
  const f=fixture({lookup:async()=>{throw Error('synthetic-private-detail');}});assert.deepEqual(await f.evaluate(input()),{status:'unavailable',decision:'deny',reasonCode:'vc-purpose-binding-unverified',executionPerformed:false});
  const g=fixture({session:false});assert.equal((await g.evaluate(input())).decision,'deny');assert.deepEqual(g.calls,[]);
});
test('preparation content and booking claims never appear in decision',async()=>{
  const f=fixture({context:{...preparation(),notes:'synthetic-private-notes',bookingConfirmed:true}}),r=await f.evaluate(input());assert.equal(JSON.stringify(r).includes('synthetic-private'),false);assert.equal(JSON.stringify(r).includes('bookingConfirmed'),false);
});
test('preparation authority is mandatory',()=>{assert.throws(()=>create({}),TypeError);});
