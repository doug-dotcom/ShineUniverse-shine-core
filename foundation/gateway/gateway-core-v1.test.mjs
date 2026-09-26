import test from 'node:test';
import assert from 'node:assert/strict';
import {createFoundationGateway} from './gateway-core-v1.mjs';

const shineId='11111111-1111-4111-8111-111111111111';
const resourceId='22222222-2222-4222-8222-222222222222';
const grantId='33333333-3333-4333-8333-333333333333';

const envelope={
  gatewayRequest:'shine-foundation/gateway-request-v1',
  schemaVersion:'1.0.0',
  operation:'access.evaluate',
  traceId:'55555555-5555-4555-8555-555555555555',
  permission:{
    requestId:'44444444-4444-4444-8444-444444444444',
    appId:'shine.travel',shineId,scope:'vault.location.read',
    purpose:'travel.home-airport',resourceId,
    resourceCategory:'profile.location',
    requestedAt:'2026-09-26T06:00:00Z'
  }
};

const manifest={appId:'shine.travel',foundation:{requestedScopes:[{
  scope:'vault.location.read',purpose:'travel.home-airport',resourceCategory:'profile.location'
}]}};

const resource={resourceId,ownerShineId:shineId,category:'profile.location'};
const grant={grantId,ownerShineId:shineId,appId:'shine.travel',
  scope:'vault.location.read',purpose:'travel.home-airport',
  resourceSelector:{resourceId},status:'active',
  issuedAt:'2026-09-01T00:00:00Z',expiresAt:'2026-12-01T00:00:00Z'};

const makeAdapters=overrides=>{
  const audit=[];
  return {audit,adapters:{
    verifyAppCaller:async()=>({appId:'shine.travel',credentialId:'cred-1'}),
    verifyIdentity:async()=>({shineId,sessionId:'session-1'}),
    getAppManifest:async()=>manifest,
    getVaultResource:async()=>resource,
    getEffectiveGrants:async()=>[grant],
    evaluateDefence:async()=>({decision:'allow',evidenceRef:'defence://ok'}),
    writeAuditEvent:async event=>{audit.push(event)},
    ...overrides
  }};
};

const create=(overrides={})=>{
  const {audit,adapters}=makeAdapters(overrides);
  return {audit,gateway:createFoundationGateway({adapters,clock:()=> '2026-09-26T06:10:00Z'})};
};

test('allows only when app and user are both verified',async()=>{
  const {gateway,audit}=create();
  const result=await gateway({envelope,authContext:{jwt:'user',appToken:'app'}});
  assert.equal(result.status,'allowed');
  assert.equal(audit.length,1);
});

test('unverified app caller is denied and audited before user lookup',async()=>{
  let identityCalls=0;
  const {gateway,audit}=create({
    verifyAppCaller:async()=>null,
    verifyIdentity:async()=>{identityCalls++;return {shineId}}
  });
  const result=await gateway({envelope,authContext:{}});
  assert.equal(result.reasonCode,'app-caller-unverified');
  assert.equal(identityCalls,0);
  assert.equal(audit[0].decision,'deny');
});

test('calling app cannot impersonate another app',async()=>{
  const {gateway}=create({verifyAppCaller:async()=>({appId:'shine.dive'})});
  const result=await gateway({envelope,authContext:{}});
  assert.equal(result.reasonCode,'app-caller-mismatch');
});

test('missing grant is denied and audited',async()=>{
  const {gateway,audit}=create({getEffectiveGrants:async()=>[]});
  const result=await gateway({envelope,authContext:{}});
  assert.equal(result.reasonCode,'no-matching-grant');
  assert.equal(audit.length,1);
});

test('identity mismatch fails closed',async()=>{
  const {gateway}=create({verifyIdentity:async()=>({shineId:'66666666-6666-4666-8666-666666666666'})});
  const result=await gateway({envelope,authContext:{}});
  assert.equal(result.reasonCode,'identity-mismatch');
});

test('Defence can veto otherwise valid access',async()=>{
  const {gateway,audit}=create({evaluateDefence:async()=>({decision:'deny',evidenceRef:'defence://veto'})});
  const result=await gateway({envelope,authContext:{}});
  assert.equal(result.reasonCode,'defence-denied');
  assert.equal(audit[0].defenceEvidenceRef,'defence://veto');
});

test('invalid envelope is rejected before adapters are called',async()=>{
  let called=false;
  const {gateway}=create({verifyAppCaller:async()=>{called=true;return {appId:'shine.travel'}}});
  const result=await gateway({envelope:{...envelope,operation:'vault.dump'},authContext:{}});
  assert.equal(result.status,'invalid');
  assert.equal(called,false);
});

test('dependency failure becomes unavailable',async()=>{
  const {gateway,audit}=create({getAppManifest:async()=>{throw new Error('db down')}});
  const result=await gateway({envelope,authContext:{}});
  assert.equal(result.status,'unavailable');
  assert.equal(audit.length,0);
});

test('allow is suppressed if audit cannot persist',async()=>{
  const {gateway}=create({writeAuditEvent:async()=>{throw new Error('audit down')}});
  const result=await gateway({envelope,authContext:{}});
  assert.equal(result.reasonCode,'audit-write-failed');
  assert.equal(Object.hasOwn(result,'decision'),false);
});

test('external response exposes neither grant nor app credential ids',async()=>{
  const {gateway}=create();
  const json=JSON.stringify(await gateway({envelope,authContext:{}}));
  assert.equal(json.includes(grantId),false);
  assert.equal(json.includes('cred-1'),false);
});

test('Foundation unavailability does not disable standalone app',async()=>{
  const {gateway}=create({getVaultResource:async()=>{throw new Error('offline')}});
  const result=await gateway({envelope,authContext:{}});
  assert.equal(Object.hasOwn(result,'disableApp'),false);
});

test('identity mismatch short-circuits before Core or Vault',async()=>{
  let manifestCalls=0,vaultCalls=0;
  const {gateway}=create({
    verifyIdentity:async()=>({shineId:'99999999-9999-4999-8999-999999999999'}),
    getAppManifest:async()=>{manifestCalls++;return manifest},
    getVaultResource:async()=>{vaultCalls++;return resource}
  });
  const result=await gateway({envelope,authContext:{}});
  assert.equal(result.reasonCode,'identity-mismatch');
  assert.equal(manifestCalls,0);
  assert.equal(vaultCalls,0);
});

test('undeclared scope short-circuits before Vault and grants',async()=>{
  let vaultCalls=0,grantCalls=0;
  const changed={...envelope,permission:{...envelope.permission,scope:'vault.location.write'}};
  const {gateway}=create({
    getVaultResource:async()=>{vaultCalls++;return resource},
    getEffectiveGrants:async()=>{grantCalls++;return [grant]}
  });
  const result=await gateway({envelope:changed,authContext:{}});
  assert.equal(result.reasonCode,'scope-not-declared');
  assert.equal(vaultCalls,0);
  assert.equal(grantCalls,0);
});
