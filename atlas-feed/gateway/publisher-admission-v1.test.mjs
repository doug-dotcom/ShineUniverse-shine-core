import test from 'node:test';
import assert from 'node:assert/strict';
import {createAtlasFeedPublisherAdmissionService} from './publisher-admission-v1.mjs';

const owner='11111111-1111-4111-8111-111111111111';
const grant='22222222-2222-4222-8222-222222222222';
const resource='33333333-3333-4333-8333-333333333333';
const now='2026-09-28T09:20:00.000Z';

const baseEvent=()=>({
  atlasFeedEvent:'shine-universe/atlas-feed-event',
  schemaVersion:'1.0.0',
  eventId:'44444444-4444-4444-8444-444444444444',
  topic:'dive.site.condition',
  source:{
    appId:'shine.dive',
    capabilityId:'dive.site.condition.publish',
    releaseRef:'git:abc123'
  },
  subject:{kind:'dive_site',key:'site:julian-rocks'},
  timing:{
    occurredAt:'2026-09-28T09:19:30.000Z',
    publishedAt:'2026-09-28T09:19:40.000Z',
    freshForSeconds:3600
  },
  audience:{mode:'owner',dataClass:'general'},
  provenance:{
    mode:'first_party',
    sourceObservedAt:'2026-09-28T09:19:20.000Z',
    evidenceRefs:[]
  },
  payloadContract:{schemaRef:'dive.site.condition',schemaVersion:'1.0.0'},
  payload:{state:'good'}
});

const request=(event=baseEvent(),permissionContext)=>({
  atlasFeedPublishAdmissionRequest:'shine-universe/atlas-feed-publisher-admission-v1',
  schemaVersion:'1.0.0',
  requestId:'55555555-5555-4555-8555-555555555555',
  requestedAt:'2026-09-28T09:19:50.000Z',
  event,
  ...(permissionContext?{permissionContext}:{})
});

function service(overrides={}){
  const adapters={
    verifyAppCaller:async()=>({appId:'shine.dive',credentialId:'66666666-6666-4666-8666-666666666666'}),
    verifyIdentity:async()=>({shineId:owner}),
    getAtlasFeedPublisherCapability:async()=>({
      capabilityId:'dive.site.condition.publish',
      capabilityVersion:'1.0.0',
      appId:'shine.dive',
      invocationState:'live'
    }),
    getAtlasFeedGrantContext:async()=>({
      grantId:grant,
      ownerShineId:owner,
      appId:'shine.companion',
      scope:'atlas.dive.read',
      purpose:'companion.dive-context',
      resourceId:resource,
      resourceCategory:null,
      effectiveStatus:'active'
    }),
    ...overrides
  };
  return createAtlasFeedPublisherAdmissionService({adapters,clock:()=>now});
}

test('admits a general owner signal with app auth and a live publisher capability',async()=>{
  const result=await service()({envelope:request(),authContext:{appToken:'good'}});
  assert.equal(result.status,'admitted');
  assert.equal(result.admission.appId,'shine.dive');
  assert.equal(result.admission.capabilityState,'live');
});

test('fails closed when the app credential does not verify',async()=>{
  const result=await service({verifyAppCaller:async()=>null})({
    envelope:request(),authContext:{appToken:'bad'}
  });
  assert.equal(result.status,'denied');
  assert.equal(result.reasonCode,'publishing-app-unverified');
});

test('requires the source capability to be live',async()=>{
  const result=await service({
    getAtlasFeedPublisherCapability:async()=>({
      capabilityId:'dive.site.condition.publish',
      appId:'shine.dive',
      invocationState:'adapter-ready'
    })
  })({envelope:request(),authContext:{appToken:'good'}});
  assert.equal(result.status,'denied');
  assert.equal(result.reasonCode,'publisher-capability-not-live');
});

test('private owner publication requires a verified matching Shine owner',async()=>{
  const event=baseEvent();
  event.audience={mode:'owner',dataClass:'personal'};
  const result=await service()({
    envelope:request(event,{ownerShineId:owner}),
    authContext:{appToken:'good',jwt:'user'}
  });
  assert.equal(result.status,'admitted');
  assert.equal(result.admission.ownerShineId,owner);
});

test('private owner publication denies an owner identity mismatch',async()=>{
  const event=baseEvent();
  event.audience={mode:'owner',dataClass:'sensitive'};
  const result=await service({
    verifyIdentity:async()=>({shineId:'77777777-7777-4777-8777-777777777777'})
  })({
    envelope:request(event,{ownerShineId:owner}),
    authContext:{appToken:'good',jwt:'user'}
  });
  assert.equal(result.status,'denied');
  assert.equal(result.reasonCode,'owner-identity-mismatch');
});

test('private data cannot use the broad internal audience',async()=>{
  const event=baseEvent();
  event.audience={mode:'internal',dataClass:'personal'};
  const result=await service()({
    envelope:request(event,{ownerShineId:owner}),
    authContext:{appToken:'good',jwt:'user'}
  });
  assert.equal(result.status,'denied');
  assert.equal(result.reasonCode,'private-internal-audience-not-supported');
});

test('grant audience requires an active exact Foundation grant context',async()=>{
  const event=baseEvent();
  event.audience={mode:'grant',dataClass:'personal',grantId:grant};
  const permissionContext={
    ownerShineId:owner,
    requiredScope:'atlas.dive.read',
    purpose:'companion.dive-context',
    resourceId:resource
  };
  const result=await service()({
    envelope:request(event,permissionContext),
    authContext:{appToken:'good',jwt:'user'}
  });
  assert.equal(result.status,'admitted');
  assert.equal(result.admission.grantId,grant);
});

test('revoked or expired grant audience is denied',async()=>{
  const event=baseEvent();
  event.audience={mode:'grant',dataClass:'general',grantId:grant};
  const result=await service({
    getAtlasFeedGrantContext:async()=>({grantId:grant,effectiveStatus:'revoked'})
  })({
    envelope:request(event,{
      requiredScope:'atlas.dive.read',
      purpose:'companion.dive-context',
      resourceId:resource
    }),
    authContext:{appToken:'good'}
  });
  assert.equal(result.status,'denied');
  assert.equal(result.reasonCode,'grant-not-active');
});

test('grant scope mismatch is denied',async()=>{
  const event=baseEvent();
  event.audience={mode:'grant',dataClass:'general',grantId:grant};
  const result=await service()({
    envelope:request(event,{
      requiredScope:'atlas.travel.read',
      purpose:'companion.dive-context',
      resourceId:resource
    }),
    authContext:{appToken:'good'}
  });
  assert.equal(result.status,'denied');
  assert.equal(result.reasonCode,'grant-scope-purpose-mismatch');
});

test('Layer-1 event validation runs before admission',async()=>{
  const event=baseEvent();
  event.payload={token:'must-not-enter'};
  const result=await service()({envelope:request(event),authContext:{appToken:'good'}});
  assert.equal(result.status,'invalid');
  assert.equal(result.reasonCode,'invalid-atlas-feed-event');
  assert.match(result.validationErrors.join('\n'),/credential-bearing/);
});

test('stale admission requests are rejected',async()=>{
  const envelope=request();
  envelope.requestedAt='2026-09-28T08:00:00.000Z';
  const result=await service()({envelope,authContext:{appToken:'good'}});
  assert.equal(result.status,'invalid');
  assert.equal(result.reasonCode,'invalid-publisher-admission-request');
});
