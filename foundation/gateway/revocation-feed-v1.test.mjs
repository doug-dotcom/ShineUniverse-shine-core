import test from 'node:test';
import assert from 'node:assert/strict';
import {createRevocationFeedService} from './revocation-feed-v1.mjs';

const appId='shine.ski';
const deliveryId='11111111-1111-4111-8111-111111111111';
const now='2026-09-27T13:30:00Z';

const make=overrides=>{
  const deliveries=[];
  const adapters={
    verifyAppCaller:async()=>({appId}),
    getAppRevocationStatus:async()=>({
      checkpointSequence:2,latestSequence:5,pendingCount:3,
      lastAckAt:'2026-09-27T13:00:00Z',oldestPendingAt:'2026-09-27T13:20:00Z'
    }),
    getAppRevocationHealth:async()=>({
      freshnessState:'pending',pendingAgeSeconds:600,maxPendingAgeSeconds:900,
      staleAction:'observe',recommendedAction:'consume-revocations'
    }),
    listAppRevocations:async()=>[
      {sequenceNo:3,event:{event:'x3'},createdAt:'2026-09-27T13:20:00Z'},
      {sequenceNo:4,event:{event:'x4'},createdAt:'2026-09-27T13:21:00Z'},
      {sequenceNo:5,event:{event:'x5'},createdAt:'2026-09-27T13:22:00Z'}
    ],
    recordAppRevocationDelivery:async input=>{deliveries.push(input);return {deliveryId,terminalSequence:4,eventCount:2}},
    ...overrides
  };
  return {
    deliveries,
    feed:createRevocationFeedService({adapters,idFactory:()=>deliveryId,clock:()=>now})
  };
};

test('feed returns a bounded app-scoped batch and records exactly what was served',async()=>{
  const {feed,deliveries}=make();
  const result=await feed({appId,afterSequence:2,limit:2,authContext:{appToken:'x'}});
  assert.equal(result.status,'ok');
  assert.equal(result.hasMore,true);
  assert.equal(result.nextCursor,4);
  assert.equal(result.deliveryId,deliveryId);
  assert.deepEqual(result.events.map(x=>x.sequenceNo),[3,4]);
  assert.equal(result.freshness.state,'pending');
  assert.deepEqual(deliveries,[{
    deliveryId,appId,afterSequence:2,sequenceNos:[3,4],occurredAt:now
  }]);
});

test('empty feed does not mint a delivery receipt',async()=>{
  const {feed,deliveries}=make({listAppRevocations:async()=>[]});
  const result=await feed({appId,afterSequence:2,limit:10,authContext:{}});
  assert.equal(result.status,'ok');
  assert.equal(result.deliveryId,null);
  assert.equal(result.nextCursor,2);
  assert.equal(deliveries.length,0);
});

test('consumer cannot skip ahead of its acknowledged checkpoint',async()=>{
  const {feed}=make();
  const result=await feed({appId,afterSequence:3,limit:2,authContext:{}});
  assert.equal(result.status,'denied');
  assert.equal(result.reasonCode,'revocation-feed-ahead-of-checkpoint');
});

test('feed validates cursor and limit before authentication',async()=>{
  let called=false;
  const {feed}=make({verifyAppCaller:async()=>{called=true;return {appId}}});
  const result=await feed({appId,afterSequence:-1,limit:101,authContext:{}});
  assert.equal(result.status,'invalid');
  assert.equal(called,false);
});

test('delivery receipt failure fails closed',async()=>{
  const {feed}=make({recordAppRevocationDelivery:async()=>{throw new Error('db')}});
  const result=await feed({appId,afterSequence:2,limit:2,authContext:{}});
  assert.equal(result.status,'unavailable');
  assert.equal(result.reasonCode,'revocation-delivery-receipt-write-failed');
});
