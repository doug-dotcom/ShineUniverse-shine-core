import test from 'node:test';
import assert from 'node:assert/strict';
import {createVeteranCareAIDecisionBuilder as create} from './veteran-care-ai-decision-v1.mjs';
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
  const evaluate=create({decisionClock:()=>1500000,getAICallerRegistration:async()=>({foundationAppId:appId,aiCallerId:'shine-veteran-care',targetServiceAppId:'shine.ai',status:'active',revision:1,keyId:'vc-adj-v1'}),resolveVerifiedAICallerProof:async q=>({verified:true,proofRef:q.proofRef,foundationAppId:appId,actorShineId:shineId,appId:'shine-veteran-care',keyId:'vc-adj-v1'}),appId,providerId:'supabase:veteran-care',clock:()=>1500000,permissionClock:()=>1500000,idFactory:()=>grantId,
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
const joined=()=>({...input(),aiCallerProof:{proofRef:sessionId}});
test('one caller and exact record grant form bounded immutable decision metadata',async()=>{const r=await fixture().evaluate(joined());assert.equal(r.status,'decision-ready');assert.equal(r.decision,'allow-selected-read');assert.equal(r.executionPermitted,false);assert.equal(r.envelope.modelDisclosurePermitted,false);assert.equal(r.envelope.requiresFreshExecutionCheck,true);assert.equal(r.envelope.audience,'shine.ai');assert.equal(r.envelope.resourceId,recordId);assert.equal(r.envelope.resourceVersion,3);assert.equal(r.envelope.preparationId,preparationId);assert.equal(r.envelope.validUntil,end);assert.ok(Object.isFrozen(r.envelope));assert.equal(JSON.stringify(r).includes('synthetic'),false);});
test('unverified AI caller stops before private permission authority',async()=>{let reads=0;const f=fixture({options:{resolveVerifiedAICallerProof:async()=>null,getPermissionContext:async()=>{reads++;return context();}}});const r=await f.evaluate(joined());assert.equal(r.decision,'deny');assert.equal(reads,0);assert.equal(r.envelope,undefined);});
test('missing revoked stale or wrong-purpose grants cannot produce decision envelope',async()=>{for(const mutate of [c=>c.grants=[],c=>c.grants[0].status='revoked',c=>c.permissionSnapshot=stamp(2),c=>c.grants[0].purposeBinding.preparationId=sessionId]){const snapshot=context();mutate(snapshot);const r=await fixture({snapshot}).evaluate(joined());assert.equal(r.decision,'deny');assert.equal(r.envelope,undefined);}});
test('principal changes between caller binding and permission evaluation cannot cross actors',async()=>{let count=0;const other=sessionId;const f=fixture({options:{verifyIdentity:async()=>({shineId:count++?other:shineId,authSubject,providerId:'supabase:veteran-care'}),getResourceDescriptor:async()=>({resourceId:recordId,resourceVersion:3,ownerShineId:other,category:resourceCategory}),getPreparationContext:async()=>({status:'available',preparationId,ownerShineId:other,purpose}),getPermissionContext:async()=>{const c=context();c.grants[0].ownerShineId=other;c.permissionSnapshot={...stamp(),ownerShineId:other};return c;},getCurrentPermissionRevision:async()=>({...stamp(),ownerShineId:other})}});assert.equal((await f.evaluate(joined())).reasonCode,'vc-ai-decision-actor-mismatch');});
test('expiry at final decision boundary and invalid clock withhold envelope',async()=>{for(const decisionClock of [()=>2000000,()=>NaN,()=>-1]){const r=await fixture({options:{decisionClock}}).evaluate(joined());assert.equal(r.decision,'deny');assert.equal(r.envelope,undefined);}});
test('caller mutation and authority-selection fields cannot widen the captured record request',async()=>{const f=fixture(),i=joined(),pending=f.evaluate(i);i.request.input.recordId=preparationId;i.aiCallerProof.proofRef=recordId;assert.equal((await pending).envelope.resourceId,recordId);for(const mutate of [i=>i.ownerShineId=sessionId,i=>i.request.input.content='edit',i=>i.aiCallerProof.aiCallerId='shine-fish',i=>Object.defineProperty(i.purposeContext,'preparationId',{get(){throw Error('do not invoke');}})]){const q=joined();mutate(q);assert.equal((await fixture().evaluate(q)).reasonCode,'vc-ai-decision-input-invalid');}});
