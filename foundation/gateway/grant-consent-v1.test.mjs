import test from 'node:test';
import assert from 'node:assert/strict';
import {createGrantConsentService} from './grant-consent-v1.mjs';

const requestId='11111111-1111-4111-8111-111111111111';
const shineId='22222222-2222-4222-8222-222222222222';
const consentId='33333333-3333-4333-8333-333333333333';
const grantId='44444444-4444-4444-8444-444444444444';

const envelope={
  grantConsent:'shine-foundation/grant-consent-v1',
  schemaVersion:'1.0.0',
  requestId,
  appId:'shine.ski',
  scope:'vault.foundation.pilot.read',
  purpose:'ski.foundation-pilot',
  resourceCategory:'foundation.pilot',
  consent:true,
  requestedAt:'2026-09-26T13:00:00Z'
};

const make=overrides=>{
  const writes=[];
  let ids=[consentId,grantId];
  const adapters={
    verifyAppCaller:async()=>({appId:'shine.ski',credentialId:'app-cred'}),
    verifyIdentity:async()=>({shineId,providerId:'supabase:ski-session',authSubject:'subject'}),
    getAppManifest:async()=>({
      appId:'shine.ski',
      foundation:{requestedScopes:[{
        scope:'vault.foundation.pilot.read',
        purpose:'ski.foundation-pilot',
        resourceCategory:'foundation.pilot'
      }]}
    }),
    getVaultResource:async()=>({
      resourceId:'55555555-5555-4555-8555-555555555555',
      ownerShineId:shineId,category:'foundation.pilot',sensitivity:'personal'
    }),
    evaluateDefence:async()=>({decision:'allow',evidenceRef:'defence://consent-ok'}),
    issueAccessGrant:async input=>{writes.push(input);return {outcome:'granted',reason_code:'grant-consent-recorded',grant_id:grantId}},
    ...overrides
  };
  return {
    writes,
    consent:createGrantConsentService({
      adapters,
      clock:()=> '2026-09-26T13:05:00Z',
      idFactory:()=>ids.shift()
    })
  };
};

test('explicit consent produces a least-privilege grant write after every proof',async()=>{
  const {consent,writes}=make();
  const result=await consent({envelope,authContext:{appToken:'app',userToken:'user'}});
  assert.equal(result.status,'granted');
  assert.equal(result.reasonCode,'grant-consent-recorded');
  assert.equal(writes.length,1);
  assert.deepEqual(writes[0],{
    consentId,grantId,requestId,ownerShineId:shineId,appId:'shine.ski',
    scope:'vault.foundation.pilot.read',purpose:'ski.foundation-pilot',
    resourceId:null,resourceCategory:'foundation.pilot',
    occurredAt:'2026-09-26T13:05:00Z'
  });
});

test('consent must be explicit true',async()=>{
  const {consent,writes}=make();
  const result=await consent({envelope:{...envelope,consent:false},authContext:{}});
  assert.equal(result.status,'invalid');assert.equal(writes.length,0);
});

test('unverified identity cannot create a grant',async()=>{
  const {consent,writes}=make({verifyIdentity:async()=>null});
  const result=await consent({envelope,authContext:{}});
  assert.equal(result.reasonCode,'identity-unverified');assert.equal(writes.length,0);
});

test('manifest scope and purpose are authoritative',async()=>{
  const {consent,writes}=make({getAppManifest:async()=>({appId:'shine.ski',foundation:{requestedScopes:[]}})});
  const result=await consent({envelope,authContext:{}});
  assert.equal(result.reasonCode,'scope-not-declared');assert.equal(writes.length,0);
});

test('Vault ownership is checked before grant persistence',async()=>{
  const {consent,writes}=make({
    getVaultResource:async()=>({
      resourceId:'55555555-5555-4555-8555-555555555555',
      ownerShineId:'66666666-6666-4666-8666-666666666666',
      category:'foundation.pilot',sensitivity:'personal'
    })
  });
  const result=await consent({envelope,authContext:{}});
  assert.equal(result.reasonCode,'resource-owner-mismatch');assert.equal(writes.length,0);
});

test('Defence may veto consent before any grant write',async()=>{
  const {consent,writes}=make({evaluateDefence:async()=>({decision:'deny'})});
  const result=await consent({envelope,authContext:{}});
  assert.equal(result.reasonCode,'defence-denied');assert.equal(writes.length,0);
});

test('stale consent requests are rejected',async()=>{
  const {consent,writes}=make();
  const result=await consent({envelope:{...envelope,requestedAt:'2026-09-26T12:00:00Z'},authContext:{}});
  assert.equal(result.reasonCode,'stale-grant-consent-request');assert.equal(writes.length,0);
});

test('already-granted is idempotent success without exposing identity or grant ids',async()=>{
  const {consent}=make({
    issueAccessGrant:async()=>({outcome:'already-granted',reason_code:'grant-already-active',grant_id:grantId})
  });
  const result=await consent({envelope,authContext:{}});
  assert.equal(result.status,'already-granted');
  assert.equal(Object.hasOwn(result,'shineId'),false);
  assert.equal(Object.hasOwn(result,'grantId'),false);
});
