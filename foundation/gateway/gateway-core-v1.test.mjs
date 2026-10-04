import test from 'node:test';
import assert from 'node:assert/strict';
import {createFoundationGateway} from './gateway-core-v1.mjs';

const shineId='11111111-1111-4111-8111-111111111111';
const resourceId='22222222-2222-4222-8222-222222222222';
const grantId='33333333-3333-4333-8333-333333333333';

const v1={
  gatewayRequest:'shine-foundation/gateway-request-v1',
  schemaVersion:'1.0.0',
  operation:'access.evaluate',
  traceId:'55555555-5555-4555-8555-555555555555',
  permission:{
    requestId:'44444444-4444-4444-8444-444444444444',
    appId:'shine.travel',shineId,scope:'vault.foundation.pilot.read',
    purpose:'travel.foundation-pilot',resourceId,
    resourceCategory:'foundation.pilot',
    requestedAt:'2026-09-26T08:30:00Z'
  }
};

const v2={
  ...v1,
  gatewayRequest:'shine-foundation/gateway-request-v2',
  schemaVersion:'2.0.0',
  traceId:'66666666-6666-4666-8666-666666666666',
  permission:{
    requestId:'77777777-7777-4777-8777-777777777777',
    appId:'shine.travel',scope:'vault.foundation.pilot.read',
    purpose:'travel.foundation-pilot',
    resourceCategory:'foundation.pilot',
    requestedAt:'2026-09-26T08:30:00Z'
  }
};

const manifest={appId:'shine.travel',foundation:{requestedScopes:[{
  scope:'vault.foundation.pilot.read',
  purpose:'travel.foundation-pilot',
  resourceCategory:'foundation.pilot'
}]}};

const resource={resourceId,ownerShineId:shineId,category:'foundation.pilot'};
const grant={grantId,ownerShineId:shineId,appId:'shine.travel',
  scope:'vault.foundation.pilot.read',purpose:'travel.foundation-pilot',
  resourceSelector:{resourceCategory:'foundation.pilot'},status:'active',
  issuedAt:'2026-09-01T00:00:00Z',expiresAt:'2026-12-01T00:00:00Z'};

const makeAdapters=overrides=>{
  const audit=[];
  return {audit,adapters:{
    verifyAppCaller:async()=>({appId:'shine.travel',credentialId:'cred-1'}),
    verifyIdentity:async()=>({shineId,sessionId:'session-1'}),
    getAppManifest:async()=>manifest,
    getVaultResource:async()=>resource,
    getEffectiveGrants:async()=>[grant],
    evaluateDependencyAdmission:async()=>({
      serviceId:'foundation.gateway',
      environment:'production',
      operation:'access.evaluate',
      impactScope:'protected-operations',
      admissionState:'admit',
      reasonCode:'dependency-admission-clear',
      ownState:'operational',
      effectiveState:'operational',
      safeMode:'normal',
      bindingEvidenceRef:'foundation:admission-binding:gateway:access-evaluate:v1',
      dependencyEvidence:[]
    }),
    evaluateDefence:async()=>({decision:'allow',evidenceRef:'defence://ok'}),
    writeAuditEvent:async event=>{audit.push(event)},
    ...overrides
  }};
};

const create=(overrides={})=>{
  const {audit,adapters}=makeAdapters(overrides);
  return {audit,gateway:createFoundationGateway({adapters,clock:()=> '2026-09-26T08:31:00Z'})};
};

test('v1 remains compatible for callers that already know Shine ID',async()=>{
  const {gateway,audit}=create();
  const result=await gateway({envelope:v1,authContext:{jwt:'user',appToken:'app'}});
  assert.equal(result.status,'allowed');
  assert.equal(audit[0].shineId,shineId);
});

test('v2 derives Shine ID from verified identity instead of request body',async()=>{
  const {gateway,audit}=create();
  const result=await gateway({envelope:v2,authContext:{jwt:'user',appToken:'app'}});
  assert.equal(result.status,'allowed');
  assert.equal(audit[0].shineId,shineId);
  assert.equal(Object.hasOwn(v2.permission,'shineId'),false);
});

