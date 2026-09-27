import test from 'node:test';
import assert from 'node:assert/strict';
import {createRevocationAckService} from './revocation-ack-v1.mjs';

const requestId='11111111-1111-4111-8111-111111111111';
const deliveryId='22222222-2222-4222-8222-222222222222';
const ackId='33333333-3333-4333-8333-333333333333';
const appId='shine.ski';
const envelope={
  revocationAck:'shine-foundation/revocation-ack-v1',
  schemaVersion:'1.0.0',
  requestId,deliveryId,appId,sequenceNo:7,
  requestedAt:'2026-09-27T13:30:00Z'
};

const make=overrides=>{
  const writes=[];
  const adapters={
    verifyAppCaller:async()=>({appId}),
    acknowledgeAppRevocations:async input=>{
      writes.push(input);
      return {outcome:'advanced',reasonCode:'revocation-checkpoint-advanced',checkpointSequence:7};
    },
    ...overrides
  };
  return {
    writes,
    ack:createRevocationAckService({
      adapters,clock:()=> '2026-09-27T13:35:00Z',idFactory:()=>ackId
    })
  };
};

test('ack advances only the terminal sequence from a recorded delivery',async()=>{
  const {ack,writes}=make();
  const result=await ack({envelope,authContext:{appToken:'x'}});
  assert.equal(result.status,'acknowledged');
  assert.equal(result.checkpointSequence,7);
  assert.deepEqual(writes,[{
    ackId,requestId,deliveryId,appId,sequenceNo:7,occurredAt:'2026-09-27T13:35:00Z'
  }]);
});

test('already-acked is idempotent success',async()=>{
  const {ack}=make({acknowledgeAppRevocations:async()=>({
    outcome:'already-acked',reasonCode:'revocation-checkpoint-already-current',checkpointSequence:7
  })});
  const result=await ack({envelope,authContext:{}});
  assert.equal(result.status,'already-acknowledged');
  assert.equal(result.checkpointSequence,7);
});

test('stale ack is rejected before any write',async()=>{
  const {ack,writes}=make();
  const result=await ack({envelope:{...envelope,requestedAt:'2026-09-27T12:00:00Z'},authContext:{}});
  assert.equal(result.reasonCode,'stale-revocation-ack-request');
  assert.equal(writes.length,0);
});

test('app caller mismatch cannot advance another app checkpoint',async()=>{
  const {ack,writes}=make({verifyAppCaller:async()=>({appId:'shine.dive'})});
  const result=await ack({envelope,authContext:{}});
  assert.equal(result.reasonCode,'app-caller-mismatch');
  assert.equal(writes.length,0);
});
