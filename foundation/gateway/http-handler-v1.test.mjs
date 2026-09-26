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


test('identity claim requires its separate three-credential authenticator',async()=>{
  let accessAuth=0,claimAuth=0;
  const claimHandler=createFoundationHttpHandler({
    gateway:async()=>{throw new Error('access gateway must not run')},
    authenticate:async()=>{accessAuth++;return {}},
    authenticateIdentityClaim:async request=>{
      claimAuth++;
      if(request.headers.get('authorization')!=='Bearer target') throw new Error('target jwt missing');
      if(request.headers.get('x-shine-user-token')!=='source') throw new Error('source token missing');
      if(request.headers.get('x-shine-app-token')!=='app') throw new Error('app token missing');
      return {targetJwt:'target',sourceUserToken:'source',appToken:'app'};
    },
    identityClaim:async({envelope})=>({
      identityClaimResponse:'shine-foundation/identity-claim-response-v1',
      schemaVersion:'1.0.0',
      requestId:envelope.requestId,
      status:'linked',
      reasonCode:'identity-claim-linked'
    })
  });

  const res=await claimHandler(new Request(base+'/foundation-gateway/v1/identity/claim',{
    method:'POST',
    headers:{
      authorization:'Bearer target',
      'x-shine-user-token':'source',
      'x-shine-app-token':'app',
      'content-type':'application/json'
    },
    body:JSON.stringify({requestId:'11111111-1111-4111-8111-111111111111'})
  }));

  assert.equal(res.status,200);
  assert.equal(accessAuth,0);
  assert.equal(claimAuth,1);
  assert.equal((await res.json()).status,'linked');
});

test('identity claim missing one proof is unauthenticated',async()=>{
  const claimHandler=createFoundationHttpHandler({
    gateway:async()=>({status:'allowed'}),
    authenticate:async()=>({}),
    authenticateIdentityClaim:async request=>{
      if(!request.headers.get('authorization')||!request.headers.get('x-shine-user-token')||!request.headers.get('x-shine-app-token')){
        throw new Error('missing proof');
      }
      return {};
    },
    identityClaim:async()=>({status:'linked'})
  });

  const res=await claimHandler(new Request(base+'/v1/identity/claim',{
    method:'POST',
    headers:{
      'x-shine-user-token':'source',
      'x-shine-app-token':'app',
      'content-type':'application/json'
    },
    body:'{}'
  }));
  assert.equal(res.status,401);
});

test('identity claim denied maps to HTTP 403 without exposing identity details',async()=>{
  const claimHandler=createFoundationHttpHandler({
    gateway:async()=>({status:'allowed'}),
    authenticate:async()=>({}),
    authenticateIdentityClaim:async()=>({}),
    identityClaim:async()=>({
      identityClaimResponse:'shine-foundation/identity-claim-response-v1',
      schemaVersion:'1.0.0',
      requestId:'11111111-1111-4111-8111-111111111111',
      status:'denied',
      reasonCode:'source-already-bound'
    })
  });
  const res=await claimHandler(new Request(base+'/v1/identity/claim',{
    method:'POST',
    headers:{'content-type':'application/json'},
    body:'{}'
  }));
  assert.equal(res.status,403);
  const body=await res.json();
  assert.equal(Object.hasOwn(body,'shineId'),false);
  assert.equal(Object.hasOwn(body,'providerSubject'),false);
});