test('v2 rejects an optional claimed Shine ID that conflicts with verified identity',async()=>{
  const claimed={...v2,permission:{...v2.permission,shineId:'99999999-9999-4999-8999-999999999999'}};
  const {gateway}=create();
  const result=await gateway({envelope:claimed,authContext:{}});
  assert.equal(result.status,'denied');
  assert.equal(result.reasonCode,'identity-mismatch');
});

test('unverified app caller is denied and auditable before identity exists',async()=>{
  let identityCalls=0;
  const {gateway,audit}=create({
    verifyAppCaller:async()=>null,
    verifyIdentity:async()=>{identityCalls++;return {shineId}}
  });
  const result=await gateway({envelope:v2,authContext:{}});
  assert.equal(result.reasonCode,'app-caller-unverified');
  assert.equal(identityCalls,0);
  assert.equal(audit[0].shineId,null);
});

test('calling app cannot impersonate another app',async()=>{
  const {gateway}=create({verifyAppCaller:async()=>({appId:'shine.dive'})});
  const result=await gateway({envelope:v2,authContext:{}});
  assert.equal(result.reasonCode,'app-caller-mismatch');
});

test('unmapped verified token fails closed before Core or Vault',async()=>{
  let manifestCalls=0;
  const {gateway,audit}=create({
    verifyIdentity:async()=>null,
    getAppManifest:async()=>{manifestCalls++;return manifest}
  });
  const result=await gateway({envelope:v2,authContext:{}});
  assert.equal(result.reasonCode,'identity-unverified');
  assert.equal(manifestCalls,0);
  assert.equal(audit[0].shineId,null);
});

test('missing Vault resource denies even when category grant exists',async()=>{
  const {gateway,audit}=create({getVaultResource:async()=>null});
  const result=await gateway({envelope:v2,authContext:{}});
  assert.equal(result.reasonCode,'resource-not-found');
  assert.equal(audit.length,1);
});

test('foreign resource metadata never reaches Defence even from a faulty adapter',async()=>{
  let defenceCalls=0;
  const {gateway,audit}=create({getVaultResource:async()=>({...resource,ownerShineId:'88888888-8888-4888-8888-888888888888'}),
    evaluateDefence:async()=>{defenceCalls++;return {decision:'allow'}}});
  const result=await gateway({envelope:v2,authContext:{jwt:'user'}});
  assert.equal(result.reasonCode,'resource-owner-mismatch');assert.equal(defenceCalls,0);
  assert.equal(audit[0].shineId,shineId);
});

test('another account grants cannot authorise the current account',async()=>{
  const {gateway}=create({getEffectiveGrants:async()=>[{...grant,ownerShineId:'88888888-8888-4888-8888-888888888888'}]});
  const result=await gateway({envelope:v2,authContext:{jwt:'user'}});
  assert.equal(result.status,'denied');assert.equal(result.reasonCode,'no-matching-grant');
});

test('successive users on the same gateway receive separately scoped lookups and audits',async()=>{
  const second='88888888-8888-4888-8888-888888888888',owners=[],grantOwners=[];
  const {gateway,audit}=create({verifyIdentity:async({authContext})=>({shineId:authContext.account}),
    getVaultResource:async({ownerShineId})=>{owners.push(ownerShineId);return {...resource,ownerShineId}},
    getEffectiveGrants:async({shineId:ownerShineId})=>{grantOwners.push(ownerShineId);return [{...grant,ownerShineId}]}});
  for(const account of [shineId,second]) assert.equal((await gateway({envelope:v2,authContext:{account}})).status,'allowed');
  assert.deepEqual(owners,[shineId,second]);assert.deepEqual(grantOwners,owners);
  assert.deepEqual(audit.map(e=>e.shineId),owners);
});

