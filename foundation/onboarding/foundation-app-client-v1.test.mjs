import test from 'node:test';
import assert from 'node:assert/strict';
import {createFoundationAppClient} from './foundation-app-client-v1.mjs';

const UUIDS=['11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222'];
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
