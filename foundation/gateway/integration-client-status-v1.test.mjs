import test from 'node:test';
import assert from 'node:assert/strict';
import {createIntegrationClientStatusService} from './integration-client-status-v1.mjs';

test('requires the integration client verification adapter',()=>{
  assert.throws(
    ()=>createIntegrationClientStatusService({adapters:{}}),
    /verifyIntegrationClient/
  );
});

test('authenticated registered client receives identity-only status',async()=>{
  let seen;
  const service=createIntegrationClientStatusService({
    adapters:{
      verifyIntegrationClient:async args=>{
        seen=args;
        return {
          clientId:'shine.companion',
          credentialId:'11111111-1111-4111-8111-111111111111',
          clientKind:'first-party-companion'
        };
      }
    }
  });

  const authContext={clientToken:'secret'};
  const result=await service({clientId:'shine.companion',authContext});

  assert.deepEqual(seen,{authContext,claimedClientId:'shine.companion'});
  assert.deepEqual(result,{
    integrationClientStatusResponse:'shine-foundation/integration-client-status-response-v1',
    schemaVersion:'1.0.0',
    integrationProtocol:'shine-foundation/open-integration-v1',
    status:'ok',
    clientId:'shine.companion',
    clientKind:'first-party-companion',
    authenticated:true,
    supportedOperations:['capabilities.discover']
  });
});

test('invalid client id is rejected before credential verification',async()=>{
  let calls=0;
  const service=createIntegrationClientStatusService({
    adapters:{verifyIntegrationClient:async()=>{calls++;return null}}
  });
  const result=await service({clientId:'BAD CLIENT',authContext:{clientToken:'secret'}});
  assert.equal(result.status,'invalid');
  assert.equal(result.reasonCode,'invalid-client-id');
  assert.equal(calls,0);
});

test('unknown or inactive client credential is denied',async()=>{
  const service=createIntegrationClientStatusService({
    adapters:{verifyIntegrationClient:async()=>null}
  });
  const result=await service({
    clientId:'shine.companion',
    authContext:{clientToken:'wrong'}
  });
  assert.equal(result.status,'denied');
  assert.equal(result.reasonCode,'integration-client-unverified');
});

test('credential for another client is denied as a mismatch',async()=>{
  const service=createIntegrationClientStatusService({
    adapters:{
      verifyIntegrationClient:async()=>({
        clientId:'external.agent',
        credentialId:'22222222-2222-4222-8222-222222222222',
        clientKind:'developer-agent'
      })
    }
  });
  const result=await service({
    clientId:'shine.companion',
    authContext:{clientToken:'secret'}
  });
  assert.equal(result.status,'denied');
  assert.equal(result.reasonCode,'integration-client-mismatch');
});

test('verification dependency failures do not leak internals',async()=>{
  const service=createIntegrationClientStatusService({
    adapters:{verifyIntegrationClient:async()=>{throw new Error('database detail')}}
  });
  const result=await service({
    clientId:'shine.companion',
    authContext:{clientToken:'secret'}
  });
  assert.equal(result.status,'unavailable');
  assert.equal(result.reasonCode,'foundation-dependency-unavailable');
});
