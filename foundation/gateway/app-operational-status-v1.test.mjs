import test from 'node:test';
import assert from 'node:assert/strict';
import {createAppOperationalStatusService} from './app-operational-status-v1.mjs';

const appId='shine.ski';

test('operational status returns the database-derived status after app proof',async()=>{
  const service=createAppOperationalStatusService({adapters:{
    verifyAppCaller:async()=>({appId}),
    getAppOperationalStatus:async()=>({
      appId,
      connection:{state:'grant-ready'},
      revocations:{pendingCount:1,freshnessState:'pending',staleAction:'observe'},
      operationalState:'revocation-pending',
      operationalHealth:'attention'
    })
  }});
  const result=await service({appId,authContext:{appToken:'x'}});
  assert.equal(result.status,'ok');
  assert.equal(result.operationalStatus.operationalState,'revocation-pending');
  assert.equal(result.operationalStatus.operationalHealth,'attention');
});

test('caller mismatch cannot inspect another app operational state',async()=>{
  const service=createAppOperationalStatusService({adapters:{
    verifyAppCaller:async()=>({appId:'shine.dive'}),
    getAppOperationalStatus:async()=>{throw new Error('must not run')}
  }});
  const result=await service({appId,authContext:{}});
  assert.equal(result.status,'denied');
  assert.equal(result.reasonCode,'app-caller-mismatch');
});

test('invalid app id is rejected before dependencies',async()=>{
  let called=false;
  const service=createAppOperationalStatusService({adapters:{
    verifyAppCaller:async()=>{called=true;return {appId}},
    getAppOperationalStatus:async()=>null
  }});
  const result=await service({appId:'bad app',authContext:{}});
  assert.equal(result.status,'invalid');
  assert.equal(called,false);
});
