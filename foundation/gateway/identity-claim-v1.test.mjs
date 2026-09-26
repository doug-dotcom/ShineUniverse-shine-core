import test from 'node:test';
import assert from 'node:assert/strict';
import {createIdentityClaimService} from './identity-claim-v1.mjs';

const requestId='11111111-1111-4111-8111-111111111111';
const claimId='22222222-2222-4222-8222-222222222222';
const shineId='33333333-3333-4333-8333-333333333333';

const envelope={
  identityClaim:'shine-foundation/identity-claim-v1',
  schemaVersion:'1.0.0',
  requestId,
  appId:'shine.ski',
  sourceProviderId:'supabase:ski-session',
  targetProviderId:'supabase:shine-l',
  requestedAt:'2026-09-26T12:00:00Z'
};

const make=overrides=>{
  const calls=[];
  const adapters={
    verifyAppCaller:async()=>({appId:'shine.ski',credentialId:'app-cred'}),
    verifyClaimSource:async()=>({providerId:'supabase:ski-session',authSubject:'source-hash'}),
    verifyClaimTarget:async()=>({providerId:'supabase:shine-l',authSubject:'target-user',shineId}),
    getAppManifest:async()=>({appId:'shine.ski'}),
    evaluateDefence:async()=>({decision:'allow',evidenceRef:'defence://claim-ok'}),
    completeIdentityClaim:async input=>{calls.push(input);return {outcome:'linked',reason_code:'identity-claim-linked'}},
    ...overrides
  };
  return {
    calls,
    claim:createIdentityClaimService({
      adapters,
      clock:()=> '2026-09-26T12:10:00Z',
      idFactory:()=>claimId
    })
  };
};

test('links only after app, source and target proofs all verify',async()=>{
  const {claim,calls}=make();
  const result=await claim({
    envelope,
    authContext:{
      appToken:'app-secret',
      sourceUserToken:'source-secret',
      targetJwt:'target-jwt'
    }
  });
  assert.deepEqual(result,{
    identityClaimResponse:'shine-foundation/identity-claim-response-v1',
    schemaVersion:'1.0.0',
    requestId,
    status:'linked',
    reasonCode:'identity-claim-linked'
  });
  assert.equal(calls.length,1);
  assert.deepEqual(calls[0],{
    claimId,
    requestId,
    appId:'shine.ski',
    sourceProviderId:'supabase:ski-session',
    sourceSubject:'source-hash',
    targetProviderId:'supabase:shine-l',
    targetSubject:'target-user',
    targetShineId:shineId,
    occurredAt:'2026-09-26T12:10:00Z'
  });
});

test('unverified app short-circuits source and target identity proofs',async()=>{
  let sourceCalls=0,targetCalls=0;
  const {claim}=make({
    verifyAppCaller:async()=>null,
    verifyClaimSource:async()=>{sourceCalls++;return null},
    verifyClaimTarget:async()=>{targetCalls++;return null}
  });
  const result=await claim({envelope,authContext:{}});
  assert.equal(result.reasonCode,'app-caller-unverified');
  assert.equal(sourceCalls,0);
  assert.equal(targetCalls,0);
});

test('source proof failure never checks target identity',async()=>{
  let targetCalls=0;
  const {claim}=make({
    verifyClaimSource:async()=>null,
    verifyClaimTarget:async()=>{targetCalls++;return null}
  });
  const result=await claim({envelope,authContext:{}});
  assert.equal(result.reasonCode,'source-identity-unverified');
  assert.equal(targetCalls,0);
});

test('target proof failure never writes a binding',async()=>{
  let writes=0;
  const {claim}=make({
    verifyClaimTarget:async()=>null,
    completeIdentityClaim:async()=>{writes++;return null}
  });
  const result=await claim({envelope,authContext:{}});
  assert.equal(result.reasonCode,'target-identity-unverified');
  assert.equal(writes,0);
});

test('Defence can veto a fully proven claim',async()=>{
  let writes=0;
  const {claim}=make({
    evaluateDefence:async()=>({decision:'deny'}),
    completeIdentityClaim:async()=>{writes++;return null}
  });
  const result=await claim({envelope,authContext:{}});
  assert.equal(result.reasonCode,'defence-denied');
  assert.equal(writes,0);
});

test('already-linked is idempotent and does not reveal Shine ID',async()=>{
  const {claim}=make({
    completeIdentityClaim:async()=>({outcome:'already-linked',reason_code:'identity-claim-already-linked'})
  });
  const result=await claim({envelope,authContext:{}});
  assert.equal(result.status,'already-linked');
  const json=JSON.stringify(result);
  assert.equal(json.includes(shineId),false);
  assert.equal(json.includes('source-hash'),false);
  assert.equal(json.includes('target-user'),false);
});

test('source already bound elsewhere is denied',async()=>{
  const {claim}=make({
    completeIdentityClaim:async()=>({outcome:'denied',reason_code:'source-already-bound'})
  });
  const result=await claim({envelope,authContext:{}});
  assert.equal(result.status,'denied');
  assert.equal(result.reasonCode,'source-already-bound');
});

test('invalid claim envelope is rejected before adapters run',async()=>{
  let called=false;
  const {claim}=make({verifyAppCaller:async()=>{called=true;return {appId:'shine.ski'}}});
  const result=await claim({envelope:{...envelope,targetProviderId:'supabase:ski-session'},authContext:{}});
  assert.equal(result.status,'invalid');
  assert.equal(called,false);
});


test('stale identity claim is rejected before any proof or write runs',async()=>{
  let appCalls=0,writes=0;
  const {claim}=make({
    verifyAppCaller:async()=>{appCalls++;return {appId:'shine.ski'}},
    completeIdentityClaim:async()=>{writes++;return null}
  });
  const result=await claim({
    envelope:{...envelope,requestedAt:'2026-09-26T11:59:59Z'},
    authContext:{}
  });
  assert.equal(result.status,'invalid');
  assert.equal(result.reasonCode,'stale-identity-claim-request');
  assert.equal(appCalls,0);
  assert.equal(writes,0);
});
