// Offline synthetic proof journey. Never use these authorities in a consumer.
import assert from 'node:assert/strict';
import {createVeteranCareExpiringPermissionEvaluator} from './veteran-care-grant-expiry-v1.mjs';
import {VETERAN_CARE_ISSUER as issuer} from './veteran-care-identity-v1.mjs';
import {VETERAN_CARE_PROJECT_URL as projectUrl} from './veteran-care-project-boundary-v1.mjs';

const appId='shine.veteran-care',providerId='supabase:veteran-care';
const shineId='11111111-1111-4111-8111-111111111111',authSubject='22222222-2222-4222-8222-222222222222';
const sessionId='33333333-3333-4333-8333-333333333333',recordId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const preparationId='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',grantId='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const otherId='dddddddd-dddd-4ddd-8ddd-dddddddddddd',requestId='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const scope='veteran-care.record.read',purpose='veteran-care.appointment-preparation',category='veteran-care.record';
const startsAt='2026-10-08T00:00:00.000Z',expiresAt='2026-10-08T02:00:00.000Z';
const initialNow=Date.parse('2026-10-08T01:00:00.000Z');
const jwt='e30.'+Buffer.from(JSON.stringify({iss:issuer})).toString('base64url')+'.c3ludGhldGlj';
const fresh=()=>({now:initialNow,caller:appId,claims:{iss:issuer,aud:'authenticated',role:'authenticated',sub:authSubject,session_id:sessionId,exp:Date.parse('2026-10-08T03:00:00.000Z')/1000},
  sessionStatus:'active',resourceOwner:shineId,resourceVersion:3,preparationOwner:shineId,defenceDecision:'allow',complete:true,outage:false,
  grants:[{grantId,appId,ownerShineId:shineId,scope,purpose,status:'active',resourceSelector:{resourceId:recordId,resourceVersion:3},
    purposeBinding:{kind:'appointment-preparation',preparationId},notBefore:startsAt,expiresAt,consentWindow:{startsAt,expiresAt}}]});
