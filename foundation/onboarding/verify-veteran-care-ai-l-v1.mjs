import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {createVeteranCareAIToolAuthorityEvaluator} from './veteran-care-ai-tool-v1.mjs';
import {createVeteranCarePrivateHandleService} from './veteran-care-private-handle-v1.mjs';
import {createVeteranCareTaskAuthorityGate} from './veteran-care-task-authority-v1.mjs';
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
const memoryId='dddddddd-dddd-4ddd-8ddd-dddddddddddd',taskId='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',memoryGrantId='ffffffff-ffff-4fff-8fff-ffffffffffff';
const modules=['veteran-care-ai-caller-v1.mjs','veteran-care-ai-decision-v1.mjs','veteran-care-private-handle-v1.mjs','veteran-care-l-binding-v1.mjs','veteran-care-memory-scope-v1.mjs','veteran-care-memory-read-v1.mjs','veteran-care-ai-tool-v1.mjs','veteran-care-result-audience-v1.mjs','veteran-care-task-authority-v1.mjs'];

// Offline contract proof. All auth, policy, database and service adapters below
// are synthetic projections. This does not authenticate any real AI or L service.
export async function runVeteranCareAILProof(){
  const results=[];
  const check=(scenario,actual,expected)=>{assert.equal(actual,expected,scenario);results.push({scenario,outcome:actual});};
  let now=1500000,record=context(),recordRevision=1,memoryConsent=true,memoryRevision=1,
    aiVerified=true,toolActive=true,lActor=shineId,recipientAudience='vc-trusted-server',taskStatus='running',cancelOnRead=false,reads=0;
  const registry=new Map();
  const options={appId,providerId:'supabase:veteran-care',clock:()=>now,permissionClock:()=>now,decisionClock:()=>now,toolClock:()=>now,handleClock:()=>now,bindingClock:()=>now,memoryClock:()=>now,releaseClock:()=>now,audienceClock:()=>now,taskClock:()=>now,idFactory:()=>grantId,
    configuration:{mode:'veteran_care',issuer,authProjectUrl:url,databaseProjectUrl:url,storageProjectUrl:url},
    auth:{getClaims:async()=>({data:{claims:{iss:issuer,aud:'authenticated',role:'authenticated',sub:authSubject,session_id:sessionId,exp:3000}}})},
    verifyAppCaller:async()=>({appId}),verifyIdentity:async()=>({shineId,authSubject,providerId:'supabase:veteran-care'}),
    getSessionState:async()=>({status:'active',sessionId,authSubject,issuer,expiresAt:null}),
    getResourceDescriptor:async()=>({resourceId:recordId,resourceVersion:3,ownerShineId:shineId,category:resourceCategory}),
    getPreparationContext:async()=>({status:'available',preparationId,ownerShineId:shineId,purpose}),
    getPermissionContext:async()=>record,getCurrentPermissionRevision:async()=>stamp(recordRevision),
    getAICallerRegistration:async()=>({foundationAppId:appId,aiCallerId:'shine-veteran-care',targetServiceAppId:'shine.ai',status:'active',revision:1,keyId:'vc-adj-v1'}),
    resolveVerifiedAICallerProof:async q=>({verified:aiVerified,proofRef:q.proofRef,foundationAppId:appId,actorShineId:shineId,appId:'shine-veteran-care',keyId:'vc-adj-v1'}),
    getCurrentAIToolPolicy:async()=>({status:toolActive?'active':'disabled',foundationAppId:appId,aiCallerId:'shine-veteran-care',targetServiceAppId:'shine.ai',toolId:'veteran-care.selected_record_read',capabilityId:'veteran-care.selected_record_read',scope,operation:'read',purpose,policyRevision:1,validUntil:end}),
    resolveVerifiedAIToolProposal:async q=>({verified:aiVerified,...q}),
    handleIdFactory:()=>recordId,insertPrivateHandle:async row=>{if(registry.has(row.handleId))return {status:'conflict',handleId:row.handleId};registry.set(row.handleId,row);return {status:'inserted',handleId:row.handleId};},getPrivateHandle:async id=>registry.get(id),
    verifyIntegrationClient:async()=>({clientId:'shine.companion',clientKind:'first-party-companion'}),verifyCompanionUser:async()=>({verified:true,clientId:'shine.companion',shineId:lActor}),
    getCurrentVCCompanionLink:async()=>({foundationAppId:appId,clientId:'shine.companion',ownerShineId:shineId,linkId:sessionId,status:'active',revision:1,validUntil:end}),
    getMemoryDescriptor:async()=>({memoryId,memoryVersion:3,ownerShineId:shineId,category:'veteran-care.context',status:'available'}),
    getMemoryPermissionContext:async()=>({complete:true,revision:memoryRevision,grants:memoryConsent?[{grantId:memoryGrantId,status:'active',foundationAppId:appId,clientId:'shine.companion',ownerShineId:shineId,linkId:sessionId,linkRevision:1,memoryId,memoryVersion:3,scope:'veteran-care.memory.read',operation:'read',purpose,preparationId,notBefore:start,expiresAt:end,consentStartsAt:start,consentExpiresAt:end}]:[]}),
    getCurrentMemoryPermissionRevision:async()=>({foundationAppId:appId,clientId:'shine.companion',ownerShineId:shineId,revision:memoryRevision}),
    readSelectedMemory:async q=>{reads++;if(cancelOnRead)taskStatus='cancelled';return {memoryId:q.memoryId,memoryVersion:q.memoryVersion,ownerShineId:q.ownerShineId,category:q.category,content:'synthetic private context'};},
    verifyResultRecipient:async()=>({verified:true,audience:recipientAudience,appId,actorShineId:shineId,servicePrincipalId:'synthetic-vc-orchestrator',revision:1,validUntil:end}),
    getCurrentVCTask:async()=>({taskId,foundationAppId:appId,ownerShineId:shineId,memoryId,memoryVersion:3,preparationId,purpose,operation:'read',status:taskStatus,revision:1,validUntil:end})};
  const tool=createVeteranCareAIToolAuthorityEvaluator(options),handles=createVeteranCarePrivateHandleService(options),task=createVeteranCareTaskAuthorityGate(options);
  const decision=()=>({...input(),aiCallerProof:{proofRef:sessionId}});
  const proposal=()=>({authContext:input().authContext,aiCallerProof:{proofRef:sessionId},purposeContext:{preparationId},toolCall:{toolCallId:taskId,toolId:'veteran-care.selected_record_read',arguments:{recordId,recordVersion:3}}});
  const retrieval=()=>({taskId,authContext:input().authContext,companionAuthContext:{clientToken:'synthetic-client',userToken:'synthetic-user'},recipientAuthContext:{serviceToken:'synthetic-service'},request:{operation:'read',memoryId,memoryVersion:3,preparationId}});
  const approved=await tool(proposal());
  check('verified AI caller and exact record tool scope',approved.status,'tool-scope-approved');
  check('scope metadata does not invoke AI tool',approved.toolInvoked,false);
  check('scope metadata does not permit model disclosure',approved.modelDisclosurePermitted,false);
  const minted=await handles.mint(decision());check('exact record produces opaque private handle',minted.status,'handle-ready');
  const resolved=await handles.resolve({handleId:minted.handle.handleId,decisionInput:decision()});check('fresh caller and grant resolve private handle',resolved.status,'handle-resolved');
  const delivered=await task(retrieval());check('separate L consent and running task yield internal result',delivered.status,'task-bound-result');
  check('record and memory flow share verified actor',approved.envelope.actorShineId===delivered.recipient.actorShineId,true);
  check('record and memory preparation remain exact',approved.envelope.preparationId===preparationId&&delivered.result.memoryId===memoryId,true);
  check('private result stays within VC server audience',delivered.audience,'vc-trusted-server');
  check('private result is not transported',delivered.transportPerformed,false);
  aiVerified=false;check('unverified AI proof withholds tool scope',(await tool(proposal())).envelope===undefined,true);aiVerified=true;
  const broad=proposal();broad.toolCall.toolId='memory.search';check('model-selected broader tool refused',(await tool(broad)).envelope===undefined,true);
  toolActive=false;check('disabled AI tool policy withholds scope',(await tool(proposal())).envelope===undefined,true);toolActive=true;
  const beforeMissing=reads;memoryConsent=false;check('record consent cannot substitute for memory consent',(await task(retrieval())).result===undefined,true);
  check('missing memory consent performs no read',reads===beforeMissing,true);memoryConsent=true;
  const beforeWrong=reads;lActor=sessionId;check('different L user cannot borrow VC identity',(await task(retrieval())).result===undefined,true);check('different L user performs no read',reads===beforeWrong,true);lActor=shineId;
  recipientAudience='shine.ai';check('AI audience cannot receive private L result',(await task(retrieval())).result===undefined,true);recipientAudience='vc-trusted-server';
  cancelOnRead=true;const cancelled=await task(retrieval());check('cancellation during selected read suppresses result',cancelled.resultReturned,false);cancelOnRead=false;
  const afterCancel=reads;check('retry of cancelled task remains denied',(await task(retrieval())).result===undefined,true);check('cancelled retry performs no further read',reads===afterCancel,true);taskStatus='running';
  record.grants[0].status='revoked';recordRevision++;record.permissionSnapshot=stamp(recordRevision);
  check('record withdrawal invalidates prior opaque handle',(await handles.resolve({handleId:minted.handle.handleId,decisionInput:decision()})).envelope===undefined,true);
  check('record withdrawal defeats fresh AI tool scope',(await tool(proposal())).envelope===undefined,true);
  record=context();recordRevision=1;memoryConsent=false;memoryRevision++;
  check('memory withdrawal defeats freshly checked task result',(await task(retrieval())).result===undefined,true);memoryConsent=true;
  now=1800000;check('handle lifetime cannot outlive its own deadline',(await handles.resolve({handleId:minted.handle.handleId,decisionInput:decision()})).envelope===undefined,true);
  const sourceManifest=await Promise.all(modules.map(async path=>({path,sha256:createHash('sha256').update(await readFile(new URL(path,import.meta.url))).digest('hex')})));
  return {contract:'shine-foundation/veteran-care-ai-l-proof-v1',schemaVersion:'1.0.0',status:'passed',evidenceMode:'offline-synthetic',liveIntegrationVerified:false,
    realCredentialsUsed:false,modelCallsPerformed:0,externalTransportPerformed:false,sourceManifest,checksPassed:results.length,checksTotal:results.length,results,
    liveOpen:['authenticated AI caller/proposal verification and tool policy','protected L user/link/consent/read adapters','recipient transport and durable task lifecycle','paired consumer execution and disclosure evidence']};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){console.log(JSON.stringify(await runVeteranCareAILProof(),null,2));}
