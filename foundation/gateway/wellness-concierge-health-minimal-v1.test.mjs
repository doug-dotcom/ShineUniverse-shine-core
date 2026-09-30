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