const input=()=>({authContext:{appToken:'synthetic-app-proof',jwt},request:{capabilityId:'veteran-care.selected_record_read',input:{recordId,recordVersion:3}},purposeContext:{preparationId}});
let state=fresh(),trace=[];
const mark=name=>trace.push(name);
// Same evaluator is reused across changed authoritative state; no network,
// hosted Auth session, clinical data, execution or model calls are involved.
const evaluate=createVeteranCareExpiringPermissionEvaluator({appId,providerId,clock:()=>state.now,permissionClock:()=>state.now,idFactory:()=>requestId,
  configuration:{mode:'veteran_care',issuer,authProjectUrl:projectUrl,databaseProjectUrl:projectUrl,storageProjectUrl:projectUrl},
  verifyAppCaller:async({authContext,claimedAppId})=>{mark('app');assert.equal(claimedAppId,appId);assert.equal(authContext.appToken,'synthetic-app-proof');return {appId:state.caller};},
  verifyIdentity:async()=>{mark('identity');return {shineId,authSubject,providerId};},
  auth:{getClaims:async(token)=>{mark('claims');assert.equal(token,jwt);return {data:{claims:state.claims}};}},
  getSessionState:async(q)=>{mark('session');assert.equal(q.authSubject,authSubject);assert.equal(q.sessionId,sessionId);return {status:state.sessionStatus,sessionId,authSubject,issuer,expiresAt:null};},
  getResourceDescriptor:async(q)=>{mark('resource');assert.deepEqual(q,{appId,ownerShineId:shineId,recordId,recordVersion:3});return {resourceId:recordId,resourceVersion:state.resourceVersion,ownerShineId:state.resourceOwner,category};},
  getPreparationContext:async(q)=>{mark('preparation');assert.deepEqual(q,{preparationId,ownerShineId:shineId,appId,purpose});return {status:'available',preparationId,ownerShineId:state.preparationOwner,purpose};},
  getPermissionContext:async({request})=>{mark('permission');assert.equal(request.shineId,shineId);assert.equal(request.operation,'read');assert.deepEqual(request.purposeBinding,{kind:'appointment-preparation',preparationId});
    if(state.outage)throw new Error('synthetic authority outage');
    return {complete:state.complete,appManifest:{appId,foundation:{requestedScopes:[{scope,purpose,resourceCategory:category}]}},grants:state.grants,defenceDecision:state.defenceDecision};}
});
const full=['app','identity','claims','session','resource','preparation','permission'];
const scenarios=[
  ['permitted exact record and preparation',()=>{},'allow','vc-exact-grant-match',full],
  ['unverified app caller',s=>{s.caller='shine.other';},'deny','vc-app-caller-unverified',full.slice(0,1)],
  ['wrong verified token audience',s=>{s.claims.aud='another-app';},'deny','vc-token-audience-mismatch',full.slice(0,3)],
  ['wrong verified token subject',s=>{s.claims.sub=otherId;},'deny','vc-token-identity-mismatch',full.slice(0,3)],
  ['inactive current session',s=>{s.sessionStatus='inactive';},'deny','vc-session-not-current',full.slice(0,4)],
  ['another veteran resource',s=>{s.resourceOwner=otherId;},'deny','vc-resource-scope-mismatch',full.slice(0,5)],
  ['changed resource version',s=>{s.resourceVersion=4;},'deny','vc-resource-scope-mismatch',full.slice(0,5)],
  ['another veteran preparation',s=>{s.preparationOwner=otherId;},'deny','vc-purpose-binding-unverified',full.slice(0,6)],
  ['missing grant',s=>{s.grants=[];},'deny','vc-permission-missing',full],
  ['grant for another preparation',s=>{s.grants[0].purposeBinding.preparationId=otherId;},'deny','vc-permission-missing',full],
  ['ambiguous effective grants',s=>{s.grants.push({...s.grants[0],grantId:otherId});},'deny','vc-permission-ambiguous',full],
  ['expired approved window',s=>{s.now=Date.parse(expiresAt);},'deny','vc-permission-missing',full],
  ['extended mutable grant dates',s=>{s.grants[0].expiresAt='2026-10-08T03:00:00.000Z';},'deny','vc-permission-missing',full],
  ['Defence has not allowed access',s=>{s.defenceDecision='not-evaluated';},'deny','vc-defence-not-allowed',full],
  ['permission authority unavailable',s=>{s.outage=true;},'deny','vc-permission-authority-unavailable',full],
  ['permitted request after independent reset',()=>{},'allow','vc-exact-grant-match',full]
];
const results=[];
for(const [scenario,change,expected,reason,stages] of scenarios){
  state=fresh();trace=[];change(state);
  const result=await evaluate(input());
  assert.equal(result.decision,expected,scenario);assert.equal(result.reasonCode,reason,scenario);
  assert.deepEqual(trace,stages,scenario);assert.equal(result.executionPerformed,false,scenario);
  if(expected==='allow'){
    assert.equal(result.permissionValidUntil,expiresAt);assert.equal(result.grantId,grantId);
    assert.equal(result.request.requestId,requestId);assert.equal(result.request.resourceId,recordId);
    assert.equal(result.request.resourceVersion,3);assert.equal(result.request.shineId,shineId);
    assert.equal(result.authorizationApplied,true);
  }else{assert.equal(result.request,undefined);assert.equal(result.grantId,undefined);assert.equal(result.permissionValidUntil,undefined);}
  results.push({scenario,decision:result.decision,reasonCode:result.reasonCode,authoritiesVisited:[...trace],executionPerformed:false});
}
console.log(JSON.stringify({contract:'shine-foundation/veteran-care-synthetic-access-proof-v1',evidence:'offline-synthetic',passed:results.length,
  hostedAuthenticationVerified:false,sharedServiceExecutionVerified:false,productionDeploymentVerified:false,
  results},null,2));