test('missing grant is denied and audited',async()=>{
  const {gateway,audit}=create({getEffectiveGrants:async()=>[]});
  const result=await gateway({envelope:v2,authContext:{}});
  assert.equal(result.reasonCode,'no-matching-grant');
  assert.equal(audit.length,1);
});

test('Defence can veto otherwise valid access',async()=>{
  const {gateway,audit}=create({evaluateDefence:async()=>({decision:'deny',evidenceRef:'defence://veto'})});
  const result=await gateway({envelope:v2,authContext:{}});
  assert.equal(result.reasonCode,'defence-denied');
  assert.equal(audit[0].defenceEvidenceRef,'defence://veto');
});

test('dependency guard denies before Vault grants or Defence and remains auditable',async()=>{
  let vaultCalls=0,grantCalls=0,defenceCalls=0;
  const {gateway,audit}=create({
    evaluateDependencyAdmission:async()=>({
      serviceId:'foundation.gateway',
      environment:'production',
      operation:'access.evaluate',
      impactScope:'protected-operations',
      admissionState:'deny',
      reasonCode:'dependency-guarded',
      ownState:'operational',
      effectiveState:'guarded',
      safeMode:'guarded',
      bindingEvidenceRef:'foundation:admission-binding:gateway:access-evaluate:v1',
      dependencyEvidence:[{
        serviceId:'foundation.defence',
        dependencyType:'guard',
        impact:'guarded',
        impactScope:'protected-operations',
        sourceEvidenceRef:'sentinel:test',
        nativeState:'unhealthy'
      }]
    }),
    getVaultResource:async()=>{vaultCalls++;return resource},
    getEffectiveGrants:async()=>{grantCalls++;return [grant]},
    evaluateDefence:async()=>{defenceCalls++;return {decision:'allow',evidenceRef:'defence://ok'}}
  });
  const result=await gateway({envelope:v2,authContext:{}});
  assert.equal(result.status,'denied');
  assert.equal(result.reasonCode,'dependency-guarded');
  assert.equal(vaultCalls,0);
  assert.equal(grantCalls,0);
  assert.equal(defenceCalls,0);
  assert.equal(audit.length,1);
  assert.equal(audit[0].requestContext.dependencyAdmission.effectiveState,'guarded');
  assert.equal(audit[0].requestContext.dependencyAdmission.dependencyEvidence[0].serviceId,'foundation.defence');
});

test('degraded dependency admission continues and is attached to final access audit',async()=>{
  const {gateway,audit}=create({
    evaluateDependencyAdmission:async()=>({
      serviceId:'foundation.gateway',
      environment:'production',
      operation:'access.evaluate',
      impactScope:'protected-operations',
      admissionState:'admit-degraded',
      reasonCode:'dependency-degraded',
      ownState:'operational',
      effectiveState:'degraded',
      safeMode:'degraded',
      bindingEvidenceRef:'foundation:admission-binding:gateway:access-evaluate:v1',
      dependencyEvidence:[{
        serviceId:'foundation.defence',
        dependencyType:'guard',
        impact:'degraded',
        impactScope:'protected-operations',
        sourceEvidenceRef:'sentinel:warning',
        nativeState:'degraded'
      }]
    })
  });
  const result=await gateway({envelope:v2,authContext:{}});
  assert.equal(result.status,'allowed');
  assert.equal(audit[0].decision,'allow');
  assert.equal(audit[0].requestContext.dependencyAdmission.admissionState,'admit-degraded');
  assert.equal(audit[0].requestContext.dependencyAdmission.reasonCode,'dependency-degraded');
});

test('unavailable admission fails safe before protected resource access and is audited',async()=>{
  let vaultCalls=0;
  const {gateway,audit}=create({
    evaluateDependencyAdmission:async()=>({
      serviceId:'foundation.gateway',
      environment:'production',
      operation:'access.evaluate',
      impactScope:'protected-operations',
      admissionState:'unavailable',
      reasonCode:'dependency-graph-invalid'
    }),
    getVaultResource:async()=>{vaultCalls++;return resource}
  });
  const result=await gateway({envelope:v2,authContext:{}});
  assert.equal(result.status,'unavailable');
  assert.equal(result.reasonCode,'dependency-graph-invalid');
  assert.equal(vaultCalls,0);
  assert.equal(audit.length,1);
  assert.equal(audit[0].decision,'deny');
});

