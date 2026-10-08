import test from 'node:test';
import assert from 'node:assert/strict';
import {createVeteranCareReadDispatcher as create} from './veteran-care-read-dispatch-v1.mjs';
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
const envelope=()=>({operation:'read',readRequest:input()});
test('read route preserves complete permission and release checks',async()=>{const f=fixture(),r=await f.evaluate(envelope());assert.equal(r.status,'release-ready');assert.equal(f.calls.length,2);assert.equal(f.preparations.length,1);assert.equal(f.preparations[0].request.operation,'read');});
test('read grant cannot dispatch any edit upload delete or inferred operation',async()=>{for(const operation of ['write','edit','upload','delete','update','READ','read,write','*',undefined,null,{},['read']]){const f=fixture(),r=await f.evaluate({...envelope(),operation});assert.equal(r.reasonCode,'vc-read-route-operation-refused');assert.equal(r.result,undefined);assert.equal(f.calls.length,0);assert.equal(f.preparations.length,0);}});
test('mixed envelopes and accessor operations fail without calling authority or preparation',async()=>{for(const mutate of [e=>e.writeRequest={},e=>e.upload={},e=>e.method='POST',e=>Object.defineProperty(e,'operation',{get(){throw Error('must not run');}}),e=>Object.defineProperty(e,'readRequest',{get(){throw Error('must not run');}})]){const f=fixture(),e=envelope();mutate(e);assert.equal((await f.evaluate(e)).status,'denied');assert.equal(f.calls.length,0);assert.equal(f.preparations.length,0);}});
test('nested write payload and write capability cannot enter private preparation',async()=>{for(const mutate of [e=>e.readRequest.request.input.content='forged edit',e=>e.readRequest.request.capabilityId='veteran-care.selected_record_write',e=>e.readRequest.request.operation='write']){const f=fixture(),e=envelope();mutate(e);assert.equal((await f.evaluate(e)).status,'denied');assert.equal(f.preparations.length,0);}});
test('valid read route does not bypass missing grants or in-flight withdrawal',async()=>{const snapshot=context();snapshot.grants=[];let f=fixture({snapshot});assert.equal((await f.evaluate(envelope())).resultReturned,false);assert.equal(f.preparations.length,0);const c=context();f=fixture({snapshot:c,prepare:async()=>c.grants[0].status='revoked'});assert.equal((await f.evaluate(envelope())).resultReturned,false);assert.equal(f.preparations.length,1);});
test('operation and nested target cannot change while identity verification awaits',async()=>{const f=fixture(),e=envelope(),pending=f.evaluate(e);e.operation='upload';e.readRequest.request.input.recordId=preparationId;const r=await pending;assert.equal(r.status,'release-ready');assert.equal(f.preparations[0].request.operation,'read');assert.equal(f.preparations[0].request.resourceId,recordId);});
