import test from 'node:test';
import assert from 'node:assert/strict';
import {evaluateVeteranCareGrantWindow as window,createVeteranCareExpiringPermissionEvaluator as create} from './veteran-care-grant-expiry-v1.mjs';
import {VETERAN_CARE_ISSUER as issuer} from './veteran-care-identity-v1.mjs';
import {VETERAN_CARE_PROJECT_URL as url} from './veteran-care-project-boundary-v1.mjs';
const start='1970-01-01T00:16:40.000Z',end='1970-01-01T00:33:20.000Z';
const timed=()=>({notBefore:start,expiresAt:end,consentWindow:{startsAt:start,expiresAt:end}});
const appId='shine.veteran-care',recordId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',preparationId='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',grantId='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const shineId='11111111-1111-4111-8111-111111111111',authSubject='22222222-2222-4222-8222-222222222222',sessionId='33333333-3333-4333-8333-333333333333';
const purpose='veteran-care.appointment-preparation',scope='veteran-care.record.read',resourceCategory='veteran-care.record';
const grant=()=>({grantId,appId,ownerShineId:shineId,scope,purpose,status:'active',resourceSelector:{resourceId:recordId,resourceVersion:3},purposeBinding:{kind:'appointment-preparation',preparationId},...timed()});
const input=()=>({authContext:{appToken:'synthetic',jwt:'e30.'+Buffer.from(JSON.stringify({iss:issuer})).toString('base64url')+'.c2ln'},request:{capabilityId:'veteran-care.selected_record_read',input:{recordId,recordVersion:3}},purposeContext:{preparationId}});
function fixture({grants=[grant()],permissionClock=()=>1500000,lookup,overrideWindow}={}){
  return create({appId,providerId:'supabase:veteran-care',clock:()=>1500000,permissionClock,idFactory:()=>grantId,evaluateGrantWindow:overrideWindow,
    configuration:{mode:'veteran_care',issuer,authProjectUrl:url,databaseProjectUrl:url,storageProjectUrl:url},
    auth:{getClaims:async()=>({data:{claims:{iss:issuer,aud:'authenticated',role:'authenticated',sub:authSubject,session_id:sessionId,exp:3000}}})},
    verifyAppCaller:async()=>({appId}),verifyIdentity:async()=>({shineId,authSubject,providerId:'supabase:veteran-care'}),
    getSessionState:async()=>({status:'active',sessionId,authSubject,issuer,expiresAt:null}),
    getResourceDescriptor:async()=>({resourceId:recordId,resourceVersion:3,ownerShineId:shineId,category:resourceCategory}),
    getPreparationContext:async()=>({status:'available',preparationId,ownerShineId:shineId,purpose}),
    getPermissionContext:async()=>{if(lookup)await lookup();return {complete:true,appManifest:{appId,foundation:{requestedScopes:[{scope,purpose,resourceCategory}]}},grants,defenceDecision:'allow'};}});
}
test('approved finite window includes start and excludes exact end',()=>{
  assert.equal(window({grant:timed(),nowMs:1000000}).status,'current');assert.equal(window({grant:timed(),nowMs:1999999}).status,'current');
  for(const nowMs of [999999,2000000,2000001,NaN])assert.equal(window({grant:timed(),nowMs}).status,'denied');
});
test('expiry and start cannot be omitted or unlimited',()=>{
  for(const value of [undefined,null,'',Infinity]){
    for(const key of ['notBefore','expiresAt'])assert.equal(window({grant:{...timed(),[key]:value},nowMs:1500000}).status,'denied');
    for(const key of ['startsAt','expiresAt'])assert.equal(window({grant:{...timed(),consentWindow:{...timed().consentWindow,[key]:value}},nowMs:1500000}).status,'denied');
  }
});
test('grant extension shortening and earlier start cannot override reviewed snapshot',()=>{
  for(const extra of [{expiresAt:'1970-01-01T00:50:00.000Z'},{expiresAt:'1970-01-01T00:25:00.000Z'},{notBefore:'1970-01-01T00:00:00.000Z'}])assert.equal(window({grant:{...timed(),...extra},nowMs:1500000}).status,'denied');
});
test('invalid reordered equal and noncanonical dates deny',()=>{
  for(const expiresAt of [start,'1970-01-01T00:00:00.000Z','1970-02-30T00:33:20.000Z','1970-01-01T00:33:20Z','1970-01-01T01:33:20.000+01:00','2000000']){
    const g={...timed(),expiresAt,consentWindow:{startsAt:start,expiresAt}};assert.equal(window({grant:g,nowMs:1500000}).status,'denied');
  }
});
test('snapshot must be plain exact data with no accessors symbols or inheritance',()=>{
  const accessor={expiresAt:end};Object.defineProperty(accessor,'startsAt',{get(){throw Error('must not execute');}});
  for(const consentWindow of [undefined,null,[],Object.create(timed().consentWindow),accessor,{...timed().consentWindow,[Symbol('extra')]:true},{...timed().consentWindow,approved:true}])assert.equal(window({grant:{...timed(),consentWindow},nowMs:1500000}).status,'denied');
});
test('complete guarded path returns approved permission deadline without execution',async()=>{
  const r=await fixture()(input());assert.equal(r.decision,'allow');assert.equal(r.permissionValidUntil,end);assert.equal(r.executionPerformed,false);
});
test('legacy missing window and null expiry cannot pass complete guarded path',async()=>{
  for(const extra of [{consentWindow:undefined},{expiresAt:null},{notBefore:undefined},{expiresAt:undefined}])assert.equal((await fixture({grants:[{...grant(),...extra}]})(input())).decision,'deny');
});
test('grant expiring while permission lookup runs is refused',async()=>{
  let now=1500000;const evaluate=fixture({permissionClock:()=>now,lookup:async()=>{now=2000000;}});assert.equal((await evaluate(input())).decision,'deny');
});
test('deadline is checked again just before allow return',async()=>{
  let n=0;const evaluate=fixture({permissionClock:()=>n++===0?1999999:2000000});assert.equal((await evaluate(input())).reasonCode,'vc-grant-expired');
});
test('invalid and regressing completion clocks withhold allow',async()=>{
  for(const final of [NaN,Infinity,1499999]){let n=0;const evaluate=fixture({permissionClock:()=>n++===0?1500000:final});assert.equal((await evaluate(input())).status,'unavailable');}
});
test('caller dates cannot extend authoritative approved deadline',async()=>{
  const r=input();r.expiresAt='2999-01-01T00:00:00.000Z';r.consentWindow={startsAt:start,expiresAt:r.expiresAt};const result=await fixture()(r);assert.equal(result.permissionValidUntil,end);
});
test('expired grants do not compete with one current approved grant',async()=>{
  const oldEnd='1970-01-01T00:20:00.000Z';const old={...grant(),grantId:'dddddddd-dddd-4ddd-8ddd-dddddddddddd',expiresAt:oldEnd,consentWindow:{startsAt:start,expiresAt:oldEnd}};
  assert.equal((await fixture({grants:[old,grant()]})(input())).grantId,grantId);
});
test('factory cannot replace required window policy with caller configuration',async()=>{
  assert.throws(()=>create({}),TypeError);const g=grant();g.expiresAt=null;assert.equal((await fixture({grants:[g],overrideWindow:()=>({status:'current',expiresAtMs:3000000})})(input())).decision,'deny');
});
