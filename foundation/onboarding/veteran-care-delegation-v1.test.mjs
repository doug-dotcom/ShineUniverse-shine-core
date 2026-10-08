import test from 'node:test';
import assert from 'node:assert/strict';
import {createVeteranCareDelegatedScopeBuilder as create} from './veteran-care-delegation-v1.mjs';
import {VETERAN_CARE_ISSUER as issuer} from './veteran-care-identity-v1.mjs';
import {VETERAN_CARE_PROJECT_URL as url} from './veteran-care-project-boundary-v1.mjs';
const appId='shine.veteran-care',sessionId='33333333-3333-4333-8333-333333333333';
const identity={shineId:'11111111-1111-4111-8111-111111111111',authSubject:'22222222-2222-4222-8222-222222222222',providerId:'supabase:veteran-care'};
const configuration={mode:'veteran_care',issuer,authProjectUrl:url,databaseProjectUrl:url,storageProjectUrl:url};
const claims=()=>({iss:issuer,aud:'authenticated',role:'authenticated',sub:identity.authSubject,session_id:sessionId,exp:2000});
const state=()=>({status:'active',sessionId,authSubject:identity.authSubject,issuer,expiresAt:null});
const owner='44444444-4444-4444-8444-444444444444',record='55555555-5555-4555-8555-555555555555',prep='66666666-6666-4666-8666-666666666666';
const input=()=>({authContext:{appToken:'synthetic',jwt:'e30.'+Buffer.from(JSON.stringify({iss:issuer})).toString('base64url')+'.c2ln'},selection:{ownerShineId:owner,recordId:record,recordVersion:2,preparationId:prep}});
function fixture({change=()=>{},lookup,session=state(),time=()=>1000000}={}){
 const calls=[];
 const build=create({configuration,appId,providerId:identity.providerId,clock:()=>1000000,delegationClock:time,
 auth:{getClaims:async()=>({data:{claims:claims()},error:null})},verifyAppCaller:async()=>({appId}),verifyIdentity:async()=>identity,getSessionState:async()=>session,
 getDelegationContext:async q=>{calls.push(q);if(lookup)return lookup(q);const c={complete:true,delegation:{...q,delegationId:'77777777-7777-4777-8777-777777777777',status:'active',relationship:'carer',revision:1,expiresAtMs:1500000},resource:{resourceId:record,resourceVersion:2,ownerShineId:owner,category:'veteran-care.record'}};change(c);return c;}});
 return {build,calls};
}
test('carer and provider bind verified actor separately from resource owner without granting execution',async()=>{
 for(const relationship of ['carer','provider']){const f=fixture({change:c=>c.delegation.relationship=relationship}),r=await f.build(input());assert.equal(r.status,'delegated-scope-ready');assert.equal(r.executionPermitted,false);assert.equal(r.authorizationApplied,false);assert.equal(r.request.actorShineId,identity.shineId);assert.equal(r.request.ownerShineId,owner);assert.equal(r.request.shineId,undefined);assert.ok(Object.isFrozen(r.request));assert.equal(JSON.stringify(f.calls).includes('synthetic'),false);}
});
test('role labels cannot override missing revoked expired or mismatched exact authority',async()=>{
 for(const [key,value] of [['status','revoked'],['relationship','veteran'],['actorShineId',owner],['ownerShineId',identity.shineId],['appId','shine.travel'],['scope','*'],['operation','write'],['recordId',prep],['recordVersion',3],['preparationId',record],['purpose','general'],['revision',0],['expiresAtMs',1000000]]){
 const r=await fixture({change:c=>c.delegation[key]=value}).build(input());assert.equal(r.status,'denied',key);assert.equal(r.request,undefined);}
 for(const c of [null,{}, {complete:true,delegation:{}}])assert.equal((await fixture({lookup:async()=>c}).build(input())).status,'denied');
});
test('authoritative resource must match exact owner record version category',async()=>{
 for(const [key,value] of [['ownerShineId',identity.shineId],['resourceId',prep],['resourceVersion',3],['category','travel.record']])assert.equal((await fixture({change:c=>c.resource[key]=value}).build(input())).status,'denied');
});
test('self access and revoked actor session cannot reach delegation authority',async()=>{
 let f=fixture(),i=input();i.selection.ownerShineId=identity.shineId;assert.equal((await f.build(i)).reasonCode,'vc-delegation-self-access');assert.equal(f.calls.length,0);
 f=fixture({session:null});assert.equal((await f.build(input())).status,'denied');assert.equal(f.calls.length,0);
});
test('invalid selection, extra authority fields and accessors are refused before lookup',async()=>{
 for(const mutate of [i=>i.selection.recordVersion=0,i=>i.selection.relationship='provider',i=>i.ownerShineId=owner,i=>Object.defineProperty(i.selection,'recordId',{get(){throw Error('must not run');},enumerable:true})]){const f=fixture(),i=input();mutate(i);assert.equal((await f.build(i)).status,'denied');assert.equal(f.calls.length,0);}
});
test('authority outage and invalid/regressing clocks withhold scope and internal errors',async()=>{
 const f=fixture({lookup:async()=>{throw Error('secret');}});const r=await f.build(input());assert.equal(r.status,'unavailable');assert.equal(JSON.stringify(r).includes('secret'),false);
 for(const time of [()=>NaN,()=>-1,(()=>{let n=0;return()=>n++?999999:1000000;})()])assert.equal((await fixture({time}).build(input())).status,'unavailable');
});
test('expiry during lookup refuses and each call rechecks delegation',async()=>{
 let n=0;const f=fixture({time:()=>n++?1500000:1000000});assert.equal((await f.build(input())).status,'denied');
 let active=true;const g=fixture({change:c=>c.delegation.status=active?'active':'revoked'});assert.equal((await g.build(input())).status,'delegated-scope-ready');active=false;assert.equal((await g.build(input())).status,'denied');assert.equal(g.calls.length,2);
});
test('caller mutation during identity awaits does not alter selected scope',async()=>{
 const f=fixture(),i=input(),pending=f.build(i);i.selection.ownerShineId=identity.shineId;i.selection.recordId=prep;i.authContext.jwt='forged';const r=await pending;assert.equal(r.status,'delegated-scope-ready');assert.equal(r.request.ownerShineId,owner);assert.equal(r.request.resourceId,record);
});
