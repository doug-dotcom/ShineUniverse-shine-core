import test from 'node:test';
import assert from 'node:assert/strict';
import {createCapabilityDiscoveryService} from './capability-discovery-v1.mjs';

test('requires the discovery adapter',()=>{
  assert.throws(()=>createCapabilityDiscoveryService({adapters:{}}),/listDiscoverableCapabilities/);
});

test('returns companion-agnostic metadata without authorising execution',async()=>{
  let seen;
  const service=createCapabilityDiscoveryService({
    adapters:{
      listDiscoverableCapabilities:async args=>{
        seen=args;
        return [{
          capabilityId:'travel.plan_trip',
          appId:'shine.travel',
          invocationState:'declared',
          invocable:false
        }];
      }
    }
  });

  const result=await service();
  assert.deepEqual(seen,{appId:null});
  assert.equal(result.status,'ok');
  assert.equal(result.integrationProtocol,'shine-foundation/open-integration-v1');
  assert.equal(result.companionAgnostic,true);
  assert.equal(result.executionRequiresAuthorization,true);
  assert.equal(result.capabilities[0].invocable,false);
});

test('passes a valid app filter to the catalogue',async()=>{
  const service=createCapabilityDiscoveryService({
    adapters:{listDiscoverableCapabilities:async({appId})=>[{appId}]}
  });
  const result=await service({appId:'shine.ski'});
  assert.equal(result.status,'ok');
  assert.equal(result.appId,'shine.ski');
  assert.deepEqual(result.capabilities,[{appId:'shine.ski'}]);
});

test('rejects malformed app ids before querying the catalogue',async()=>{
  let calls=0;
  const service=createCapabilityDiscoveryService({
    adapters:{listDiscoverableCapabilities:async()=>{calls++;return []}}
  });
  const result=await service({appId:'SHINE.TRAVEL'});
  assert.equal(result.status,'invalid');
  assert.equal(result.reasonCode,'invalid-app-id');
  assert.equal(calls,0);
});

test('maps catalogue failures to unavailable without leaking internals',async()=>{
  const service=createCapabilityDiscoveryService({
    adapters:{listDiscoverableCapabilities:async()=>{throw new Error('database detail')}}
  });
  const result=await service({appId:'shine.travel'});
  assert.deepEqual(result,{
    capabilityDiscoveryResponse:'shine-foundation/capability-discovery-response-v1',
    schemaVersion:'1.0.0',
    integrationProtocol:'shine-foundation/open-integration-v1',
    status:'unavailable',
    companionAgnostic:true,
    executionRequiresAuthorization:true,
    reasonCode:'capability-catalogue-unavailable'
  });
});
