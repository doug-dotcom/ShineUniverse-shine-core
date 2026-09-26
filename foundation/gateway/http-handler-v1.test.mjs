import test from 'node:test';
import assert from 'node:assert/strict';
import {createFoundationHttpHandler} from './http-handler-v1.mjs';

const base='https://foundation.example.test';

const handler=createFoundationHttpHandler({
  authenticate:async request=>{
    if(request.headers.get('authorization')!=='Bearer good') throw new Error('bad auth');
    return {verified:true};
  },
  gateway:async({envelope})=>({
    gatewayResponse:'shine-foundation/gateway-response-v1',
    schemaVersion:'1.0.0',
    traceId:envelope.traceId,
    requestId:envelope.permission?.requestId ?? null,
    status:'allowed',
    reasonCode:'grant-match',
    decision:{decision:'allow',reasonCode:'grant-match'}
  })
});

test('health endpoint is small and cache-disabled',async()=>{
  const res=await handler(new Request(base+'/health'));
  assert.equal(res.status,200);
  assert.equal(res.headers.get('cache-control'),'no-store');
});

test('only POST is accepted for evaluation',async()=>{
  const res=await handler(new Request(base+'/v1/access/evaluate',{method:'GET'}));
  assert.equal(res.status,405);
});

test('JSON is required',async()=>{
  const res=await handler(new Request(base+'/v1/access/evaluate',{
    method:'POST',
    headers:{authorization:'Bearer good','content-type':'text/plain'},
    body:'x'
  }));
  assert.equal(res.status,415);
});

test('authentication is required',async()=>{
  const res=await handler(new Request(base+'/v1/access/evaluate',{
    method:'POST',
    headers:{'content-type':'application/json'},
    body:JSON.stringify({traceId:'x'})
  }));
  assert.equal(res.status,401);
});

test('allowed gateway decisions map to HTTP 200',async()=>{
  const res=await handler(new Request(base+'/v1/access/evaluate',{
    method:'POST',
    headers:{authorization:'Bearer good','content-type':'application/json'},
    body:JSON.stringify({traceId:'t',permission:{requestId:'r'}})
  }));
  assert.equal(res.status,200);
});
