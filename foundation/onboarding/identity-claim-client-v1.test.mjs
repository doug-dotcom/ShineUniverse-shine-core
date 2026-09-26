import test from 'node:test';
import assert from 'node:assert/strict';
import {createIdentityClaimClient} from './identity-claim-client-v1.mjs';

const cryptoBackup=globalThis.crypto;
const ids=[
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222'
];
Object.defineProperty(globalThis,'crypto',{
  value:{...cryptoBackup,randomUUID:()=>ids.shift()??'33333333-3333-4333-8333-333333333333'},
  configurable:true
});

test('claim client keeps all proofs in headers and provider identities off the JSON body',async()=>{
  let call;
  const appToken='a'.repeat(64);
  const sourceUserToken='b'.repeat(64);
  const targetJwt='header.payload.signature';
  const client=createIdentityClaimClient({
    foundationUrl:'https://foundation.example/functions/v1/foundation-gateway',
    appId:'shine.ski',
    appToken,
    fetchImpl:async(url,options)=>{
      call={url,options,body:JSON.parse(options.body)};
      return Response.json({
        identityClaimResponse:'shine-foundation/identity-claim-response-v1',
        schemaVersion:'1.0.0',
        claimId:call.body.claimId,
        requestId:call.body.requestId,
        appId:'shine.ski',
        status:'linked',
        reasonCode:'identity-claim-linked',
        bindingCreated:true
      });
    }
  });

  const result=await client.claim({sourceUserToken,targetJwt});
  assert.equal(result.linked,true);
  assert.equal(result.status,'linked');
  assert.equal(result.bindingCreated,true);
  assert.equal(call.url,'https://foundation.example/functions/v1/foundation-gateway/v1/identity/claim');
  assert.equal(call.options.headers['X-Shine-App-Token'],appToken);
  assert.equal(call.options.headers['X-Shine-User-Token'],sourceUserToken);
  assert.equal(call.options.headers.Authorization,'Bearer '+targetJwt);

  assert.deepEqual(Object.keys(call.body).sort(),[
    'appId','claimId','identityClaimRequest','operation','requestId','requestedAt','schemaVersion'
  ]);
  const encoded=JSON.stringify(call.body);
  assert.equal(encoded.includes(appToken),false);
  assert.equal(encoded.includes(sourceUserToken),false);
  assert.equal(encoded.includes(targetJwt),false);
  assert.equal(encoded.includes('provider'),false);
  assert.equal(Object.hasOwn(call.body,'shineId'),false);
});

test('claim client preserves conflict result without treating it as linked',async()=>{
  const client=createIdentityClaimClient({
    foundationUrl:'https://foundation.example',
    appId:'shine.ski',
    appToken:'a'.repeat(64),
    fetchImpl:async()=>Response.json({
      identityClaimResponse:'shine-foundation/identity-claim-response-v1',
      schemaVersion:'1.0.0',
      claimId:'1',
      requestId:'2',
      appId:'shine.ski',
      status:'conflict',
      reasonCode:'identity-claim-conflict'
    },{status:409})
  });

  const result=await client.claim({
    sourceUserToken:'b'.repeat(64),
    targetJwt:'jwt'
  });
  assert.equal(result.linked,false);
  assert.equal(result.status,'conflict');
  assert.equal(result.reasonCode,'identity-claim-conflict');
});
