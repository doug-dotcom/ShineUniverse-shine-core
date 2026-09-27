import test from 'node:test';
import assert from 'node:assert/strict';
import {createGrantRevokeService} from './grant-revoke-v1.mjs';

const requestId='11111111-1111-4111-8111-111111111111';
const shineId='22222222-2222-4222-8222-222222222222';
const grantId='33333333-3333-4333-8333-333333333333';
const revocationId='44444444-4444-4444-8444-444444444444';

const envelope={
  grantRevoke:'shine-foundation/grant-revoke-v1',
  schemaVersion:'1.0.0',
  requestId,
  appId:'shine.ski',
  grantId,
  requestedAt:'2026-09-27T13:00:00Z'
};

const make=overrides=>{
  const writes=[];
  const adapters={
    verifyAppCaller:async()=>({appId:'shine.ski',credentialId:'app-cred'}),
    verifyIdentity:async()=>({shineId,providerId:'supabase:ski-session',authSubject:'subject'}),
    revokeAccessGrant:async input=>{
      writes.push(input);
      return {outcome:'revoked',reason_code:'grant-revoked-by-user',grant_id:grantId};
    },
    ...overrides
  };
  return {
    writes,
    revoke:createGrantRevokeService({
      adapters,
      clock:()=> '2026-09-27T13:05:00Z',
      idFactory:()=>revocationId
    })
  };
};

test('explicit user revoke writes only after app and identity proof',async()=>{
  const {revoke,writes}=make();
  const result=await revoke({envelope,authContext:{appToken:'app',userToken:'user'}});
  assert.equal(result.status,'revoked');
  assert.equal(result.reasonCode,'grant-revoked-by-user');
  assert.equal(writes.length,1);
  assert.deepEqual(writes[0],{
    revocationId,grantId,ownerShineId:shineId,appId:'shine.ski',
    revokedAt:'2026-09-27T13:05:00Z'
  });
});

test('unverified identity cannot revoke a grant',async()=>{
  const {revoke,writes}=make({verifyIdentity:async()=>null});
  const result=await revoke({envelope,authContext:{}});
  assert.equal(result.reasonCode,'identity-unverified');
  assert.equal(writes.length,0);
});

test('app mismatch cannot revoke a grant',async()=>{
  const {revoke,writes}=make({verifyAppCaller:async()=>({appId:'shine.dive'})});
  const result=await revoke({envelope,authContext:{}});
  assert.equal(result.reasonCode,'app-caller-mismatch');
  assert.equal(writes.length,0);
});

test('stale revoke requests are rejected before any write',async()=>{
  const {revoke,writes}=make();
  const result=await revoke({
    envelope:{...envelope,requestedAt:'2026-09-27T12:00:00Z'},
    authContext:{}
  });
  assert.equal(result.reasonCode,'stale-grant-revoke-request');
  assert.equal(writes.length,0);
});

test('already revoked is idempotent success and exposes no identity',async()=>{
  const {revoke}=make({
    revokeAccessGrant:async()=>({
      outcome:'already-revoked',
      reason_code:'grant-already-revoked',
      grant_id:grantId
    })
  });
  const result=await revoke({envelope,authContext:{}});
  assert.equal(result.status,'already-revoked');
  assert.equal(Object.hasOwn(result,'shineId'),false);
  assert.equal(Object.hasOwn(result,'grantId'),false);
});

test('revocation has no Defence dependency',()=>{
  assert.doesNotThrow(()=>createGrantRevokeService({
    adapters:{
      verifyAppCaller:async()=>({appId:'shine.ski'}),
      verifyIdentity:async()=>({shineId}),
      revokeAccessGrant:async()=>({outcome:'revoked',reason_code:'grant-revoked-by-user'})
    }
  }));
});
