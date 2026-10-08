import {pathToFileURL} from 'node:url';
import {createVeteranCareRevocationService} from './veteran-care-revocation-v1.mjs';
import {createVeteranCareRevocationStatusReader} from './veteran-care-revocation-status-v1.mjs';
import {createRevocationFeedService} from '../gateway/revocation-feed-v1.mjs';
import {createRevocationAckService} from '../gateway/revocation-ack-v1.mjs';
import assert from 'node:assert/strict';
import {createVeteranCareFreshPermissionEvaluator as create} from './veteran-care-permission-freshness-v1.mjs';
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
  const evaluate=create({appId,providerId:'supabase:veteran-care',clock:()=>1500000,permissionClock:()=>1500000,idFactory:()=>grantId,
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

export async function runVeteranCareRevocationProof(){
 const results=[];
 const check=(scenario,actual,expected)=>{assert.equal(actual,expected,scenario);results.push({scenario,outcome:actual});};
 let authority=context(),revision=1,withdrawal=null,delivery=null,acknowledgement=null;
 const cached=structuredClone(authority);
 const a=fixture({snapshot:cached,lookup:async()=>stamp(revision)});
 const b=fixture({options:{getPermissionContext:async()=>authority,getCurrentPermissionRevision:async()=>stamp(revision)}});
 check('consumer A initially allowed',(await a.evaluate(input())).decision,'allow');
 check('consumer B initially allowed',(await b.evaluate(input())).decision,'allow');
 const ids=['44444444-4444-4444-8444-444444444444','55555555-5555-4555-8555-555555555555','66666666-6666-4666-8666-666666666666'];
 const shared={appId,providerId:'supabase:veteran-care',clock:()=>1500000,
 configuration:{mode:'veteran_care',issuer,authProjectUrl:url,databaseProjectUrl:url,storageProjectUrl:url},
 verifyAppCaller:async()=>({appId}),verifyIdentity:async()=>({shineId,authSubject,providerId:'supabase:veteran-care'}),
 auth:{getClaims:async()=>({data:{claims:{iss:issuer,aud:'authenticated',role:'authenticated',sub:authSubject,session_id:sessionId,exp:3000}}})},
 getSessionState:async()=>({status:'active',sessionId,authSubject,issuer,expiresAt:null})};
 const revoke=createVeteranCareRevocationService({...shared,revocationClock:()=>1500000,idFactory:()=>ids.shift(),
 getGrantDescriptor:async()=>authority.grants[0],
 revokeAccessGrant:async q=>{assert.equal(q.ownerShineId,shineId);assert.equal(q.appId,appId);assert.equal(q.grantId,grantId);
 authority.grants[0].status='revoked';revision++;authority.permissionSnapshot=stamp(revision);withdrawal={status:'recorded',sequenceNo:1};
 return {grantId,requestId:q.requestId,outcome:'revoked',reason_code:'grant-revoked-by-user',outboxRecorded:true};}});
 const revoked=await revoke({authContext:input().authContext,request:{grantId,revoke:true}});
 check('withdrawal recorded through real producer',revoked.status,'revoked');
 check('outbox does not imply consumer enforcement',revoked.consumerEnforcementVerified,false);
 const readStatus=createVeteranCareRevocationStatusReader({...shared,getGrantRevocationEvidence:async()=>({complete:true,grantId,appId,ownerShineId:shineId,scope,purpose,withdrawal,delivery,acknowledgement})});
 const statusInput={authContext:input().authContext,request:{grantId}};
 check('recorded withdrawal before delivery',(await readStatus(statusInput)).status,'withdrawal-recorded');
 check('stale cached consumer A refuses after withdrawal',(await a.evaluate(input())).reasonCode,'vc-permission-snapshot-stale');
 check('fresh consumer B refuses revoked grant',(await b.evaluate(input())).reasonCode,'vc-permission-missing');
 const deliveryId='77777777-7777-4777-8777-777777777777',ackRequestId='88888888-8888-4888-8888-888888888888';
 const feed=createRevocationFeedService({idFactory:()=>deliveryId,clock:()=>new Date(1500000).toISOString(),adapters:{
 verifyAppCaller:shared.verifyAppCaller,getAppRevocationStatus:async()=>({checkpointSequence:0,latestSequence:1,pendingCount:1}),getAppRevocationHealth:async()=>({freshnessState:'fresh'}),
 listAppRevocations:async()=>[{sequenceNo:1,grantId,appId}],recordAppRevocationDelivery:async q=>{delivery={deliveryId:q.deliveryId,appId:q.appId,afterSequence:q.afterSequence,sequenceNos:q.sequenceNos};}}});
 const delivered=await feed({appId,afterSequence:0,authContext:input().authContext});
 check('app feed delivery recorded',delivered.status,'ok');
 check('delivery before acknowledgement',(await readStatus(statusInput)).status,'delivered');
 const ack=createRevocationAckService({idFactory:()=>recordId,clock:()=>new Date(1500000).toISOString(),adapters:{verifyAppCaller:shared.verifyAppCaller,
 acknowledgeAppRevocations:async q=>{assert.equal(q.deliveryId,deliveryId);assert.equal(q.sequenceNo,1);acknowledgement={deliveryId:q.deliveryId,appId:q.appId,requestId:q.requestId,outcome:'advanced',sequenceNo:1,checkpointSequence:1};return {outcome:'advanced',reasonCode:'revocation-ack-advanced',checkpointSequence:1};}}});
 const acked=await ack({authContext:input().authContext,envelope:{revocationAck:'shine-foundation/revocation-ack-v1',schemaVersion:'1.0.0',requestId:ackRequestId,deliveryId,appId,sequenceNo:1,requestedAt:new Date(1500000).toISOString()}});
 check('real acknowledgement producer confirms',acked.status,'acknowledged');
 const acknowledged=await readStatus(statusInput);
 check('exact withdrawal delivery ack chain verified',acknowledged.status,'acknowledged');
 check('acknowledgement does not imply private enforcement',acknowledged.consumerEnforcementVerified,false);
 check('consumer A remains blocked after acknowledgement',(await a.evaluate(input())).decision,'deny');
 check('consumer B remains blocked after acknowledgement',(await b.evaluate(input())).decision,'deny');
 acknowledgement={...acknowledgement,deliveryId:recordId};
 check('wrong delivery acknowledgement rejected',(await readStatus(statusInput)).status,'unavailable');
 return {contract:'shine-foundation/veteran-care-revocation-proof-v1',evidence:'offline-synthetic',passed:results.length,
 consumerScope:'two isolated VC evaluator instances; one app-scoped feed',hostedAuthenticationVerified:false,durableDatabaseVerified:false,productionDisclosureVerified:false,results};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)console.log(JSON.stringify(await runVeteranCareRevocationProof(),null,2));
