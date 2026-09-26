import test from 'node:test';
import assert from 'node:assert/strict';
import {createGrantConsentClient} from './grant-consent-client-v1.mjs';

const baseOptions={
  foundationUrl:'https://foundation.example/functions/v1/foundation-gateway',
  appId:'shine.ski',
  appToken:'a'.repeat(64),
  scope:'vault.foundation.pilot.read',
  purpose:'ski.foundation-pilot',
  resourceCategory:'foundation.pilot'
};

test('opaque-session consent keeps app and user credentials out of JSON',async()=>{
  let call;
  const client=createGrantConsentClient({
    ...baseOptions,
    fetchImpl:async(url,options)=>{
      call={url:String(url),options,body:JSON.parse(options.body)};
      return Response.json({status:'granted',reasonCode:'grant-consent-recorded'});
    }
  });
  const result=await client.consent({userToken:'b'.repeat(64)});
  assert.equal(result.granted,true);
  assert.match(call.url,/\/v1\/grants\/consent$/);
  assert.equal(call.options.headers['X-Shine-App-Token'],'a'.repeat(64));
  assert.equal(call.options.headers['X-Shine-User-Token'],'b'.repeat(64));
  const body=JSON.stringify(call.body);
  assert.equal(body.includes('a'.repeat(64)),false);
  assert.equal(body.includes('b'.repeat(64)),false);
  assert.equal(Object.hasOwn(call.body,'shineId'),false);
  assert.equal(call.body.consent,true);
});

test('JWT consent uses bearer authentication without identity values in body',async()=>{
  let call;
  const client=createGrantConsentClient({
    ...baseOptions,
    fetchImpl:async(url,options)=>{
      call={url:String(url),options};
      return Response.json({status:'already-granted',reasonCode:'grant-already-active'});
    }
  });
  const result=await client.consent({userJwt:'jwt-value'});
  assert.equal(result.granted,true);
  assert.equal(call.options.headers.Authorization,'Bearer jwt-value');
  assert.equal(Object.hasOwn(JSON.parse(call.options.body),'shineId'),false);
});

test('exactly one user credential is required',async()=>{
  const client=createGrantConsentClient({...baseOptions,fetchImpl:async()=>Response.json({})});
  await assert.rejects(()=>client.consent({}),/exactly one user credential/);
  await assert.rejects(()=>client.consent({userJwt:'jwt',userToken:'token'}),/exactly one user credential/);
});

test('denial does not report a grant',async()=>{
  const client=createGrantConsentClient({
    ...baseOptions,
    fetchImpl:async()=>Response.json({status:'denied',reasonCode:'scope-not-declared'},{status:403})
  });
  const result=await client.consent({userToken:'session'});
  assert.equal(result.granted,false);
  assert.equal(result.reasonCode,'scope-not-declared');
});

test('network failure is unavailable, never granted',async()=>{
  const client=createGrantConsentClient({...baseOptions,fetchImpl:async()=>{throw new Error('offline')}});
  const result=await client.consent({userToken:'session'});
  assert.deepEqual(result,{granted:false,status:'unavailable',reasonCode:'grant-consent-unavailable',httpStatus:null});
});
