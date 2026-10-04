import test from 'node:test';
import assert from 'node:assert/strict';
import {
  projectWellnessHealthMinimalHandoff,
  WELLNESS_CONCIERGE_PURPOSE,
} from './wellness-concierge-health-minimal-v1.mjs';
import {createConciergeExecuteService,createConciergePlanService} from './concierge-orchestration-v1.mjs';

const REQUEST='11111111-1111-4111-8111-111111111111';
const HANDOFF='22222222-2222-4222-8222-222222222222';
const CLOCK='2026-09-30T06:30:00.000Z';

const handoff=()=>({
  healthMinimalHandoff:'shine-wellness/concierge-health-minimal-v1',
  schemaVersion:'1.0.0',
  handoffId:HANDOFF,
  canonicalRecordId:'wellness-record-1',
  permissionDecisionId:'permission-1',
  actionCode:'appointment-book',
  target:{
    kind:'provider',
    displayName:'Example Health Service',
    contact:{phone:'07 3000 0000',url:'https://example.test/book'}
  },
  timing:{
    dueAt:'2026-10-01T00:00:00.000Z',
    window:'morning',
    timezone:'Australia/Brisbane'
  },
  location:{displayName:'Main clinic',address:'1 Example Street'},
  channel:'phone',
  sourceRecordIds:['wellness-record-1']
});

test('projects the bounded Wellness logistics contract without adding clinical fields',()=>{
  assert.deepEqual(projectWellnessHealthMinimalHandoff(handoff()),handoff());
});

test('rejects unknown clinical fields at every level',()=>{
  assert.equal(projectWellnessHealthMinimalHandoff({...handoff(),diagnosis:'private'}),null);
  const nested=handoff();
  nested.target={...nested.target,clinicalNotes:'private'};
  assert.equal(projectWellnessHealthMinimalHandoff(nested),null);
});

test('requires the canonical record to remain in the opaque source chain',()=>{
  assert.equal(projectWellnessHealthMinimalHandoff({...handoff(),sourceRecordIds:['other-record']}),null);
});

test('Wellness plan requests are restricted to care logistics purpose',async()=>{
  let verified=0;
  const service=createConciergePlanService({
    clock:()=>CLOCK,
    adapters:{
      verifyIntegrationClient:async()=>{verified++;return {clientId:'shine.wellness'}},
      verifyIntegrationIdentity:async()=>({shineId:'owner'}),
      verifyIntegrationDelegation:async()=>({shineId:'owner',clientId:'shine.wellness'}),
      planConciergeRequest:async()=>({id:'plan'})
    }
  });
  const result=await service({
    envelope:{
      conciergePlan:'shine-concierge/plan-v1',
      schemaVersion:'1.0.0',
      requestId:REQUEST,
      clientId:'shine.wellness',
      purpose:'clinical-chart-review',
      capabilityIds:['calendar.book'],
      requestedAt:CLOCK
    },
    authContext:{}
  });
  assert.equal(result.status,'invalid');
  assert.equal(verified,0);
});

function executeAdapters({capture}){
  return {
    verifyIntegrationClient:async()=>({clientId:'shine.wellness'}),
    verifyIntegrationIdentity:async()=>({shineId:'owner'}),
    verifyIntegrationDelegation:async()=>({shineId:'owner',clientId:'shine.wellness'}),
    gateConciergeExecution:async()=>({
      status:'allowed',
      plan:{
        purpose:WELLNESS_CONCIERGE_PURPOSE,
        steps:[{stepId:'step-1',capabilityId:'calendar.book',appId:'calendar'}]
      }
    }),
    invokeCapability:async args=>{capture.push(args);return {status:'completed',result:{ok:true}}},
    recordConciergeExecutionEvent:async()=>({ok:true}),
    getConciergeResumeState:async()=>({steps:[]}),
    recordConciergeStepCheckpoint:async()=>({ok:true}),
    queueConciergeRetry:async()=>({ok:true})
  };
}

test('validates all Wellness inputs before invoking a specialist',async()=>{
  const capture=[];
  const service=createConciergeExecuteService({
    clock:()=>CLOCK,
    idFactory:()=>HANDOFF,
    adapters:executeAdapters({capture})
  });
  const result=await service({
    envelope:{
      conciergeExecute:'shine-concierge/execute-v1',
      schemaVersion:'1.0.0',
      requestId:REQUEST,
      clientId:'shine.wellness',
      requestedAt:CLOCK,
      inputs:{'calendar.book':handoff()}
    },
    authContext:{}
  });
  assert.equal(result.status,'completed');
  assert.equal(capture.length,1);
  assert.deepEqual(capture[0].input,handoff());
  assert.equal(capture[0].context.clientId,'shine.wellness');
  assert.equal(capture[0].context.purpose,WELLNESS_CONCIERGE_PURPOSE);
  assert.equal('diagnosis' in capture[0].input,false);
});

