import test from 'node:test';
import assert from 'node:assert/strict';
import {createIdentityClaimClient} from './identity-claim-client-v1.mjs';

test('claim client keeps both user proofs and app credential out of JSON',async()=>{
  let call;
  const client=createIdentityClaimClient({
    foundationUrl:'https://foundation.example/functions/v1/foundation-gateway',
    appId:'shine.ski',
    appToken:'a'.repeat(64),
    sourceProviderId:'supabase:ski-session',
    targetProviderId:'supabase:shine-l',
    fetchImpl:async(url,options)=>{
      call={url:String(url),options,body:JSON.parse(options.body)};
      return Response.json({
        identityClaimResponse:'shine-foundation/identity-claim-response-v1',
        schemaVersion:'1.0.0',
        requestId:call.body.requestId,
        status:'linked',
        reasonCode:'identity-claim-linked'
      });
    }
  });

  const result=await client.claim({
    sourceUserToken:'b'.repeat(64),
    targetJwt:'target-jwt'
  });

  assert.equal(result.linked,true);
  assert.equal(result.status,'linked');
  assert.match(call.url,/\/v1\/identity\/claim$/);
  assert.equal(call.options.headers['X-Shine-App-Token'],'a'.repeat(64));
  assert.equal(call.options.headers['X-Shine-User-Token'],'b'.repeat(64));
  assert.equal(call.options.headers.Authorization,'Bearer target-jwt');
  const json=JSON.stringify(call.body);
  assert.equal(json.includes('target-jwt'),false);
  assert.equal(json.includes('b'.repeat(64)),false);
  assert.equal(json.includes('a'.repeat(64)),false);
  assert.equal(Object.hasOwn(call.body,'shineId'),false);
});

test('already-linked is success but still reveals no identity value',async()=>{
  const client=createIdentityClaimClient({
    foundationUrl:'https://foundation.example',
    appId:'shine.ski',
    appToken:'a'.repeat(64),
    sourceProviderId:'supabase:ski-session',
    targetProviderId:'supabase:shine-l',
    fetchImpl:async()=>Response.json({
      identityClaimResponse:'shine-foundation/identity-claim-response-v1',
      schemaVersion:'1.0.0',
      requestId:'11111111-1111-4111-8111-111111111111',
      status:'already-linked',
      reasonCode:'identity-claim-already-linked'
    })
  });
  const result=await client.claim({sourceUserToken:'source',targetJwt:'target'});
  assert.equal(result.linked,true);
  assert.equal(Object.hasOwn(result,'shineId'),false);
});

test('denied claim remains a non-linked result',async()=>{
  const client=createIdentityClaimClient({
    foundationUrl:'https://foundation.example',
    appId:'shine.ski',
    appToken:'a'.repeat(64),
    sourceProviderId:'supabase:ski-session',
    targetProviderId:'supabase:shine-l',
    fetchImpl:async()=>Response.json({
      identityClaimResponse:'shine-foundation/identity-claim-response-v1',
      schemaVersion:'1.0.0',
      requestId:'11111111-1111-4111-8111-111111111111',
      status:'denied',
      reasonCode:'source-already-bound'
    },{status:403})
  });
  const result=await client.claim({sourceUserToken:'source',targetJwt:'target'});
  assert.equal(result.linked,false);
  assert.equal(result.reasonCode,'source-already-bound');
});

test('network failure degrades without claiming identity',async()=>{
  const client=createIdentityClaimClient({
    foundationUrl:'https://foundation.example',
    appId:'shine.ski',
    appToken:'a'.repeat(64),
    sourceProviderId:'supabase:ski-session',
    targetProviderId:'supabase:shine-l',
    fetchImpl:async()=>{throw new Error('offline')}
  });
  const result=await client.claim({sourceUserToken:'source',targetJwt:'target'});
  assert.deepEqual(result,{
    linked:false,
    status:'unavailable',
    reasonCode:'identity-claim-unavailable',
    httpStatus:null
  });
});
