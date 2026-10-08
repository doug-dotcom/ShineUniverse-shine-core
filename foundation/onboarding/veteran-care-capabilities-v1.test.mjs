import test from 'node:test';
import assert from 'node:assert/strict';
import {createVeteranCareCapabilityDeclaration,validateVeteranCareCapabilityInput} from './veteran-care-capabilities-v1.mjs';
const appId='shine.veteran-care'; // Synthetic registry ID, not live registration.
const recordId='11111111-1111-4111-8111-111111111111';
const build=getAppManifest=>createVeteranCareCapabilityDeclaration({appId,getAppManifest});
test('registered VC has two bounded declarations with no invocation or registration',async()=>{
  const result=await build(async query=>{assert.deepEqual(query,{appId});return {appId};})();
  assert.equal(result.status,'declaration-ready');
  assert.equal(result.registrationApplied,false);
  assert.equal(result.executionRequiresAuthorization,true);
  assert.equal(result.capabilities.length,2);
  for(const c of result.capabilities){
    assert.equal(c.appId,appId);assert.equal(c.invocationState,'declared');assert.equal(c.invocable,false);
    assert.equal(c.inputSchema.additionalProperties,false);
    assert.equal(c.outputSchema.additionalProperties,false);
  }
  const read=result.capabilities.find(c=>c.mode==='read');
  assert.deepEqual(read.requiredPermissions,[{scope:'veteran-care.record.read',purpose:'veteran-care.appointment-preparation',resourceCategory:'veteran-care.record'}]);
});
test('missing or substituted registry app produces no capabilities',async()=>{
  for(const manifest of [null,{appId:'shine.travel'}])
    assert.deepEqual(await build(async()=>manifest)(),{status:'blocked',reasonCode:'vc-app-unregistered'});
});
test('registry outage withholds declarations and redacts dependency detail',async()=>{
  assert.deepEqual(await build(async()=>{throw new Error('secret details');})(),{status:'unavailable',reasonCode:'vc-registry-unavailable'});
});
test('returned metadata cannot mutate a later declaration',async()=>{
  const declare=build(async()=>({appId}));const first=await declare();
  first.capabilities[0].invocable=true;first.capabilities[1].requiredPermissions.length=0;
  const next=await declare();assert.equal(next.capabilities[0].invocable,false);assert.equal(next.capabilities[1].requiredPermissions.length,1);
});
test('exact record/version and bounded general question inputs are accepted as copies',()=>{
  for(const [suffix,input] of [['selected_record_read',{recordId,recordVersion:2}],['adj_guidance',{question:'What should I prepare?'}]]){
    const result=validateVeteranCareCapabilityInput({appId,capabilityId:'veteran-care.'+suffix,input});
    assert.deepEqual(result,input);assert.notEqual(result,input);
  }
});
test('private input rejects wildcard/missing versions, credentials, identity and write fields',()=>{
  for(const input of [{recordId:'*',recordVersion:1},{recordId},{recordId,recordVersion:0},{recordId,recordVersion:1.5},{recordId,recordVersion:Number.MAX_SAFE_INTEGER+1},{recordId,recordVersion:1,token:'secret'},{recordId,recordVersion:1,shineId:recordId},{recordId,recordVersion:1,operation:'write'}])
    assert.throws(()=>validateVeteranCareCapabilityInput({appId,capabilityId:'veteran-care.selected_record_read',input}));
});
test('advisory input excludes private record references and authority claims',()=>{
  for(const input of [{question:''},{question:'  '},{question:'x'.repeat(2001)},{question:'hello',recordId},{question:'hello',permission:'allow'}])
    assert.throws(()=>validateVeteranCareCapabilityInput({appId,capabilityId:'veteran-care.adj_guidance',input}));
});
test('foreign/unknown capabilities cannot reuse VC validation',()=>{
  for(const capabilityId of ['travel.selected_record_read','veteran-care.write','veteran-care.submit'])
    assert.throws(()=>validateVeteranCareCapabilityInput({appId,capabilityId,input:{recordId,recordVersion:1}}));
});
test('accessors, symbols, arrays and foreign prototypes are rejected without reading values',()=>{
  let reads=0;const getter={get question(){reads++;return 'hello';}};
  for(const input of [getter,{question:'hello',[Symbol('authority')]:'allow'},['hello'],Object.assign(Object.create({}),{question:'hello'})])
    assert.throws(()=>validateVeteranCareCapabilityInput({appId,capabilityId:'veteran-care.adj_guidance',input}));
  assert.equal(reads,0);
});
test('missing registry authority or app configuration is rejected',()=>{
  assert.throws(()=>createVeteranCareCapabilityDeclaration({appId}));
  assert.throws(()=>createVeteranCareCapabilityDeclaration({appId:'VC',getAppManifest:async()=>null}));
});
