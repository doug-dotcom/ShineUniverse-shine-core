import test from 'node:test';
import assert from 'node:assert/strict';
import {createFoundationHttpHandler} from './http-handler-v1.mjs';

const base='https://foundation.example.test';
const reviewed='a'.repeat(40),profile='b'.repeat(40);
let authCalls=0;
const handler=createFoundationHttpHandler({
  authenticate:async request=>{
    authCalls++;
    if(request.headers.get('authorization')!=='Bearer good') throw new Error('bad auth');
    return {verified:true};
  },
  defenceStatus:({appId,releaseSha,profileBlobSha})=>({
    defenceStatus:'shine-defence/public-release-status-v1',schemaVersion:'1.0.0',
    appId,state:releaseSha===reviewed&&profileBlobSha===profile?'reviewed_release':'unreviewed_revision',
    badgeCurrent:releaseSha===reviewed&&profileBlobSha===profile,
    display:'status'
  }),
  identityClaim:async({envelope})=>({
    identityClaimResponse:'shine-foundation/identity-claim-response-v1',
    schemaVersion:'1.0.0',claimId:envelope.claimId??null,appId:envelope.appId??null,
    status:'linked',reasonCode:'identity-linked'
  }),
  gateway:async({envelope})=>({
    gatewayResponse:'shine-foundation/gateway-response-v1',schemaVersion:'1.0.0',
    traceId:envelope.traceId,requestId:envelope.permission?.requestId??null,
    status:'allowed',reasonCode:'grant-match',
    decision:{decision:'allow',reasonCode:'grant-match'}
  })
});

test('health endpoint is cache-disabled',async()=>{
  const res=await handler(new Request(base+'/health'));
  assert.equal(res.status,200);
  assert.equal(res.headers.get('cache-control'),'no-store');
});

test('Supabase function-prefixed path works',async()=>{
  assert.equal((await handler(new Request(base+'/foundation-gateway/health'))).status,200);
});

test('public Defence status needs no user or app authentication',async()=>{
  authCalls=0;
  const res=await handler(new Request(base+'/v1/defence/status/shine-daash?releaseSha='+reviewed+'&profileBlobSha='+profile));
  assert.equal(res.status,200);assert.equal(authCalls,0);
  assert.equal(res.headers.get('cache-control'),'no-store');
  const body=await res.json();assert.equal(body.state,'reviewed_release');assert.equal(body.badgeCurrent,true);
});

test('function-prefixed Defence status path works',async()=>{
  const res=await handler(new Request(base+'/foundation-gateway/v1/defence/status/shine-daash?releaseSha='+reviewed+'&profileBlobSha='+profile));
  assert.equal(res.status,200);
});

test('Defence status validates exact SHA inputs',async()=>{
  const res=await handler(new Request(base+'/v1/defence/status/shine-daash?releaseSha=no&profileBlobSha='+profile));
  assert.equal(res.status,400);
});

test('Defence status accepts GET only',async()=>{
  const res=await handler(new Request(base+'/v1/defence/status/shine-daash?releaseSha='+reviewed+'&profileBlobSha='+profile,{method:'POST'}));
  assert.equal(res.status,405);
});

test('only POST is accepted for access evaluation',async()=>{
  assert.equal((await handler(new Request(base+'/v1/access/evaluate',{method:'GET'}))).status,405);
});

test('JSON is required',async()=>{
  const res=await handler(new Request(base+'/v1/access/evaluate',{
    method:'POST',headers:{authorization:'Bearer good','content-type':'text/plain'},body:'x'
  }));
  assert.equal(res.status,415);
});

test('oversized bodies are rejected before gateway',async()=>{
  const small=createFoundationHttpHandler({
    gateway:async()=>{throw new Error('must not run')},authenticate:async()=>({}),maxBodyBytes:32
  });
  const res=await small(new Request(base+'/v1/access/evaluate',{
    method:'POST',headers:{'content-type':'application/json'},
    body:JSON.stringify({value:'x'.repeat(100)})
  }));
  assert.equal(res.status,413);
});

test('authentication is required for access evaluation',async()=>{
  const res=await handler(new Request(base+'/v1/access/evaluate',{
    method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({traceId:'x'})
  }));
  assert.equal(res.status,401);
});

test('allowed decisions map to HTTP 200',async()=>{
  const res=await handler(new Request(base+'/foundation-gateway/v1/access/evaluate',{
    method:'POST',
    headers:{authorization:'Bearer good','content-type':'application/json'},
    body:JSON.stringify({traceId:'t',permission:{requestId:'r'}})
  }));
  assert.equal(res.status,200);
});

test('identity claim endpoint is authenticated and maps linked result to HTTP 200',async()=>{
  const res=await handler(new Request(base+'/foundation-gateway/v1/identity/claim',{
    method:'POST',
    headers:{authorization:'Bearer good','content-type':'application/json'},
    body:JSON.stringify({claimId:'c',appId:'shine.ski'})
  }));
  assert.equal(res.status,200);
  assert.equal((await res.json()).status,'linked');
});

test('identity claim conflicts map to HTTP 409',async()=>{
  const conflict=createFoundationHttpHandler({
    gateway:async()=>({status:'invalid'}),
    authenticate:async()=>({}),
    identityClaim:async()=>({status:'conflict',reasonCode:'identity-claim-conflict'})
  });
  const res=await conflict(new Request(base+'/v1/identity/claim',{
    method:'POST',headers:{'content-type':'application/json'},body:'{}'
  }));
  assert.equal(res.status,409);
});
