import test from 'node:test';
import assert from 'node:assert/strict';
import {createIdentityClaimService} from './identity-claim-v1.mjs';

const claim={
  identityClaimRequest:'shine-foundation/identity-claim-request-v1',
  schemaVersion:'1.0.0',
  operation:'identity.claim',
  claimId:'11111111-1111-4111-8111-111111111111',
  appId:'shine.ski',
  requestedAt:'2026-09-26T12:50:00Z',
  permission:{
    scope:'vault.foundation.pilot.read',
    purpose:'ski.foundation-pilot',
    resourceCategory:'foundation.pilot'
  }
};

const make=overrides=>{
  const calls=[];
  const adapters={
    verifyAppCaller:async()=>({appId:'shine.ski'}),
    verifyOpaqueIdentityProof:async()=>({providerId:'supabase:ski-session',providerSubject:'a'.repeat(64)}),
    verifyCanonicalIdentityProof:async()=>({shineId:'22222222-2222-4222-8222-222222222222',providerId:'supabase:shine-l'}),
    getAppManifest:async()=>({
      appId:'shine.ski',
      foundation:{requestedScopes:[{
        scope:'vault.foundation.pilot.read',
        purpose:'ski.foundation-pilot',
        resourceCategory:'foundation.pilot'
      }]}
    }),
    claimIdentityAndGrant:async args=>{calls.push(args);return {outcome:'linked',bindingCreated:true,grantCreated:true}},
    ...overrides
  };
  return {service:createIdentityClaimService({adapters}),calls};
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

test('dual-proof claim links opaque session and issues declared grant',async()=>{
  const {service,calls}=make();
  const res=await service({envelope:claim,authContext:auth});
  assert.equal(res.status,'linked');
  assert.equal(res.reasonCode,'identity-linked');
  assert.equal(res.bindingCreated,true);
  assert.equal(res.grantCreated,true);
  assert.equal(calls.length,1);
  assert.equal(calls[0].appId,'shine.ski');
  assert.equal(calls[0].providerId,'supabase:ski-session');
  assert.equal(calls[0].providerSubject,'a'.repeat(64));
  assert.equal(calls[0].scope,'vault.foundation.pilot.read');
  assert.equal(Object.hasOwn(calls[0],'jwt'),false);
  assert.equal(Object.hasOwn(calls[0],'userToken'),false);
});

test('unverified canonical proof cannot create binding or grant',async()=>{
  let writes=0;
  const {service}=make({
    verifyCanonicalIdentityProof:async()=>null,
    claimIdentityAndGrant:async()=>{writes++;return {outcome:'linked'}}
  });
  const res=await service({envelope:claim,authContext:auth});
  assert.equal(res.status,'denied');
  assert.equal(res.reasonCode,'canonical-proof-unverified');
  assert.equal(writes,0);
});

test('undeclared permission cannot be created by claim flow',async()=>{
  let writes=0;
  const {service}=make({
    getAppManifest:async()=>({appId:'shine.ski',foundation:{requestedScopes:[]}}),
    claimIdentityAndGrant:async()=>{writes++;return {outcome:'linked'}}
  });
  const res=await service({envelope:claim,authContext:auth});
  assert.equal(res.status,'denied');
  assert.equal(res.reasonCode,'permission-not-declared');
  assert.equal(writes,0);
});

test('existing binding to another canonical identity fails closed',async()=>{
  const {service}=make({claimIdentityAndGrant:async()=>({outcome:'conflict',bindingCreated:false,grantCreated:false})});
  const res=await service({envelope:claim,authContext:auth});
  assert.equal(res.status,'conflict');
  assert.equal(res.reasonCode,'identity-claim-conflict');
});
