import test from 'node:test';
import assert from 'node:assert/strict';
import {createFoundationAppClient} from './foundation-app-client-v1.mjs';

const UUIDS=[
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  '33333333-3333-4333-8333-333333333333',
  '44444444-4444-4444-8444-444444444444',
  '55555555-5555-4555-8555-555555555555',
  '66666666-6666-4666-8666-666666666666'
];
const cryptoBackup=globalThis.crypto;
Object.defineProperty(globalThis,'crypto',{value:{...cryptoBackup,randomUUID:()=>UUIDS.shift()??'33333333-3333-4333-8333-333333333333'},configurable:true});

const allowedResponse=body=>Response.json({
  gatewayResponse:'shine-foundation/gateway-response-v1',
  schemaVersion:'1.0.0',
  traceId:body.traceId,
  requestId:body.permission.requestId,
  status:'allowed',
  reasonCode:'grant-match',
  decision:{decision:'allow',reasonCode:'grant-match'}
});

test('JWT client keeps credentials in headers and never sends shineId',async()=>{
  let call;
  const client=createFoundationAppClient({
    foundationUrl:'https://foundation.example/functions/v1/foundation-gateway/',
    appId:'shine.travel',
    appToken:'a'.repeat(64),
    userCredentialMode:'bearer-jwt',
    fetchImpl:async(url,options)=>{
      const body=JSON.parse(options.body);
      call={url,options,body};
      return allowedResponse(body);
    }
  });
  const result=await client.evaluate({
    userCredential:'jwt-value',
    scope:'vault.foundation.pilot.read',
    purpose:'travel.foundation-pilot',
    resourceCategory:'foundation.pilot'
  });
  assert.equal(result.status,'allowed');
  assert.equal(call.options.headers.Authorization,'Bearer jwt-value');
  assert.equal(call.options.headers['X-Shine-App-Token'],'a'.repeat(64));
  assert.equal(Object.hasOwn(call.body.permission,'shineId'),false);
  assert.equal(JSON.stringify(call.body).includes('jwt-value'),false);
  assert.equal(JSON.stringify(call.body).includes('a'.repeat(64)),false);
});

test('opaque client uses X-Shine-User-Token and no bearer header',async()=>{
  let headers;
  const client=createFoundationAppClient({
    foundationUrl:'https://foundation.example/functions/v1/foundation-gateway',
    appId:'shine.dive',
    appToken:'b'.repeat(64),
    userCredentialMode:'opaque-header',
    fetchImpl:async(url,options)=>{
      headers=options.headers;
      return allowedResponse(JSON.parse(options.body));
    }
  });
  const result=await client.evaluate({
    userCredential:'c'.repeat(64),
    scope:'vault.foundation.pilot.read',
    purpose:'dive.foundation-pilot',
    resourceCategory:'foundation.pilot'
  });
  assert.equal(result.connected,true);
  assert.equal(headers['X-Shine-User-Token'],'c'.repeat(64));
  assert.equal(Object.hasOwn(headers,'Authorization'),false);
});

test('network failure degrades without disabling the app',async()=>{
  const client=createFoundationAppClient({
    foundationUrl:'https://foundation.example',
    appId:'shine.travel',
    appToken:'a'.repeat(64),
    userCredentialMode:'bearer-jwt',
    fetchImpl:async()=>{throw new Error('offline')}
  });
  assert.deepEqual(await client.evaluate({
    userCredential:'jwt',
    scope:'vault.foundation.pilot.read',
    purpose:'travel.foundation-pilot',
    resourceCategory:'foundation.pilot'
  }),{
    connected:false,status:'unavailable',reasonCode:'foundation-unavailable',httpStatus:null
  });
});

test('oversized Foundation response fails closed',async()=>{
  const client=createFoundationAppClient({
    foundationUrl:'https://foundation.example',
    appId:'shine.travel',
    appToken:'a'.repeat(64),
    userCredentialMode:'bearer-jwt',
    fetchImpl:async()=>new Response('x'.repeat(70000),{status:200,headers:{'content-type':'application/json'}})
  });
  const result=await client.evaluate({
    userCredential:'jwt',
    scope:'vault.foundation.pilot.read',
    purpose:'travel.foundation-pilot',
    resourceCategory:'foundation.pilot'
  });
  assert.equal(result.status,'unavailable');
});


test('opaque client claims identity with both proofs in headers and no personal IDs in body',async()=>{
  let call;
  const appToken='d'.repeat(64);
  const userToken='e'.repeat(64);
  const canonicalJwt='canonical.jwt.value';
  const client=createFoundationAppClient({
    foundationUrl:'https://foundation.example/functions/v1/foundation-gateway',
    appId:'shine.ski',
    appToken,
    userCredentialMode:'opaque-header',
    fetchImpl:async(url,options)=>{
      const body=JSON.parse(options.body);
      call={url,options,body};
      return Response.json({
        identityClaimResponse:'shine-foundation/identity-claim-response-v1',
        schemaVersion:'1.0.0',
        claimId:body.claimId,
        requestId:body.requestId,
        appId:'shine.ski',
        status:'linked',
        reasonCode:'identity-claim-linked',
        bindingCreated:true
      });
    }
  });
  const result=await client.claimIdentity({userCredential:userToken,canonicalJwt});
  assert.equal(result.status,'linked');
  assert.equal(result.bindingCreated,true);
  assert.equal(call.url,'https://foundation.example/functions/v1/foundation-gateway/v1/identity/claim');
  assert.equal(call.options.headers['X-Shine-App-Token'],appToken);
  assert.equal(call.options.headers['X-Shine-User-Token'],userToken);
  assert.equal(call.options.headers.Authorization,'Bearer '+canonicalJwt);
  const encoded=JSON.stringify(call.body);
  assert.equal(encoded.includes(appToken),false);
  assert.equal(encoded.includes(userToken),false);
  assert.equal(encoded.includes(canonicalJwt),false);
  assert.equal(Object.hasOwn(call.body,'shineId'),false);
  assert.equal(Object.hasOwn(call.body,'providerSubject'),false);
});

test('JWT-only appendages cannot invoke opaque identity claim helper',async()=>{
  const client=createFoundationAppClient({
    foundationUrl:'https://foundation.example',
    appId:'shine.travel',
    appToken:'a'.repeat(64),
    userCredentialMode:'bearer-jwt'
  });
  await assert.rejects(
    ()=>client.claimIdentity({userCredential:'x'.repeat(64),canonicalJwt:'jwt'}),
    /opaque-header/
  );
});
