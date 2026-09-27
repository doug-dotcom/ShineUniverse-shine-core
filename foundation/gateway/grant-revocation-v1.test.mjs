import test from 'node:test';
import assert from 'node:assert/strict';
import {createGrantRevocationService} from './grant-revocation-v1.mjs';

const requestId='11111111-1111-4111-8111-111111111111';
const shineId='22222222-2222-4222-8222-222222222222';
const grantId='33333333-3333-4333-8333-333333333333';
const eventId='44444444-4444-4444-8444-444444444444';
const revocationId='55555555-5555-4555-8555-555555555555';

const envelope={
  grantRevocation:'shine-foundation/grant-revocation-v1',
  schemaVersion:'1.0.0',
  requestId,
  appId:'shine.ski',
  grantId,
  revoke:true,
  requestedAt:'2026-09-27T13:00:00Z'
};

const make=overrides=>{
  const writes=[];
  const ids=[eventId,revocationId];
  const adapters={
    verifyAppCaller:async()=>({appId:'shine.ski',credentialId:'app-cred'}),
    verifyIdentity:async()=>({shineId,providerId:'supabase:ski-session',authSubject:'subject'}),
    revokeAccessGrant:async input=>{
      writes.push(input);
      return {outcome:'revoked',reason_code:'grant-revoked-by-user',revocation_id:revocationId};
    },
    ...overrides
  };
  return {
    writes,
    revoke:createGrantRevocationService({
      adapters,
      clock:()=> '2026-09-27T13:05:00Z',
      idFactory:()=>ids.shift()??crypto.randomUUID()
    })
  };
};

test('explicit user revocation records replay evidence after app and identity proof',async()=>{
  const {revoke,writes}=make();
  const result=await revoke({envelope,authContext:{appToken:'app',userToken:'user'}});
  assert.equal(result.status,'revoked');
  assert.equal(result.reasonCode,'grant-revoked-by-user');
  assert.deepEqual(writes,[{
    eventId,
    revocationId,
    requestId,
    grantId,
    ownerShineId:shineId,
    appId:'shine.ski',
    occurredAt:'2026-09-27T13:05:00Z'
  }]);
});

test('revoke must be an explicit true action',async()=>{
  const {revoke,writes}=make();
  const result=await revoke({envelope:{...envelope,revoke:false},authContext:{}});
  assert.equal(result.status,'invalid');
  assert.equal(result.reasonCode,'invalid-grant-revocation-request');
  assert.equal(writes.length,0);
});

test('unverified identity cannot revoke a grant',async()=>{
  const {revoke,writes}=make({verifyIdentity:async()=>null});
  const result=await revoke({envelope,authContext:{}});
  assert.equal(result.reasonCode,'identity-unverified');
  assert.equal(writes.length,0);
});

test('stale revoke requests are rejected before any write',async()=>{
  const {revoke,writes}=make();
  const result=await revoke({envelope:{...envelope,requestedAt:'2026-09-27T12:00:00Z'},authContext:{}});
  assert.equal(result.reasonCode,'stale-grant-revocation-request');
  assert.equal(writes.length,0);
});

test('already revoked is idempotent success and response hides internal revocation id',async()=>{
  const {revoke}=make({
    revokeAccessGrant:async()=>({
      outcome:'already-revoked',
      reason_code:'grant-already-revoked',
      revocation_id:revocationId
    })
  });
  const result=await revoke({envelope,authContext:{}});
  assert.equal(result.status,'already-revoked');
  assert.equal(Object.hasOwn(result,'revocationId'),false);
  assert.equal(Object.hasOwn(result,'shineId'),false);
});

test('revocation has no Defence dependency',()=>{
  assert.doesNotThrow(()=>createGrantRevocationService({
    adapters:{
      verifyAppCaller:async()=>({appId:'shine.ski'}),
      verifyIdentity:async()=>({shineId}),
      revokeAccessGrant:async()=>({outcome:'revoked',reason_code:'grant-revoked-by-user'})
    }
  }));
});
