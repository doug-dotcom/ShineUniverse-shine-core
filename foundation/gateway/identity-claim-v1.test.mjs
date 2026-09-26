import test from 'node:test';
import assert from 'node:assert/strict';
import {createIdentityClaimService} from './identity-claim-v1.mjs';

const now='2026-09-26T13:00:00Z';
const claim={
  identityClaimRequest:'shine-foundation/identity-claim-request-v1',
  schemaVersion:'1.0.0',
  operation:'identity.claim',
  claimId:'11111111-1111-4111-8111-111111111111',
  requestId:'33333333-3333-4333-8333-333333333333',
  appId:'shine.ski',
  requestedAt:now
};

const make=overrides=>{
  const calls=[];
  const adapters={
    verifyAppCaller:async()=>({appId:'shine.ski'}),
    verifyOpaqueIdentityProof:async()=>({providerId:'supabase:ski-session',providerSubject:'a'.repeat(64)}),
    verifyCanonicalIdentityProof:async()=>({
      shineId:'22222222-2222-4222-8222-222222222222',
      providerId:'supabase:shine-l',
      authSubject:'canonical-user'
    }),
    completeIdentityClaim:async args=>{
      calls.push(args);
      return {outcome:'linked',reasonCode:'identity-claim-linked'};
    },
    ...overrides
  };
  return {service:createIdentityClaimService({adapters,clock:()=>now}),calls};
};

const auth={appToken:'app-secret',userToken:'u'.repeat(64),jwt:'header.payload.sig'};

test('requires exact claim envelope and never accepts caller supplied Shine ID',async()=>{
  const {service}=make();
  const res=await service({envelope:{...claim,shineId:'nope'},authContext:auth});
  assert.equal(res.status,'invalid');
  assert.equal(res.reasonCode,'invalid-identity-claim-request');
});

test('requires app, opaque session and canonical JWT proof in one request',async()=>{
  const {service}=make();
  const res=await service({envelope:claim,authContext:{appToken:'x',userToken:'y'}});
  assert.equal(res.status,'denied');
  assert.equal(res.reasonCode,'dual-proof-required');
});

test('stale claim requests are rejected before any identity write',async()=>{
  let writes=0;
  const {service}=make({completeIdentityClaim:async()=>{writes++;return {outcome:'linked'}}});
  const res=await service({
    envelope:{...claim,requestedAt:'2026-09-26T12:00:00Z'},
    authContext:auth
  });
  assert.equal(res.status,'invalid');
  assert.equal(res.reasonCode,'stale-identity-claim-request');
  assert.equal(writes,0);
});

test('dual-proof claim links opaque session without creating a Vault grant',async()=>{
  const {service,calls}=make();
  const res=await service({envelope:claim,authContext:auth});
  assert.equal(res.status,'linked');
  assert.equal(res.reasonCode,'identity-claim-linked');
  assert.equal(res.bindingCreated,true);
  assert.equal(Object.hasOwn(res,'grantCreated'),false);
  assert.equal(calls.length,1);
  assert.equal(calls[0].appId,'shine.ski');
  assert.equal(calls[0].sourceProviderId,'supabase:ski-session');
  assert.equal(calls[0].sourceProviderSubject,'a'.repeat(64));
  assert.equal(calls[0].targetProviderId,'supabase:shine-l');
  assert.equal(Object.hasOwn(calls[0],'jwt'),false);
  assert.equal(Object.hasOwn(calls[0],'userToken'),false);
});

test('unverified canonical proof cannot create a binding',async()=>{
  let writes=0;
  const {service}=make({
    verifyCanonicalIdentityProof:async()=>null,
    completeIdentityClaim:async()=>{writes++;return {outcome:'linked'}}
  });
  const res=await service({envelope:claim,authContext:auth});
  assert.equal(res.status,'denied');
  assert.equal(res.reasonCode,'canonical-proof-unverified');
  assert.equal(writes,0);
});

test('idempotent already-linked outcome remains successful',async()=>{
  const {service}=make({
    completeIdentityClaim:async()=>({
      outcome:'already-linked',
      reasonCode:'identity-claim-already-linked'
    })
  });
  const res=await service({envelope:claim,authContext:auth});
  assert.equal(res.status,'linked');
  assert.equal(res.bindingCreated,false);
  assert.equal(res.reasonCode,'identity-claim-already-linked');
});

test('attempt to rebind a session to another identity is a conflict',async()=>{
  const {service}=make({
    completeIdentityClaim:async()=>({
      outcome:'denied',
      reasonCode:'source-already-bound'
    })
  });
  const res=await service({envelope:claim,authContext:auth});
  assert.equal(res.status,'conflict');
  assert.equal(res.reasonCode,'identity-claim-conflict');
});
