import test from 'node:test';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {createVeteranCareServerReadEntryPoint as create,VETERAN_CARE_SERVER_READ_ADAPTERS as required} from './veteran-care-server-read-v1.mjs';
import {VETERAN_CARE_ISSUER as issuer} from './veteran-care-identity-v1.mjs';
import {VETERAN_CARE_PROJECT_URL as url} from './veteran-care-project-boundary-v1.mjs';
const start='1970-01-01T00:16:40.000Z',end='1970-01-01T00:33:20.000Z';
const appId='shine.veteran-care',recordId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',preparationId='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',grantId='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const shineId='11111111-1111-4111-8111-111111111111',authSubject='22222222-2222-4222-8222-222222222222',sessionId='33333333-3333-4333-8333-333333333333';
const purpose='veteran-care.appointment-preparation';
const input=()=>({authContext:{appToken:'synthetic',jwt:'e30.'+Buffer.from(JSON.stringify({iss:issuer})).toString('base64url')+'.c2ln'}});
function fixture({options={}}={}){
  const healthCalls=[];const refs=[],resolutions=[];const calls=[],reads=[],registry=new Map([[sessionId,retryRow()]]);
  const configuredOptions={healthClock:()=>1500000,getCurrentVCCapabilityHealth:async q=>{healthCalls.push(q);return health(q);},credentialClock:()=>1500000,getCurrentCredentialReference:async q=>{refs.push(q);return reference();},resolveCredentialReference:async q=>{resolutions.push(q);return credentials();},resumeClock:()=>1500000,getCurrentResumeCheckpoint:async()=>checkpoint(),getExistingRetryIdentity:async q=>registry.get(q.operationId),taskClock:()=>1500000,getCurrentVCTask:async()=>task(),audienceClock:()=>1500000,verifyResultRecipient:async()=>recipient(),releaseClock:()=>1500000,readSelectedMemory:async q=>{reads.push(q);return row();},memoryClock:()=>1500000,getMemoryDescriptor:async()=>memory(),getMemoryPermissionContext:async()=>consent(),getCurrentMemoryPermissionRevision:async()=>revision(),bindingClock:()=>1500000,verifyIntegrationClient:async()=>({clientId:'shine.companion',clientKind:'first-party-companion'}),verifyCompanionUser:async()=>({verified:true,clientId:'shine.companion',shineId}),getCurrentVCCompanionLink:async q=>{calls.push(q);return link();},appId,providerId:'supabase:veteran-care',clock:()=>1500000,
    configuration:{mode:'veteran_care',issuer,authProjectUrl:url,databaseProjectUrl:url,storageProjectUrl:url},
    auth:{getClaims:async()=>({data:{claims:{iss:issuer,aud:'authenticated',role:'authenticated',sub:authSubject,session_id:sessionId,exp:3000}}})},
    verifyAppCaller:async()=>({appId}),verifyIdentity:async()=>({shineId,authSubject,providerId:'supabase:veteran-care'}),
    getSessionState:async()=>({status:'active',sessionId,authSubject,issuer,expiresAt:null}),
    getPreparationContext:async()=>({status:'available',preparationId,ownerShineId:shineId,purpose}),
    ...options};
  const adapters=Object.fromEntries(required.map(k=>[k,k==='getClaims'?configuredOptions.auth.getClaims:configuredOptions[k]]));
  const serverOptions={configuration:configuredOptions.configuration,adapters,clock:configuredOptions.clock};
  const entry=create(serverOptions),evaluate=q=>entry.readSelectedMemory(q);
  return {evaluate,entry,serverOptions,calls,reads,registry,refs,resolutions,healthCalls};
}
const link=()=>({foundationAppId:appId,clientId:'shine.companion',ownerShineId:shineId,linkId:sessionId,status:'active',revision:1,validUntil:end});
const joined=()=>({checkpointId:preparationId,credentialReferenceId:grantId,authContext:input().authContext});
const memory=()=>({memoryId:recordId,memoryVersion:3,ownerShineId:shineId,category:'veteran-care.context',status:'available'});
const revision=()=>({foundationAppId:appId,clientId:'shine.companion',ownerShineId:shineId,revision:1});
const memoryGrant=()=>({grantId,status:'active',foundationAppId:appId,clientId:'shine.companion',ownerShineId:shineId,linkId:sessionId,linkRevision:1,memoryId:recordId,memoryVersion:3,scope:'veteran-care.memory.read',operation:'read',purpose,preparationId,notBefore:start,expiresAt:end,consentStartsAt:start,consentExpiresAt:end});
const consent=()=>({complete:true,revision:1,grants:[memoryGrant()]});
const row=()=>({memoryId:recordId,memoryVersion:3,ownerShineId:shineId,category:'veteran-care.context',content:'synthetic private memory'});
const recipient=()=>({verified:true,audience:'vc-trusted-server',appId,actorShineId:shineId,servicePrincipalId:'vc-orchestrator',revision:1,validUntil:end});
const task=()=>({taskId:grantId,foundationAppId:appId,ownerShineId:shineId,memoryId:recordId,memoryVersion:3,preparationId,purpose,operation:'read',status:'running',revision:1,validUntil:end});
const checkpoint=()=>({checkpointId:preparationId,foundationAppId:appId,ownerShineId:shineId,operationId:sessionId,taskId:grantId,memoryId:recordId,memoryVersion:3,preparationId,stage:'selected-memory-read',status:'resumable',revision:1,validUntil:end});
function retryRow(){const binding={foundationAppId:appId,actorShineId:shineId,clientId:'shine.companion',taskId:grantId,memoryId:recordId,memoryVersion:3,preparationId,operation:'read',scope:'veteran-care.memory.read',purpose,audience:'vc-trusted-server'};return {operationId:sessionId,fingerprint:createHash('sha256').update(JSON.stringify(binding)).digest('hex'),binding};}
const reference=()=>({credentialReferenceId:grantId,foundationAppId:appId,ownerShineId:shineId,purpose:'veteran-care.resume',audience:'vc-trusted-server',status:'active',revision:1,validUntil:end});
const credentials=()=>({credentialReferenceId:grantId,revision:1,companionAuthContext:{clientToken:'vault-client-secret',userToken:'vault-user-secret'},recipientAuthContext:{serviceToken:'vault-service-secret'}});
const observed='1970-01-01T00:24:00.000Z';
const health=q=>({...q,healthStatus:'available',lastOutcome:'success',lastEventAt:observed,evidenceRef:sessionId,evidenceMode:'synthetic'});
test('default incomplete server wiring blocks without invoking any adapter',async()=>{
  for(const options of [undefined,null,{}, {configuration:{},adapters:{}}]){
    const entry=create(options),result=await entry.readSelectedMemory(joined());
    assert.equal(entry.configurationStatus,'blocked');assert.equal(entry.authorityProvided,false);
    assert.equal(result.status,'unavailable');assert.equal(result.retrievalPerformed,false);
    assert.equal(result.resultReturned,false);assert.ok(Object.isFrozen(entry));
  }
});
test('every required dependency must be present and callable before any private read',async()=>{
  for(const key of required)for(const value of [undefined,null,true]){
    const f=fixture();f.serverOptions.adapters[key]=value;
    const entry=create(f.serverOptions),result=await entry.readSelectedMemory(joined());
    assert.equal(entry.configurationStatus,'blocked',key);assert.equal(result.retrievalPerformed,false);
    assert.equal(f.healthCalls.length,0);assert.equal(f.reads.length,0);
  }
});
test('configured server executes the real chain with synthetic evidence and no transport',async()=>{
  const f=fixture(),result=await f.evaluate(joined());
  assert.equal(f.entry.configurationStatus,'dependencies-configured');
  assert.equal(f.entry.authorityProvided,false);assert.equal(result.status,'server-read-result');
  assert.equal(result.serverOnly,true);assert.equal(result.transportPerformed,false);
  assert.equal(result.modelDisclosurePermitted,false);assert.equal(result.memoryWritePermitted,false);
  assert.equal(result.credentialsReturned,false);assert.equal(f.reads.length,1);
  assert.equal(f.healthCalls.length,24);assert.equal(f.refs.length,3);
  assert.equal(result.capabilityHealth.dependencies.every(d=>d.evidenceMode==='synthetic'),true);
  assert.ok(Object.isFrozen(result));
  assert.equal(JSON.stringify(result).includes('vault-'),false);
  assert.equal(JSON.stringify(result).includes('e30.'),false);
});
test('wrong project and caller-supplied composition overrides cannot configure the server',async()=>{
  for(const change of [q=>q.configuration={...q.configuration,databaseProjectUrl:'https://other.supabase.co'},
    q=>q.appId='shine.travel',q=>q.gate=async()=>({status:'capability-health-checked-result'}),
    q=>q.adapters.writeSelectedMemory=async()=>{},q=>q.clock=42]){
    const f=fixture();change(f.serverOptions);
    assert.equal(create(f.serverOptions).configurationStatus,'blocked');assert.equal(f.reads.length,0);
  }
});
test('getters symbols and inherited configuration are rejected without executing getters',async()=>{
  let calls=0;
  for(const change of [q=>Object.defineProperty(q,'adapters',{get(){calls++;throw Error('secret');}}),
    q=>Object.defineProperty(q.adapters,'getClaims',{get(){calls++;throw Error('secret');}}),
    q=>Object.defineProperty(q.configuration,'issuer',{get(){calls++;throw Error('secret');}}),
    q=>q.adapters[Symbol('hidden')]=()=>{},q=>Object.setPrototypeOf(q,{extra:true})]){
    const f=fixture();change(f.serverOptions);assert.equal(create(f.serverOptions).configurationStatus,'blocked');
  }
  assert.equal(calls,0);
});
test('construction snapshots configuration and adapter function references',async()=>{
  const f=fixture();f.serverOptions.configuration.issuer='wrong';
  f.serverOptions.adapters.readSelectedMemory=async()=>{throw Error('replaced');};
  f.serverOptions.clock=()=>NaN;
  assert.equal((await f.evaluate(joined())).status,'server-read-result');assert.equal(f.reads.length,1);
  assert.equal(create(f.serverOptions).configurationStatus,'blocked');
});
test('request authority extras malformed tokens and accessors fail before authority adapters',async()=>{
  let getters=0;
  for(const change of [q=>q.healthStatus='available',q=>q.request={operation:'write'},
    q=>q.recipientAuthContext={serviceToken:'override'},q=>q.authContext.claims={role:'authenticated'},
    q=>q.authContext.appToken='x'.repeat(8193),q=>q.authContext.jwt='x'.repeat(16385),
    q=>q.checkpointId='bad',q=>Object.defineProperty(q,'authContext',{get(){getters++;throw Error('secret');}})]){
    const f=fixture(),q=joined();change(q);const result=await f.evaluate(q);
    assert.equal(result.status,'denied');assert.equal(f.healthCalls.length,0);assert.equal(f.reads.length,0);
  }
  assert.equal(getters,0);
});
test('request is captured before asynchronous verification',async()=>{
  const f=fixture(),q=joined(),pending=f.evaluate(q);
  q.checkpointId=recordId;q.credentialReferenceId=recordId;q.authContext.jwt='wrong';
  const result=await pending;assert.equal(result.status,'server-read-result');
  assert.equal(result.checkpoint.checkpointId,preparationId);assert.equal(result.credentialReference.credentialReferenceId,grantId);
});
test('configured dependencies cannot replace fresh owner session consent task or recipient checks',async()=>{
  for(const options of [{getSessionState:async()=>({status:'revoked'})},
    {verifyCompanionUser:async()=>({verified:true,clientId:'shine.companion',shineId:recordId})},
    {getMemoryPermissionContext:async()=>({...consent(),grants:[]})},
    {getCurrentVCTask:async()=>({...task(),status:'cancelled'})},
    {verifyResultRecipient:async()=>({...recipient(),audience:'shine.ai'})},
    {getExistingRetryIdentity:async()=>null},
    {getCurrentCredentialReference:async()=>({...reference(),status:'revoked'})}]){
    const f=fixture({options}),result=await f.evaluate(joined());
    assert.notEqual(result.status,'server-read-result');assert.equal(result.result,undefined);assert.equal(f.reads.length,0);
  }
});
test('cancellation after retrieval withholds private content',async()=>{
  let cancelled=false;
  const f=fixture({options:{readSelectedMemory:async()=>{cancelled=true;return row();},
    getCurrentVCTask:async()=>({...task(),status:cancelled?'cancelled':'running'})}});
  const result=await f.evaluate(joined());assert.equal(result.retrievalPerformed,true);
  assert.equal(result.resultReturned,false);assert.equal(result.result,undefined);
  assert.equal(JSON.stringify(result).includes('synthetic private memory'),false);
});
test('adapter exceptions and invalid server clock are redacted and never release a result',async()=>{
  for(const options of [{getCurrentVCCapabilityHealth:async()=>{throw Error('private-host-secret');}},
    {readSelectedMemory:async()=>{throw Error('private-content-secret');}},{clock:()=>NaN}]){
    const f=fixture({options}),result=await f.evaluate(joined());
    assert.equal(result.status,'unavailable');assert.equal(result.resultReturned,false);
    assert.equal(JSON.stringify(result).includes('secret'),false);
  }
});
test('concurrent requests independently recheck authority and never reuse content',async()=>{
  const f=fixture(),results=await Promise.all([f.evaluate(joined()),f.evaluate(joined())]);
  assert.ok(results.every(r=>r.status==='server-read-result'));assert.equal(f.reads.length,2);
  assert.equal(f.resolutions.length,2);assert.equal(f.healthCalls.length,48);
});
test('post-read health failure withholds content and accurately records adapter invocation',async()=>{
  let read=false;
  const f=fixture({options:{readSelectedMemory:async()=>{read=true;return row();},
    getCurrentVCCapabilityHealth:async q=>({...health(q),lastOutcome:read?'failure':'success'})}});
  const result=await f.evaluate(joined());assert.equal(result.status,'unavailable');
  assert.equal(result.retrievalPerformed,true);assert.equal(result.resultReturned,false);
  assert.equal(result.result,undefined);
});
test('credential rotation during retrieval refuses the result and next request resolves afresh',async()=>{
  let rotated=false;
  const f=fixture({options:{readSelectedMemory:async()=>{rotated=true;return row();},
    getCurrentCredentialReference:async()=>({...reference(),revision:rotated?2:1})}});
  const result=await f.evaluate(joined());assert.notEqual(result.status,'server-read-result');
  assert.equal(result.retrievalPerformed,true);assert.equal(result.result,undefined);
  const next=await f.evaluate(joined());assert.notEqual(next.status,'server-read-result');
  assert.equal(next.retrievalPerformed,false);
});
