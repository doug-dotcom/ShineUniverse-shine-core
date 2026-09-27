import test from 'node:test';
import assert from 'node:assert/strict';
import {createRevocationHealthService} from './revocation-health-v1.mjs';

const appId='shine.ski';

test('health exposes pending age and the configured stale action without mutating state',async()=>{
  const health=createRevocationHealthService({adapters:{
    verifyAppCaller:async()=>({appId}),
    getAppRevocationStatus:async()=>({lastAckAt:'2026-09-27T13:00:00Z'}),
    getAppRevocationHealth:async()=>({
      checkpointSequence:4,latestSequence:6,pendingCount:2,
      oldestPendingAt:'2026-09-27T13:20:00Z',
      pendingAgeSeconds:600,maxPendingAgeSeconds:900,
      freshnessState:'pending',staleAction:'observe',
      recommendedAction:'consume-revocations'
    })
  }});
  const result=await health({appId,authContext:{appToken:'x'}});
  assert.equal(result.status,'ok');
  assert.equal(result.pendingCount,2);
  assert.equal(result.freshnessState,'pending');
  assert.equal(result.recommendedAction,'consume-revocations');
  assert.equal(result.lastAckAt,'2026-09-27T13:00:00Z');
});

test('health requires app authentication',async()=>{
  const health=createRevocationHealthService({adapters:{
    verifyAppCaller:async()=>null,
    getAppRevocationStatus:async()=>null,
    getAppRevocationHealth:async()=>null
  }});
  const result=await health({appId,authContext:{}});
  assert.equal(result.status,'denied');
  assert.equal(result.reasonCode,'app-caller-unverified');
});