test('rejects a clinical payload before the first specialist invocation',async()=>{
  const capture=[];
  const service=createConciergeExecuteService({
    clock:()=>CLOCK,
    idFactory:()=>HANDOFF,
    adapters:executeAdapters({capture})
  });
  const invalid={...handoff(),medications:['private']};
  const result=await service({
    envelope:{
      conciergeExecute:'shine-concierge/execute-v1',
      schemaVersion:'1.0.0',
      requestId:REQUEST,
      clientId:'shine.wellness',
      requestedAt:CLOCK,
      inputs:{'calendar.book':invalid}
    },
    authContext:{}
  });
  assert.equal(result.status,'invalid');
  assert.equal(result.reasonCode,'concierge-wellness-health-minimal-input-invalid');
  assert.equal(capture.length,0);
});

test('execution and checkpoint writes retain the same parent request and action step',async()=>{
 const capture=[],checkpoints=[];
 const adapters=executeAdapters({capture});
 adapters.recordConciergeStepCheckpoint=async args=>{checkpoints.push(args);return {ok:true}};
 const service=createConciergeExecuteService({adapters,clock:()=>CLOCK,idFactory:()=>HANDOFF});
 const result=await service({envelope:{conciergeExecute:'shine-concierge/execute-v1',schemaVersion:'1.0.0',
 requestId:REQUEST,clientId:'shine.wellness',requestedAt:CLOCK,inputs:{'calendar.book':handoff()}},authContext:{}});
 assert.equal(result.status,'completed');
 assert.equal(capture[0].context.conciergeRequestId,REQUEST);
 assert.equal(checkpoints[0].requestId,REQUEST);
 assert.equal(checkpoints[0].stepId,capture[0].requestId);
 assert.equal(checkpoints[0].capabilityId,capture[0].capabilityId);
});
test('a checkpoint naming a different capability cannot be reused for this action',async()=>{
 const capture=[];const adapters=executeAdapters({capture});
 adapters.getConciergeResumeState=async()=>({steps:[{completed:true,stepId:'step-1',capabilityId:'calendar.cancel',result:{ok:true}}]});
 const service=createConciergeExecuteService({adapters,clock:()=>CLOCK,idFactory:()=>HANDOFF});
 const result=await service({envelope:{conciergeExecute:'shine-concierge/execute-v1',schemaVersion:'1.0.0',
 requestId:REQUEST,clientId:'shine.wellness',requestedAt:CLOCK,inputs:{'calendar.book':handoff()}},authContext:{}});
 assert.equal(result.status,'unavailable');assert.equal(result.reasonCode,'concierge-checkpoint-binding-mismatch');
 assert.equal(capture.length,0);
});

test('only confirmed pre-dispatch failures queue an automatic retry',async()=>{
 for(const reason of ['capability-adapter-quarantined','capability-adapter-registry-unavailable',
 'capability-adapter-health-unavailable','capability-endpoint-unavailable','capability-endpoint-rejected',
 'capability-response-invalid','capability-invocation-failed','permission-denied']){
  let queued=0,invoked=0;
  const adapters=executeAdapters({capture:[]});
  adapters.invokeCapability=async()=>{invoked++;return {status:'failed',reasonCode:reason}};
  adapters.queueConciergeRetry=async()=>{queued++;return {ok:true}};
  const service=createConciergeExecuteService({clock:()=>CLOCK,idFactory:()=>HANDOFF,adapters});
  await service({envelope:{conciergeExecute:'shine-concierge/execute-v1',schemaVersion:'1.0.0',
   requestId:REQUEST,clientId:'shine.wellness',requestedAt:CLOCK,inputs:{'calendar.book':handoff()}},authContext:{}});
  assert.equal(queued,reason.startsWith('capability-adapter-')?1:0,reason);
  assert.equal(invoked,1,reason);
 }
});

