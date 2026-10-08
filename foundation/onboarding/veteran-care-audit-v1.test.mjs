import test from 'node:test';
import assert from 'node:assert/strict';
import {createVeteranCareAuditedPermissionEvaluator as create} from './veteran-care-audit-v1.mjs';
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
  const calls=[],events=[];
  const evaluate=create({auditIdFactory:()=>sessionId,auditClock:()=>1500000,writeAuditEvent:async event=>{events.push(event);return {status:'recorded',eventId:event.eventId};},appId,providerId:'supabase:veteran-care',clock:()=>1500000,permissionClock:()=>1500000,idFactory:()=>grantId,
    configuration:{mode:'veteran_care',issuer,authProjectUrl:url,databaseProjectUrl:url,storageProjectUrl:url},
    auth:{getClaims:async()=>({data:{claims:{iss:issuer,aud:'authenticated',role:'authenticated',sub:authSubject,session_id:sessionId,exp:3000}}})},
    verifyAppCaller:async()=>({appId}),verifyIdentity:async()=>({shineId,authSubject,providerId:'supabase:veteran-care'}),
    getSessionState:async()=>({status:'active',sessionId,authSubject,issuer,expiresAt:null}),
    getResourceDescriptor:async()=>({resourceId:recordId,resourceVersion:3,ownerShineId:shineId,category:resourceCategory}),
    getPreparationContext:async()=>({status:'available',preparationId,ownerShineId:shineId,purpose}),
    getPermissionContext:async()=>snapshot,
    getCurrentPermissionRevision:async q=>{calls.push(q);return lookup?lookup(q):current;},...options});
  return {evaluate,calls,events};
}
test('allow is durably acknowledged without recording private identifiers or tokens',async()=>{const f=fixture(),r=await f.evaluate(input());assert.equal(r.decision,'allow');assert.equal(r.auditRecorded,true);assert.equal(r.auditEventId,sessionId);assert.equal(f.events.length,1);assert.ok(Object.isFrozen(f.events[0]));assert.deepEqual(Object.keys(f.events[0]).sort(),['appId','disclosureVerified','event','eventId','executionPerformed','observedOutcome','occurredAt','schemaVersion','stage'].sort());const text=JSON.stringify(f.events);for(const privateValue of [recordId,preparationId,grantId,shineId,authSubject,'synthetic','c2ln'])assert.equal(text.includes(privateValue),false);assert.equal(f.events[0].observedOutcome,'permission-allowed');assert.equal(f.events[0].disclosureVerified,false);});
test('denial and authority outage receive bounded observation categories',async()=>{const snapshot=context();snapshot.grants=[];let f=fixture({snapshot});assert.equal((await f.evaluate(input())).decision,'deny');assert.equal(f.events[0].observedOutcome,'permission-denied');f=fixture({lookup:async()=>{throw Error('clinical secret');}});assert.equal((await f.evaluate(input())).status,'unavailable');assert.equal(f.events[0].observedOutcome,'authority-unavailable');assert.equal(JSON.stringify(f.events).includes('clinical secret'),false);});
test('unknown content and credentials are never copied into the audit sink',async()=>{const f=fixture(),i=input();i.note='private diagnosis';i.authContext.extra='credential';await f.evaluate(i);assert.equal(JSON.stringify(f.events).includes('private diagnosis'),false);assert.equal(JSON.stringify(f.events).includes('credential'),false);});
test('failed or wrong-event audit acknowledgement withholds allowed request and grant',async()=>{for(const writeAuditEvent of [async()=>{throw Error('sink-secret');},async()=>undefined,async()=>({status:'recorded',eventId:grantId}),async()=>({status:'queued',eventId:sessionId}),async()=>({get status(){throw Error('must not leak');},eventId:sessionId})]){const r=await fixture({options:{writeAuditEvent}}).evaluate(input());assert.equal(r.auditRecorded,false);assert.equal(r.decision,'deny');assert.equal(r.request,undefined);assert.equal(r.grantId,undefined);assert.equal(JSON.stringify(r).includes('secret'),false);}});
test('server audit IDs and timestamp validation fail closed',async()=>{for(const options of [{auditIdFactory:()=>recordId+' private'},{auditIdFactory:()=>{throw Error('secret');}},{auditClock:()=>NaN},{auditClock:()=>-1},{auditClock:()=>Number.MAX_SAFE_INTEGER}]){const f=fixture({options}),r=await f.evaluate(input());assert.equal(r.auditRecorded,false);assert.equal(f.events.length,0);}});
test('no permission response is returned before durable acknowledgement',async()=>{let release,arrived;const ready=new Promise(r=>arrived=r);const f=fixture({options:{writeAuditEvent:event=>{arrived();return new Promise(r=>release=()=>r({status:'recorded',eventId:event.eventId}));}}});let returned=false;const pending=f.evaluate(input()).then(r=>{returned=true;return r;});await ready;assert.equal(returned,false);release();assert.equal((await pending).auditRecorded,true);});
