import test from 'node:test';
import assert from 'node:assert/strict';
import {
  canonicalJson,
  createAtlasFeedPublishService,
  sha256CanonicalJson
} from './publish-v1.mjs';

const now='2026-09-28T10:00:00.000Z';
const requestId='11111111-1111-4111-8111-111111111111';
const eventId='22222222-2222-4222-8222-222222222222';
const credentialId='33333333-3333-4333-8333-333333333333';
const receiptId='44444444-4444-4444-8444-444444444444';

const event=()=>({
  atlasFeedEvent:'shine-universe/atlas-feed-event',
  schemaVersion:'1.0.0',
  eventId,
  topic:'dive.site.condition',
  source:{
    appId:'shine.dive',
    capabilityId:'dive.site.condition.publish',
    releaseRef:'git:abc123'
  },
  subject:{kind:'dive_site',key:'site:julian-rocks'},
  timing:{
    occurredAt:'2026-09-28T09:59:10.000Z',
    publishedAt:'2026-09-28T09:59:20.000Z',
    freshForSeconds:3600
  },
  audience:{mode:'owner',dataClass:'general'},
  provenance:{
    mode:'first_party',
    sourceObservedAt:'2026-09-28T09:59:00.000Z',
    evidenceRefs:[]
  },
  payloadContract:{schemaRef:'dive.site.condition',schemaVersion:'1.0.0'},
  payload:{state:'good',depth:18}
});

const envelope=()=>({
  atlasFeedPublishRequest:'shine-universe/atlas-feed-publish-v1',
  schemaVersion:'1.0.0',
  requestId,
  requestedAt:'2026-09-28T09:59:30.000Z',
  event:event()
});

const admitted=async({envelope})=>({
  atlasFeedPublisherAdmissionResponse:'shine-universe/atlas-feed-publisher-admission-response-v1',
  schemaVersion:'1.0.0',
  requestId:envelope.requestId,
  status:'admitted',
  reasonCode:'publisher-admission-clear',
  admission:{
    eventId,
    appId:'shine.dive',
    credentialId,
    capabilityId:'dive.site.condition.publish',
    capabilityVersion:'1.0.0',
    capabilityState:'live',
    audienceMode:'owner',
    dataClass:'general',
    ownerShineId:null,
    grantId:null
  }
});

function service({publisherAdmission=admitted,persist}={}){
  const calls=[];
  const adapters={
    persistAtlasFeedEvent:async args=>{
      calls.push(args);
      if(persist) return persist(args);
      return {
        outcome:'persisted',
        reasonCode:'atlas-feed-event-persisted',
        receipt:args.receipt,
        receiptSha256:args.receiptSha256
      };
    }
  };
  return {
    publish:createAtlasFeedPublishService({
      publisherAdmission,
      adapters,
      clock:()=>now,
      idFactory:()=>receiptId
    }),
    calls
  };
}

test('canonical JSON ignores object key insertion order',async()=>{
  const a={b:2,a:{z:3,y:1}};
  const b={a:{y:1,z:3},b:2};
  assert.equal(canonicalJson(a),canonicalJson(b));
  assert.equal(await sha256CanonicalJson(a),await sha256CanonicalJson(b));
});

test('persists only after an admitted Layer-2 decision',async()=>{
  const {publish,calls}=service();
  const result=await publish({envelope:envelope(),authContext:{appToken:'good'}});
  assert.equal(result.status,'persisted');
  assert.equal(calls.length,1);
  assert.equal(calls[0].admission.credentialId,credentialId);
  assert.match(calls[0].eventSha256,/^[a-f0-9]{64}$/);
  assert.match(calls[0].payloadSha256,/^[a-f0-9]{64}$/);
  assert.match(result.receiptSha256,/^[a-f0-9]{64}$/);
  assert.equal(result.receipt.eventId,eventId);
});

test('denied admission cannot touch persistence',async()=>{
  const {publish,calls}=service({
    publisherAdmission:async()=>({status:'denied',reasonCode:'publisher-capability-not-live'})
  });
  const result=await publish({envelope:envelope(),authContext:{appToken:'good'}});
  assert.equal(result.status,'denied');
  assert.equal(result.reasonCode,'publisher-capability-not-live');
  assert.equal(calls.length,0);
});

test('invalid Layer-2 event errors pass through without storage',async()=>{
  const {publish,calls}=service({
    publisherAdmission:async()=>({
      status:'invalid',
      reasonCode:'invalid-atlas-feed-event',
      validationErrors:['event.payload.token is forbidden']
    })
  });
  const result=await publish({envelope:envelope(),authContext:{appToken:'good'}});
  assert.equal(result.status,'invalid');
  assert.deepEqual(result.validationErrors,['event.payload.token is forbidden']);
  assert.equal(calls.length,0);
});

test('returns the stable stored receipt on idempotent replay',async()=>{
  const stored={
    atlasFeedPersistenceReceipt:'shine-universe/atlas-feed-persistence-receipt-v1',
    schemaVersion:'1.0.0',
    receiptId:'55555555-5555-4555-8555-555555555555',
    requestId,
    eventId,
    publisherAppId:'shine.dive',
    capabilityId:'dive.site.condition.publish',
    persistedAt:'2026-09-28T09:58:00.000Z',
    eventSha256:'a'.repeat(64),
    payloadSha256:'b'.repeat(64)
  };
  const {publish}=service({
    persist:async()=>({
      outcome:'already-persisted',
      reasonCode:'atlas-feed-event-already-persisted',
      receipt:stored,
      receiptSha256:'c'.repeat(64)
    })
  });
  const result=await publish({envelope:envelope(),authContext:{appToken:'good'}});
  assert.equal(result.status,'already-persisted');
  assert.equal(result.receipt.receiptId,stored.receiptId);
  assert.equal(result.receipt.persistedAt,stored.persistedAt);
});

test('event id or request replay conflicts map to HTTP-conflict semantics',async()=>{
  const {publish}=service({
    persist:async()=>({
      outcome:'conflict',
      reasonCode:'atlas-feed-event-id-conflict'
    })
  });
  const result=await publish({envelope:envelope(),authContext:{appToken:'good'}});
  assert.equal(result.status,'conflict');
  assert.equal(result.reasonCode,'atlas-feed-event-id-conflict');
});

test('an admission snapshot that does not match the exact event fails closed',async()=>{
  const {publish,calls}=service({
    publisherAdmission:async()=>({
      status:'admitted',
      admission:{
        eventId,
        appId:'shine.travel',
        credentialId,
        capabilityId:'dive.site.condition.publish',
        capabilityVersion:'1.0.0',
        capabilityState:'live'
      }
    })
  });
  const result=await publish({envelope:envelope(),authContext:{appToken:'good'}});
  assert.equal(result.status,'unavailable');
  assert.equal(result.reasonCode,'publisher-admission-invalid');
  assert.equal(calls.length,0);
});