test('invalid envelope is rejected before adapters are called',async()=>{
  let called=false;
  const {gateway}=create({verifyAppCaller:async()=>{called=true;return {appId:'shine.travel'}}});
  const result=await gateway({envelope:{...v2,operation:'vault.dump'},authContext:{}});
  assert.equal(result.status,'invalid');
  assert.equal(called,false);
});

test('dependency failure becomes unavailable',async()=>{
  const {gateway,audit}=create({getAppManifest:async()=>{throw new Error('db down')}});
  const result=await gateway({envelope:v2,authContext:{}});
  assert.equal(result.status,'unavailable');
  assert.equal(audit.length,1);
  assert.equal(audit[0].decision,'deny');
});

test('allow is suppressed if audit cannot persist',async()=>{
  const {gateway}=create({writeAuditEvent:async()=>{throw new Error('audit down')}});
  const result=await gateway({envelope:v2,authContext:{}});
  assert.equal(result.reasonCode,'audit-write-failed');
  assert.equal(Object.hasOwn(result,'decision'),false);
});

test('external response exposes neither grant nor app credential ids',async()=>{
  const {gateway}=create();
  const json=JSON.stringify(await gateway({envelope:v2,authContext:{}}));
  assert.equal(json.includes(grantId),false);
  assert.equal(json.includes('cred-1'),false);
});

test('Foundation unavailability does not disable standalone app',async()=>{
  const {gateway}=create({getVaultResource:async()=>{throw new Error('offline')}});
  const result=await gateway({envelope:v2,authContext:{}});
  assert.equal(Object.hasOwn(result,'disableApp'),false);
});

test('undeclared scope short-circuits before Vault and grants',async()=>{
  let vaultCalls=0,grantCalls=0;
  const changed={...v2,permission:{...v2.permission,scope:'vault.foundation.pilot.write'}};
  const {gateway}=create({
    getVaultResource:async()=>{vaultCalls++;return resource},
    getEffectiveGrants:async()=>{grantCalls++;return [grant]}
  });
  const result=await gateway({envelope:changed,authContext:{}});
  assert.equal(result.reasonCode,'scope-not-declared');
  assert.equal(vaultCalls,0);
  assert.equal(grantCalls,0);
});

test('dependency failures retain stage provenance and only verified identities in the audit',async()=>{
 const stages=[['verifyAppCaller','app-caller-verification',null],['verifyIdentity','identity-verification',null],
 ['getAppManifest','manifest-lookup',shineId],['evaluateDependencyAdmission','dependency-admission',shineId],
 ['getVaultResource','resource-and-grant-lookup',shineId],['evaluateDefence','defence-evaluation',shineId]];
 for(const [adapter,stage,expectedIdentity] of stages){
  const {gateway,audit}=create({[adapter]:async()=>{throw new Error('private-token-secret')}});
  const result=await gateway({envelope:v1,authContext:{jwt:'private-token-secret'}});
  assert.equal(result.status,'unavailable');assert.equal(audit.length,1);
  assert.equal(audit[0].decision,'deny');assert.equal(audit[0].shineId,expectedIdentity);
  assert.equal(audit[0].requestContext.dependencyFailure.stage,stage);
  assert.equal(audit[0].reasonCode,result.reasonCode);
  assert.equal(JSON.stringify({result,audit}).includes('private-token-secret'),false);
 }
});
test('failure provenance still fails closed if the audit store is unavailable',async()=>{
 const {gateway}=create({getAppManifest:async()=>{throw new Error('offline')},
 writeAuditEvent:async()=>{throw new Error('offline')}});
 const r=await gateway({envelope:v2,authContext:{}});
 assert.equal(r.status,'unavailable');assert.equal(r.reasonCode,'audit-write-failed');
});
