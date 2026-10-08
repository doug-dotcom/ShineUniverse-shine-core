import test from 'node:test';
import assert from 'node:assert/strict';
import {createVeteranCareBoundedPermissionEvaluator as create} from './veteran-care-permission-outage-v1.mjs';
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
  const evaluate=create({authorityTimeoutMs:15,appId,providerId:'supabase:veteran-care',clock:()=>1500000,permissionClock:()=>1500000,idFactory:()=>grantId,
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
test('healthy authorities retain full exact permission and expiry checks',async()=>{const f=fixture(),r=await f.evaluate(input());assert.equal(r.decision,'allow');assert.equal(r.executionPerformed,false);assert.equal(r.permissionValidUntil,end);assert.equal(f.calls.length,1);});
test('hanging permission context times out blocks access and supplies cooperative abort',async()=>{let signal;const f=fixture({options:{getPermissionContext:async(q,control)=>{signal=control.signal;return new Promise(()=>{});}}});const r=await f.evaluate(input());assert.equal(r.status,'unavailable');assert.equal(r.decision,'deny');assert.equal(r.request,undefined);assert.equal(r.grantId,undefined);assert.equal(signal.aborted,true);assert.equal(f.calls.length,0);});
test('hanging revision never falls back to the otherwise valid cached grant',async()=>{let signal;const f=fixture({options:{getCurrentPermissionRevision:async(q,control)=>{signal=control.signal;return new Promise(()=>{});}}});const r=await f.evaluate(input());assert.equal(r.status,'unavailable');assert.equal(r.decision,'deny');assert.equal(r.request,undefined);assert.equal(signal.aborted,true);});
test('late allowed context cannot revive timeout or leak into a fresh recovered request',async()=>{let release,first=true;const f=fixture({options:{getPermissionContext:async()=>{if(first){first=false;return new Promise(r=>release=r);}return context();}}});const timed=await f.evaluate(input());assert.equal(timed.decision,'deny');release(context());await Promise.resolve();assert.equal(timed.decision,'deny');assert.equal((await f.evaluate(input())).decision,'allow');});
test('late rejecting adapters are consumed and new requests freshly detect revocation',async()=>{let reject,first=true;const c=context();const f=fixture({options:{getCurrentPermissionRevision:async()=>{if(first){first=false;return new Promise((r,j)=>reject=j);}return stamp(2);}}});assert.equal((await f.evaluate(input())).status,'unavailable');reject(Error('secret'));await Promise.resolve();const r=await f.evaluate(input());assert.equal(r.reasonCode,'vc-permission-snapshot-stale');assert.equal(r.decision,'deny');});
test('authority failures hide raw details and do not retry',async()=>{for(const key of ['getPermissionContext','getCurrentPermissionRevision']){let count=0;const f=fixture({options:{[key]:()=>{count++;throw Error('clinical-token-secret');}}});const r=await f.evaluate(input());assert.equal(r.status,'unavailable');assert.equal(count,1);assert.equal(JSON.stringify(r).includes('clinical-token-secret'),false);}});
test('concurrent hanging and healthy requests have independent deadlines and results',async()=>{let first=true;const f=fixture({options:{getPermissionContext:async()=>{if(first){first=false;return new Promise(()=>{});}return context();}}});const a=f.evaluate(input()),b=f.evaluate(input());assert.equal((await b).decision,'allow');assert.equal((await a).decision,'deny');});
test('invalid timeout configuration is refused at construction',()=>{for(const authorityTimeoutMs of [0,-1,1.5,30001,NaN,Infinity,'15'])assert.throws(()=>fixture({options:{authorityTimeoutMs}}),TypeError);});
