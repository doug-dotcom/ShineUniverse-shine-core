import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createIntegrationDelegationRefreshService} from './integration-delegation-refresh-v1.mjs';

const clientId='shine.companion';
const rotation='11111111-1111-4111-8111-111111111111';
const session='22222222-2222-4222-8222-222222222222';
const refresh='33333333-3333-4333-8333-333333333333';
const event='44444444-4444-4444-8444-444444444444';
const oldRefresh='r'.repeat(128);
const hash=value=>createHash('sha256').update(value).digest('hex');

const envelope=()=>({
  integrationDelegationRefresh:'shine-foundation/integration-delegation-refresh-v2',
  schemaVersion:'2.0.0',
  requestId:rotation,
  clientId,
  newSessionId:session,
  newRefreshId:refresh,
  newDelegationTokenHash:'a'.repeat(64),
  newRefreshTokenHash:'b'.repeat(64)
});

test('v2 keeps old refresh secret out of the JSON envelope and rotates staged hashes',async()=>{
  let seen;
  const service=createIntegrationDelegationRefreshService({
    adapters:{
      verifyIntegrationClient:async()=>({clientId}),
      rotateIntegrationDelegation:async()=>{throw new Error('legacy path not expected')},
      rotateIntegrationDelegationV2:async input=>{
        seen=input;
        return {
          rotated:true,replayed:false,reasonCode:'refresh-credential-rotated-v2',
          requestId:'55555555-5555-4555-8555-555555555555',
          sessionId:session,refreshId:refresh,
          delegationExpiresAt:'2026-09-28T11:00:00.000Z',
          refreshExpiresAt:'2026-12-26T11:00:00.000Z',
          refreshGeneration:2
        };
      }
    },
    clock:()=> '2026-09-27T11:00:00.000Z',
    idFactory:()=>event
  });

  const result=await service({
    envelope:envelope(),
    authContext:{clientToken:'c'.repeat(64),refreshToken:oldRefresh}
  });

  assert.equal(result.status,'refreshed');
  assert.equal(result.requestId,rotation);
  assert.equal(result.sessionId,session);
  assert.equal(result.refreshId,refresh);
  assert.equal(result.replayed,false);
  assert.equal(seen.oldRefreshTokenHash,hash(oldRefresh));
  assert.notEqual(seen.oldRefreshTokenHash,oldRefresh);
  assert.equal(seen.newDelegationHash,'a'.repeat(64));
  assert.equal(seen.newRefreshTokenHash,'b'.repeat(64));
  assert.equal(JSON.stringify(envelope()).includes(oldRefresh),false);
  assert.equal(Object.hasOwn(result,'delegationToken'),false);
  assert.equal(Object.hasOwn(result,'refreshToken'),false);
});

test('v2 reports an exact committed retry without returning raw authority',async()=>{
  const service=createIntegrationDelegationRefreshService({
    adapters:{
      verifyIntegrationClient:async()=>({clientId}),
      rotateIntegrationDelegation:async()=>null,
      rotateIntegrationDelegationV2:async()=>({
        rotated:true,replayed:true,reasonCode:'refresh-request-replayed',
        requestId:'55555555-5555-4555-8555-555555555555',
        sessionId:session,refreshId:refresh,
        delegationExpiresAt:'2026-09-28T11:00:00.000Z',
        refreshExpiresAt:'2026-12-26T11:00:00.000Z',
        refreshGeneration:2
      })
    },
    clock:()=> '2026-09-27T11:00:00.000Z',
    idFactory:()=>event
  });

  const result=await service({
    envelope:envelope(),
    authContext:{clientToken:'c'.repeat(64),refreshToken:oldRefresh}
  });

  assert.equal(result.status,'refreshed');
  assert.equal(result.reasonCode,'refresh-request-replayed');
  assert.equal(result.replayed,true);
  assert.equal(Object.hasOwn(result,'delegationToken'),false);
  assert.equal(Object.hasOwn(result,'refreshToken'),false);
});

test('v2 requires the old refresh secret in authenticated header context',async()=>{
  let called=false;
  const service=createIntegrationDelegationRefreshService({
    adapters:{
      verifyIntegrationClient:async()=>{called=true;return {clientId}},
      rotateIntegrationDelegation:async()=>null,
      rotateIntegrationDelegationV2:async()=>null
    }
  });
  const result=await service({envelope:envelope(),authContext:{clientToken:'c'.repeat(64)}});
  assert.equal(result.status,'invalid');
  assert.equal(result.reasonCode,'invalid-delegation-refresh-request');
  assert.equal(called,false);
});

test('v1 remains accepted for backward compatibility',async()=>{
  let called=false;
  const service=createIntegrationDelegationRefreshService({
    adapters:{
      verifyIntegrationClient:async()=>({clientId}),
      rotateIntegrationDelegation:async input=>{
        called=true;
        return {
          rotated:true,requestId:'55555555-5555-4555-8555-555555555555',
          sessionId:session,delegationExpiresAt:'2026-09-28T11:00:00.000Z',
          refreshExpiresAt:'2026-12-26T11:00:00.000Z',refreshGeneration:2
        };
      },
      rotateIntegrationDelegationV2:async()=>null
    },
    clock:()=> '2026-09-27T11:00:00.000Z',
    idFactory:()=>event
  });
  const result=await service({
    envelope:{
      integrationDelegationRefresh:'shine-foundation/integration-delegation-refresh-v1',
      schemaVersion:'1.0.0',requestId:rotation,clientId,refreshToken:oldRefresh
    },
    authContext:{clientToken:'c'.repeat(64)}
  });
  assert.equal(result.status,'refreshed');
  assert.equal(called,true);
  assert.equal(typeof result.delegationToken,'string');
  assert.equal(typeof result.refreshToken,'string');
});