test('checkpoint lookup outage stops execution and recovery reuses durable completion',async()=>{
 const capture=[],durable=[];
 const adapters=executeAdapters({capture});
 const args={envelope:{conciergeExecute:'shine-concierge/execute-v1',schemaVersion:'1.0.0',
 requestId:REQUEST,clientId:'shine.wellness',requestedAt:CLOCK,inputs:{'calendar.book':handoff()}},authContext:{}};
 const run=()=>createConciergeExecuteService({clock:()=>CLOCK,idFactory:()=>HANDOFF,adapters})(args);
 adapters.getConciergeResumeState=async()=>{throw new Error('private database failure')};
 assert.equal((await run()).reasonCode,'concierge-resume-state-unavailable');
 assert.equal(capture.length,0);
 adapters.getConciergeResumeState=async()=>({steps:durable});
 adapters.recordConciergeStepCheckpoint=async checkpoint=>{
  durable.push({...checkpoint,completed:true});return {ok:true};
 };
 assert.equal((await run()).status,'completed');
 assert.equal(capture.length,1);
 const resumed=await run();
 assert.equal(resumed.status,'completed');
 assert.equal(capture.length,1);
 assert.equal(resumed.results[0].reasonCode,'concierge-step-reused');
});

test('recovery requires current authorisation before accessing saved results',async()=>{
 for(const failure of ['client','identity','delegation','blocked','unknown','missing']){
  const adapters=executeAdapters({capture:[]});let downstream=0;
  adapters.getConciergeResumeState=async()=>{downstream++;return {steps:[{completed:true,stepId:'step-1',result:{private:true}}]}};
  adapters.invokeCapability=async()=>{downstream++};
  if(failure==='client') adapters.verifyIntegrationClient=async()=>null;
  if(failure==='identity') adapters.verifyIntegrationIdentity=async()=>null;
  if(failure==='delegation') adapters.verifyIntegrationDelegation=async()=>null;
  if(['blocked','unknown','missing'].includes(failure)) adapters.gateConciergeExecution=async()=>(
   failure==='missing'?{}:{status:failure,reasonCode:'permission-revoked'});
  const service=createConciergeExecuteService({clock:()=>CLOCK,idFactory:()=>HANDOFF,adapters});
  const result=await service({envelope:{conciergeExecute:'shine-concierge/execute-v1',schemaVersion:'1.0.0',
   requestId:REQUEST,clientId:'shine.wellness',requestedAt:CLOCK,inputs:{'calendar.book':handoff()}},
   authContext:failure==='delegation'?{delegationToken:'revoked'}:{}});
  assert.notEqual(result.status,'completed',failure);
  assert.equal(downstream,0,failure);
  assert.equal(result.results,undefined,failure);
 }
});

test('recovery after transient failure honours revocation before checkpoint reuse',async()=>{
 const capture=[],stored=[{completed:true,stepId:'step-1',capabilityId:'calendar.book',result:{ok:true}}];
 const adapters=executeAdapters({capture});let revoked=false,reads=0,queues=0;
 adapters.gateConciergeExecution=async()=>revoked?{status:'blocked',reasonCode:'permission-revoked'}:{
  status:'allowed',plan:{purpose:WELLNESS_CONCIERGE_PURPOSE,steps:[
   {stepId:'step-1',capabilityId:'calendar.book',appId:'calendar'},
   {stepId:'step-2',capabilityId:'calendar.book',appId:'calendar'}]}};
 adapters.getConciergeResumeState=async()=>{reads++;return {steps:stored}};
 adapters.invokeCapability=async args=>{capture.push(args);return {status:'failed',reasonCode:'capability-adapter-health-unavailable'}};
 adapters.queueConciergeRetry=async()=>{queues++;return {ok:true}};
 const args={envelope:{conciergeExecute:'shine-concierge/execute-v1',schemaVersion:'1.0.0',
 requestId:REQUEST,clientId:'shine.wellness',requestedAt:CLOCK,inputs:{'calendar.book':handoff()}},authContext:{}};
 const run=()=>createConciergeExecuteService({clock:()=>CLOCK,idFactory:()=>HANDOFF,adapters})(args);
 await run();
 assert.equal(capture.length,1);assert.equal(capture[0].requestId,'step-2');
 assert.equal(queues,1);assert.equal(reads,1);
 revoked=true;
 const recovered=await run();
 assert.equal(recovered.status,'blocked');assert.equal(recovered.reasonCode,'permission-revoked');
 assert.equal(capture.length,1);assert.equal(reads,1);assert.equal(queues,1);
 assert.equal(recovered.results,undefined);
});
