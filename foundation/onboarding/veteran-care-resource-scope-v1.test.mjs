import test from 'node:test';
import assert from 'node:assert/strict';
import {createVeteranCareResourceScopeBuilder as create} from './veteran-care-resource-scope-v1.mjs';
import {VETERAN_CARE_ISSUER as issuer} from './veteran-care-identity-v1.mjs';
import {VETERAN_CARE_PROJECT_URL as url} from './veteran-care-project-boundary-v1.mjs';
const appId='shine.veteran-care',recordId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',requestId='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const shineId='11111111-1111-4111-8111-111111111111',authSubject='22222222-2222-4222-8222-222222222222',sessionId='33333333-3333-4333-8333-333333333333';
const request=()=>({capabilityId:'veteran-care.selected_record_read',input:{recordId,recordVersion:3}});
const proof=()=>({appToken:'synthetic',jwt:'e30.'+Buffer.from(JSON.stringify({iss:issuer})).toString('base64url')+'.c2ln'});
const descriptor=()=>({resourceId:recordId,resourceVersion:3,ownerShineId:shineId,category:'veteran-care.record'});
function fixture({resource=descriptor(),lookup,idFactory=()=>requestId,session=true,caller=appId}={}){
  const calls=[];
  const build=create({appId,providerId:'supabase:veteran-care',idFactory,clock:()=>1000000,
    configuration:{mode:'veteran_care',issuer,authProjectUrl:url,databaseProjectUrl:url,storageProjectUrl:url},
    auth:{getClaims:async()=>({data:{claims:{iss:issuer,aud:'authenticated',role:'authenticated',sub:authSubject,session_id:sessionId,exp:2000}}})},
    verifyAppCaller:async()=>{calls.push('caller');return {appId:caller};},
    verifyIdentity:async()=>({shineId,authSubject,providerId:'supabase:veteran-care'}),
    getSessionState:async()=>session?{status:'active',sessionId,authSubject,issuer,expiresAt:null}:null,
    getResourceDescriptor:async query=>{calls.push(query);return lookup?lookup(query):resource;}});
  return {build,calls};
}
test('exact owned record becomes an immutable request, never an authorisation',async()=>{
  const f=fixture(),r=await f.build({authContext:proof(),request:request()});
  assert.deepEqual(f.calls,['caller',{appId,ownerShineId:shineId,recordId,recordVersion:3}]);
  assert.deepEqual(r,{status:'scope-ready',authorizationApplied:false,executionPermitted:false,request:{contract:'shine-foundation/veteran-care-resource-request-v1',schemaVersion:'1.0.0',requestId,appId,shineId,capabilityId:'veteran-care.selected_record_read',operation:'read',scope:'veteran-care.record.read',purpose:'veteran-care.appointment-preparation',resourceId:recordId,resourceVersion:3,resourceCategory:'veteran-care.record'}});
  assert.equal(Object.isFrozen(r.request),true);
});
test('caller cannot choose owner app scope purpose or operation',async()=>{
  for(const key of ['shineId','ownerShineId','appId','scope','purpose','operation','requestId']){
    const f=fixture();assert.equal((await f.build({authContext:proof(),request:{...request(),[key]:'forged'}})).reasonCode,'vc-resource-request-invalid');assert.deepEqual(f.calls,[]);
  }
});
test('write advisory and foreign capabilities cannot request private metadata',async()=>{
  for(const capabilityId of ['veteran-care.record_write','veteran-care.adj_guidance','travel.selected_record_read','*']){
    const f=fixture();assert.equal((await f.build({authContext:proof(),request:{...request(),capabilityId}})).reasonCode,'vc-resource-request-invalid');assert.deepEqual(f.calls,[]);
  }
});
test('wildcards versions and injected nested authority fail before auth',async()=>{
  for(const input of [{recordId:'*',recordVersion:3},{recordId},{recordId,recordVersion:0},{recordId,recordVersion:'3'},{recordId,recordVersion:3,ownerShineId:shineId}]){
    const f=fixture();assert.equal((await f.build({authContext:proof(),request:{...request(),input}})).reasonCode,'vc-resource-request-invalid');assert.deepEqual(f.calls,[]);
  }
});
test('request accessors symbols and inherited fields fail without getter execution',async()=>{
  const accessor=request();Object.defineProperty(accessor,'input',{get(){throw new Error('must not execute');}});
  for(const r of [accessor,{...request(),[Symbol('extra')]:1},Object.create(request()),null,[]]){
    const f=fixture();assert.equal((await f.build({authContext:proof(),request:r})).reasonCode,'vc-resource-request-invalid');assert.deepEqual(f.calls,[]);
  }
});
test('missing foreign veteran wrong ID version and category share one denial',async()=>{
  for(const resource of [null,{...descriptor(),ownerShineId:'44444444-4444-4444-8444-444444444444'},{...descriptor(),resourceId:requestId},{...descriptor(),resourceVersion:4},{...descriptor(),category:'travel.record'}])
    assert.deepEqual(await fixture({resource}).build({authContext:proof(),request:request()}),{status:'denied',reasonCode:'vc-resource-scope-mismatch'});
});
test('revoked session and foreign caller never reach resource metadata',async()=>{
  for(const options of [{session:false},{caller:'shine.travel'}]){const f=fixture(options);assert.equal((await f.build({authContext:proof(),request:request()})).status,'denied');assert.deepEqual(f.calls,['caller']);}
});
test('UUIDs are canonicalised without changing record selection',async()=>{
  const f=fixture({resource:{...descriptor(),resourceId:recordId.toUpperCase()}}),r=request();r.input.recordId=recordId.toUpperCase();
  assert.equal((await f.build({authContext:proof(),request:r})).request.resourceId,recordId);
});
test('metadata content and credentials are not propagated into scoped output',async()=>{
  const f=fixture({resource:{...descriptor(),content:'synthetic-private-content',token:'synthetic-secret'}});const r=await f.build({authContext:proof(),request:request()});assert.equal(JSON.stringify(r).includes('synthetic'),false);
});
test('request is snapshotted before async metadata lookup',async()=>{
  let release,arrived;const reached=new Promise(r=>{arrived=r;});
  const f=fixture({lookup:async()=>{arrived();return new Promise(r=>{release=r;});}}),r=request();
  const pending=f.build({authContext:proof(),request:r});await reached;r.input.recordId=requestId;r.input.recordVersion=99;
  release(descriptor());const output=await pending;assert.equal(output.request.resourceId,recordId);assert.equal(output.request.resourceVersion,3);
});
test('authority outage and invalid request ID return bounded unavailable',async()=>{
  for(const options of [{lookup:async()=>{throw new Error('synthetic-secret');}},{idFactory:()=>'*'}])
    assert.deepEqual(await fixture(options).build({authContext:proof(),request:request()}),{status:'unavailable',reasonCode:'vc-resource-authority-unavailable'});
});
test('concurrent selections cannot borrow another resource descriptor',async()=>{
  const f=fixture({lookup:async q=>q.recordId===recordId?descriptor():null});const wrong={...request(),input:{recordId:requestId,recordVersion:3}};
  const [good,bad]=await Promise.all([f.build({authContext:proof(),request:request()}),f.build({authContext:proof(),request:wrong})]);assert.equal(good.status,'scope-ready');assert.equal(bad.status,'denied');
});
test('metadata authority is mandatory',()=>{assert.throws(()=>create({}),TypeError);});
