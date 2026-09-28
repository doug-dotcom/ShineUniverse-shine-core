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


test('explicit grant consent uses normal dual authentication and maps success to HTTP 200',async()=>{
  let auth=0;
  const consentHandler=createFoundationHttpHandler({
    gateway:async()=>{throw new Error('access gateway must not run')},
    authenticate:async request=>{
      auth++;
      if(request.headers.get('x-shine-app-token')!=='app') throw new Error('missing app');
      if(request.headers.get('x-shine-user-token')!=='user') throw new Error('missing user');
      return {appToken:'app',userToken:'user'};
    },
    grantConsent:async({envelope})=>({
      grantConsentResponse:'shine-foundation/grant-consent-response-v1',
      schemaVersion:'1.0.0',
      requestId:envelope.requestId,
      status:'granted',
      reasonCode:'grant-consent-recorded'
    })
  });
  const res=await consentHandler(new Request(base+'/foundation-gateway/v1/grants/consent',{
    method:'POST',
    headers:{
      'x-shine-app-token':'app',
      'x-shine-user-token':'user',
      'content-type':'application/json'
    },
    body:JSON.stringify({requestId:'11111111-1111-4111-8111-111111111111'})
  }));
  assert.equal(res.status,200);
  assert.equal(auth,1);
  assert.equal((await res.json()).status,'granted');
});

test('grant consent denial maps to HTTP 403',async()=>{
  const consentHandler=createFoundationHttpHandler({
    gateway:async()=>({status:'allowed'}),
    authenticate:async()=>({}),
    grantConsent:async()=>({status:'denied',reasonCode:'scope-not-declared'})
  });
  const res=await consentHandler(new Request(base+'/v1/grants/consent',{
    method:'POST',headers:{'content-type':'application/json'},body:'{}'
  }));
  assert.equal(res.status,403);
});


test('explicit grant revocation uses normal dual authentication and maps success to HTTP 200',async()=>{
  let auth=0;
  const revokeHandler=createFoundationHttpHandler({
    gateway:async()=>{throw new Error('access gateway must not run')},
    authenticate:async request=>{
      auth++;
      if(request.headers.get('x-shine-app-token')!=='app') throw new Error('missing app');
      if(request.headers.get('x-shine-user-token')!=='user') throw new Error('missing user');
      return {appToken:'app',userToken:'user'};
    },
    grantRevocation:async({envelope})=>({
      grantRevocationResponse:'shine-foundation/grant-revocation-response-v1',
      schemaVersion:'1.0.0',
      requestId:envelope.requestId,
      status:'revoked',
      reasonCode:'grant-revoked-by-user'
    })
  });
  const res=await revokeHandler(new Request(base+'/foundation-gateway/v1/grants/revoke',{
    method:'POST',
    headers:{
      'x-shine-app-token':'app',
      'x-shine-user-token':'user',
      'content-type':'application/json'
    },
    body:JSON.stringify({requestId:'11111111-1111-4111-8111-111111111111'})
  }));
  assert.equal(res.status,200);
  assert.equal(auth,1);
  assert.equal((await res.json()).status,'revoked');
});

test('grant revocation denial maps to HTTP 403',async()=>{
  const revokeHandler=createFoundationHttpHandler({
    gateway:async()=>({status:'allowed'}),
    authenticate:async()=>({}),
    grantRevocation:async()=>({status:'denied',reasonCode:'grant-not-found'})
  });
  const res=await revokeHandler(new Request(base+'/v1/grants/revoke',{
    method:'POST',headers:{'content-type':'application/json'},body:'{}'
  }));
  assert.equal(res.status,403);
});


test('revocation feed GET uses app-only authentication and query cursors',async()=>{
  let appAuth=0;
  const h=createFoundationHttpHandler({
    gateway:async()=>({status:'allowed'}),
    authenticate:async()=>{throw new Error('user auth must not run')},
    authenticateApp:async request=>{
      appAuth++;
      if(request.headers.get('x-shine-app-token')!=='app') throw new Error('missing app');
      return {appToken:'app'};
    },
    revocationFeed:async args=>({
      revocationFeedResponse:'shine-foundation/revocation-feed-response-v1',
      schemaVersion:'1.0.0',status:'ok',
      appId:args.appId,afterSequence:args.afterSequence,nextCursor:7,
      hasMore:false,deliveryId:'11111111-1111-4111-8111-111111111111',events:[]
    })
  });
  const res=await h(new Request(base+'/foundation-gateway/v1/revocations?appId=shine.ski&after=6&limit=25',{
    headers:{'x-shine-app-token':'app'}
  }));
  assert.equal(res.status,200);
  assert.equal(appAuth,1);
  const body=await res.json();
  assert.equal(body.appId,'shine.ski');
  assert.equal(body.afterSequence,6);
});

test('revocation status GET uses app-only authentication',async()=>{
  const h=createFoundationHttpHandler({
    gateway:async()=>({status:'allowed'}),
    authenticate:async()=>({}),
    authenticateApp:async()=>({appToken:'app'}),
    revocationHealth:async()=>({
      revocationHealthResponse:'shine-foundation/revocation-health-response-v1',
      schemaVersion:'1.0.0',status:'ok',appId:'shine.ski',freshnessState:'current'
    })
  });
  const res=await h(new Request(base+'/v1/revocations/status?appId=shine.ski',{
    headers:{'x-shine-app-token':'app'}
  }));
  assert.equal(res.status,200);
  assert.equal((await res.json()).freshnessState,'current');
});

test('revocation acknowledgement uses app-only authentication and maps success to 200',async()=>{
  let userAuth=0;
  const h=createFoundationHttpHandler({
    gateway:async()=>({status:'allowed'}),
    authenticate:async()=>{userAuth++;return {}},
    authenticateApp:async()=>({appToken:'app'}),
    revocationAck:async({envelope})=>({
      revocationAckResponse:'shine-foundation/revocation-ack-response-v1',
      schemaVersion:'1.0.0',requestId:envelope.requestId,
      status:'acknowledged',reasonCode:'revocation-checkpoint-advanced',checkpointSequence:7
    })
  });
  const res=await h(new Request(base+'/v1/revocations/ack',{
    method:'POST',
    headers:{'x-shine-app-token':'app','content-type':'application/json'},
    body:JSON.stringify({requestId:'11111111-1111-4111-8111-111111111111'})
  }));
  assert.equal(res.status,200);
  assert.equal(userAuth,0);
  assert.equal((await res.json()).checkpointSequence,7);
});


test('capability discovery is public metadata and supports app filtering',async()=>{
  let normalAuth=0,appAuth=0,seenAppId;
  const discoveryHandler=createFoundationHttpHandler({
    gateway:async()=>({status:'allowed'}),
    authenticate:async()=>{normalAuth++;throw new Error('must not authenticate')},
    authenticateApp:async()=>{appAuth++;throw new Error('must not authenticate app')},
    capabilityDiscovery:async({appId})=>{
      seenAppId=appId;
      return {
        capabilityDiscoveryResponse:'shine-foundation/capability-discovery-response-v1',
        schemaVersion:'1.0.0',
        integrationProtocol:'shine-foundation/open-integration-v1',
        status:'ok',
        companionAgnostic:true,
        executionRequiresAuthorization:true,
        appId,
        capabilities:[{capabilityId:'travel.plan_trip',invocable:false}]
      };
    }
  });
  const res=await discoveryHandler(new Request(base+'/foundation-gateway/v1/integration/capabilities?appId=shine.travel'));
  assert.equal(res.status,200);
  assert.equal(normalAuth,0);
  assert.equal(appAuth,0);
  assert.equal(seenAppId,'shine.travel');
  const body=await res.json();
  assert.equal(body.executionRequiresAuthorization,true);
  assert.equal(body.capabilities[0].invocable,false);
});

test('capability discovery maps invalid catalogue requests to 400',async()=>{
  const discoveryHandler=createFoundationHttpHandler({
    gateway:async()=>({status:'allowed'}),
    authenticate:async()=>({}),
    capabilityDiscovery:async()=>({status:'invalid',reasonCode:'invalid-app-id'})
  });
  const res=await discoveryHandler(new Request(base+'/v1/integration/capabilities?appId=BAD'));
  assert.equal(res.status,400);
});

test('integration client status requires client-only authentication',async()=>{
  let clientAuth=0,normalAuth=0,appAuth=0;
  const clientStatusHandler=createFoundationHttpHandler({
    gateway:async()=>({status:'allowed'}),
    authenticate:async()=>{normalAuth++;return {}},
    authenticateApp:async()=>{appAuth++;return {}},
    authenticateIntegrationClient:async request=>{
      clientAuth++;
      if(request.headers.get('x-shine-client-token')!=='client-secret') throw new Error('missing client');
      return {clientToken:'client-secret'};
    },
    integrationClientStatus:async({clientId,authContext})=>({
      integrationClientStatusResponse:'shine-foundation/integration-client-status-response-v1',
      schemaVersion:'1.0.0',
      integrationProtocol:'shine-foundation/open-integration-v1',
      status:'ok',
      clientId,
      clientKind:'first-party-companion',
      authenticated:authContext.clientToken==='client-secret',
      supportedOperations:['capabilities.discover']
    })
  });

  const res=await clientStatusHandler(new Request(
    base+'/foundation-gateway/v1/integration/client/status?clientId=shine.companion',
    {headers:{'x-shine-client-token':'client-secret'}}
  ));
  assert.equal(res.status,200);
  assert.equal(clientAuth,1);
  assert.equal(normalAuth,0);
  assert.equal(appAuth,0);
  const body=await res.json();
  assert.equal(body.clientId,'shine.companion');
  assert.equal(body.authenticated,true);
  assert.deepEqual(body.supportedOperations,['capabilities.discover']);
});

test('integration client status rejects missing client credential',async()=>{
  const clientStatusHandler=createFoundationHttpHandler({
    gateway:async()=>({status:'allowed'}),
    authenticate:async()=>({}),
    authenticateIntegrationClient:async()=>{throw new Error('missing')},
    integrationClientStatus:async()=>({status:'ok'})
  });
  const res=await clientStatusHandler(new Request(
    base+'/v1/integration/client/status?clientId=shine.companion'
  ));
  assert.equal(res.status,401);
});

test('integration client status maps client mismatch denial to 403',async()=>{
  const clientStatusHandler=createFoundationHttpHandler({
    gateway:async()=>({status:'allowed'}),
    authenticate:async()=>({}),
    authenticateIntegrationClient:async()=>({clientToken:'secret'}),
    integrationClientStatus:async()=>({
      status:'denied',
      reasonCode:'integration-client-mismatch'
    })
  });
  const res=await clientStatusHandler(new Request(
    base+'/v1/integration/client/status?clientId=shine.companion',
    {headers:{'x-shine-client-token':'secret'}}
  ));
  assert.equal(res.status,403);
});

test('app operational status uses app-only authentication',async()=>{
  let appAuth=0,normalAuth=0;
  const statusHandler=createFoundationHttpHandler({
    gateway:async()=>({status:'allowed'}),
    authenticate:async()=>{normalAuth++;return {}},
    authenticateApp:async request=>{
      appAuth++;
      if(request.headers.get('x-shine-app-token')!=='app') throw new Error('missing app');
      return {appToken:'app'};
    },
    appOperationalStatus:async({appId})=>({
      appOperationalStatusResponse:'shine-foundation/app-operational-status-response-v1',
      schemaVersion:'1.0.0',status:'ok',appId,
      operationalStatus:{operationalState:'revocation-pending',operationalHealth:'attention'}
    })
  });
  const res=await statusHandler(new Request(base+'/foundation-gateway/v1/status?appId=shine.ski',{
    headers:{'x-shine-app-token':'app'}
  }));
  assert.equal(res.status,200);
  assert.equal(appAuth,1);
  assert.equal(normalAuth,0);
  assert.equal((await res.json()).operationalStatus.operationalHealth,'attention');
});

test('app operational status rejects missing app credential',async()=>{
  const statusHandler=createFoundationHttpHandler({
    gateway:async()=>({status:'allowed'}),authenticate:async()=>({}),
    authenticateApp:async()=>{throw new Error('missing')},
    appOperationalStatus:async()=>({status:'ok'})
  });
  const res=await statusHandler(new Request(base+'/v1/status?appId=shine.ski'));
  assert.equal(res.status,401);
});

test('required operation policy denies privileged POST before authentication or service execution',async()=>{
  let auth=0,service=0,policyCalls=0;
  const h=createFoundationHttpHandler({
    gateway:async()=>({status:'allowed'}),
    authenticate:async()=>{auth++;return {}},
    grantConsent:async()=>{service++;return {status:'granted'}},
    evaluateOperationPolicy:async({method,path})=>{
      policyCalls++;
      assert.equal(method,'POST');
      assert.equal(path,'/v1/grants/consent');
      return {policyState:'deny',reasonCode:'dependency-guarded'};
    },
    operationPolicyRequired:true
  });

  const res=await h(new Request(base+'/v1/grants/consent',{
    method:'POST',
    headers:{'content-type':'application/json'},
    body:'{}'
  }));

  assert.equal(res.status,403);
  assert.equal(policyCalls,1);
  assert.equal(auth,0);
  assert.equal(service,0);
  assert.equal((await res.json()).reasonCode,'dependency-guarded');
});

test('required operation policy unavailable fails privileged POST closed',async()=>{
  const h=createFoundationHttpHandler({
    gateway:async()=>({status:'allowed'}),
    authenticate:async()=>({}),
    grantRevocation:async()=>({status:'revoked'}),
    evaluateOperationPolicy:async()=>({
      policyState:'unavailable',
      reasonCode:'dependency-graph-invalid'
    }),
    operationPolicyRequired:true
  });

  const res=await h(new Request(base+'/v1/grants/revoke',{
    method:'POST',
    headers:{'content-type':'application/json'},
    body:'{}'
  }));

  assert.equal(res.status,503);
  assert.equal((await res.json()).reasonCode,'dependency-graph-invalid');
});

test('worker-only operation policy continues to worker route authentication',async()=>{
  let clientAuth=0,claimCalls=0;
  const h=createFoundationHttpHandler({
    gateway:async()=>({status:'allowed'}),
    authenticate:async()=>({}),
    authenticateIntegrationClient:async()=>{
      clientAuth++;
      return {clientToken:'worker'};
    },
    conciergeRetry:{
      claim:async()=>{
        claimCalls++;
        return {status:'ok',reasonCode:'no-retry-due',retry:null};
      },
      finish:async()=>({status:'ok'})
    },
    evaluateOperationPolicy:async()=>({
      policyState:'worker-only',
      reasonCode:'worker-auth-required'
    }),
    operationPolicyRequired:true
  });

  const res=await h(new Request(base+'/v1/concierge/retry/claim',{
    method:'POST',
    headers:{'content-type':'application/json','x-shine-client-token':'worker'},
    body:JSON.stringify({
      conciergeRetryClaim:'shine-concierge/retry-claim-v1',
      schemaVersion:'1.0.0',
      clientId:'shine.companion'
    })
  }));

  assert.equal(res.status,200);
  assert.equal(clientAuth,1);
  assert.equal(claimCalls,1);
});

test('unregistered POST route still falls through to normal 404',async()=>{
  const h=createFoundationHttpHandler({
    gateway:async()=>({status:'allowed'}),
    authenticate:async()=>({}),
    evaluateOperationPolicy:async()=>({
      policyState:'not-registered',
      reasonCode:'operation-not-registered'
    }),
    operationPolicyRequired:true
  });

  const res=await h(new Request(base+'/v1/no-such-route',{
    method:'POST',
    headers:{'content-type':'application/json'},
    body:'{}'
  }));
  assert.equal(res.status,404);
});

test('production policy mode cannot be enabled without a broker',()=>{
  assert.throws(()=>createFoundationHttpHandler({
    gateway:async()=>({status:'allowed'}),
    authenticate:async()=>({}),
    operationPolicyRequired:true
  }),/operation policy broker is required/);
});

test('privileged operation audit records policy before auth/service and outcome after response',async()=>{
  const order=[];
  const auditEvents=[];
  const requestId='29111111-1111-4111-8111-111111111111';
  const h=createFoundationHttpHandler({
    gateway:async()=>({status:'allowed'}),
    authenticate:async()=>{order.push('authenticate');return {}},
    grantConsent:async()=>{
      order.push('service');
      return {status:'granted',reasonCode:'grant-consent-recorded',requestId};
    },
    evaluateOperationPolicy:async()=>{
      order.push('policy-evaluate');
      return {
        operationKey:'grant.consent',
        policyState:'admit',
        reasonCode:'dependency-admission-clear',
        policy:{
          policyState:'admit',
          reasonCode:'dependency-admission-clear',
          policyEvidenceRef:'foundation:operation-policy:gateway:grant-consent:v1',
          impactScope:'permission-operations',
          executionGuardRef:'foundation.issue_access_grant_v1',
          admission:{dependencyEvidence:[]}
        }
      };
    },
    operationPolicyRequired:true,
    recordOperationAudit:async event=>{
      auditEvents.push(event);
      order.push('audit-'+event.phase);
      return {status:'recorded'};
    },
    operationAuditRequired:true,
    operationAuditIdFactory:()=> '29000000-0000-4000-8000-000000009001'
  });

  const res=await h(new Request(base+'/v1/grants/consent',{
    method:'POST',
    headers:{'content-type':'application/json'},
    body:'{}'
  }));

  assert.equal(res.status,200);
  assert.deepEqual(order,[
    'policy-evaluate','audit-policy','authenticate','service','audit-outcome'
  ]);
  assert.equal(auditEvents.length,2);
  assert.equal(auditEvents[0].operationAuditId,'29000000-0000-4000-8000-000000009001');
  assert.equal(auditEvents[0].phase,'policy');
  assert.equal(auditEvents[1].phase,'outcome');
  assert.equal(auditEvents[1].httpStatus,200);
  assert.equal(auditEvents[1].responseReasonCode,'grant-consent-recorded');
  assert.equal(auditEvents[1].domainRequestId,requestId);
});

test('policy denial is audited before route execution and receives an outcome event',async()=>{
  let authCalls=0,serviceCalls=0;
  const auditEvents=[];
  const h=createFoundationHttpHandler({
    gateway:async()=>({status:'allowed'}),
    authenticate:async()=>{authCalls++;return {}},
    grantConsent:async()=>{serviceCalls++;return {status:'granted'}},
    evaluateOperationPolicy:async()=>({
      operationKey:'grant.consent',
      policyState:'deny',
      reasonCode:'dependency-guarded',
      policy:{
        policyState:'deny',
        reasonCode:'dependency-guarded',
        policyEvidenceRef:'foundation:operation-policy:gateway:grant-consent:v1',
        impactScope:'permission-operations',
        executionGuardRef:'foundation.issue_access_grant_v1',
        admission:{dependencyEvidence:[{serviceId:'foundation.defence',impact:'guarded'}]}
      }
    }),
    operationPolicyRequired:true,
    recordOperationAudit:async event=>{auditEvents.push(event);return {status:'recorded'}},
    operationAuditRequired:true,
    operationAuditIdFactory:()=> '29000000-0000-4000-8000-000000009002'
  });

  const res=await h(new Request(base+'/v1/grants/consent',{
    method:'POST',headers:{'content-type':'application/json'},body:'{}'
  }));

  assert.equal(res.status,403);
  assert.equal(authCalls,0);
  assert.equal(serviceCalls,0);
  assert.deepEqual(auditEvents.map(e=>e.phase),['policy','outcome']);
  assert.equal(auditEvents[1].responseReasonCode,'dependency-guarded');
});

test('required pre-execution audit failure fails privileged route closed',async()=>{
  let authCalls=0,serviceCalls=0;
  const h=createFoundationHttpHandler({
    gateway:async()=>({status:'allowed'}),
    authenticate:async()=>{authCalls++;return {}},
    grantRevocation:async()=>{serviceCalls++;return {status:'revoked'}},
    evaluateOperationPolicy:async()=>({
      operationKey:'grant.revoke',
      policyState:'admit',
      reasonCode:'dependency-admission-clear',
      policy:{
        policyState:'admit',
        reasonCode:'dependency-admission-clear',
        policyEvidenceRef:'foundation:operation-policy:gateway:grant-revoke:v1',
        impactScope:'permission-operations',
        executionGuardRef:'foundation.revoke_access_grant_v1',
        admission:{dependencyEvidence:[]}
      }
    }),
    operationPolicyRequired:true,
    recordOperationAudit:async()=>{throw new Error('audit down')},
    operationAuditRequired:true
  });

  const res=await h(new Request(base+'/v1/grants/revoke',{
    method:'POST',headers:{'content-type':'application/json'},body:'{}'
  }));

  assert.equal(res.status,503);
  assert.equal(authCalls,0);
  assert.equal(serviceCalls,0);
  assert.equal((await res.json()).error,'operation-audit-unavailable');
});

test('post-execution audit failure does not rewrite a completed domain response',async()=>{
  let auditCalls=0;
  const originalError=console.error;
  console.error=()=>{};
  try{
    const h=createFoundationHttpHandler({
      gateway:async()=>({status:'allowed'}),
      authenticate:async()=>({}),
      grantConsent:async()=>({
        status:'granted',
        reasonCode:'grant-consent-recorded',
        requestId:'29222222-2222-4222-8222-222222222222'
      }),
      evaluateOperationPolicy:async()=>({
        operationKey:'grant.consent',
        policyState:'admit',
        reasonCode:'dependency-admission-clear',
        policy:{
          policyState:'admit',
          reasonCode:'dependency-admission-clear',
          policyEvidenceRef:'foundation:operation-policy:gateway:grant-consent:v1',
          impactScope:'permission-operations',
          executionGuardRef:'foundation.issue_access_grant_v1',
          admission:{dependencyEvidence:[]}
        }
      }),
      operationPolicyRequired:true,
      recordOperationAudit:async event=>{
        auditCalls++;
        if(event.phase==='outcome') throw new Error('outcome audit down');
        return {status:'recorded'};
      },
      operationAuditRequired:true
    });

    const res=await h(new Request(base+'/v1/grants/consent',{
      method:'POST',headers:{'content-type':'application/json'},body:'{}'
    }));

    assert.equal(res.status,200);
    assert.equal(auditCalls,2);
    assert.equal((await res.json()).status,'granted');
  } finally {
    console.error=originalError;
  }
});

test('production audit mode cannot be enabled without an audit recorder',()=>{
  assert.throws(()=>createFoundationHttpHandler({
    gateway:async()=>({status:'allowed'}),
    authenticate:async()=>({}),
    operationAuditRequired:true
  }),/operation audit recorder is required/);
});



test('Concierge supersede route is constructor-bound and uses dual integration authentication',async()=>{
  let authCalls=0,serviceCalls=0;
  const supersedeHandler=createFoundationHttpHandler({
    gateway:async()=>({status:'allowed'}),
    authenticate:async()=>({}),
    authenticateIntegrationUserAndClient:async request=>{
      authCalls++;
      assert.equal(request.headers.get('x-shine-client-token'),'client');
      assert.equal(request.headers.get('x-shine-delegation-token'),'delegation');
      return {clientToken:'client',delegationToken:'delegation'};
    },
    conciergeSupersede:async({envelope,authContext})=>{
      serviceCalls++;
      assert.equal(envelope.conciergeSupersede,'shine-concierge/supersede-v1');
      assert.equal(authContext.clientToken,'client');
      return {
        conciergeResponse:'shine-concierge/supersede-response-v1',
        schemaVersion:'1.0.0',
        requestId:envelope.requestId,
        status:'superseded',
        reasonCode:'superseded-by-newer-request'
      };
    }
  });

  const res=await supersedeHandler(new Request(base+'/v1/concierge/supersede',{
    method:'POST',
    headers:{
      'content-type':'application/json',
      'x-shine-client-token':'client',
      'x-shine-delegation-token':'delegation'
    },
    body:JSON.stringify({
      conciergeSupersede:'shine-concierge/supersede-v1',
      schemaVersion:'1.0.0',
      requestId:'11111111-1111-4111-8111-111111111111',
      supersededByRequestId:'22222222-2222-4222-8222-222222222222',
      clientId:'shine.companion',
      requestedAt:new Date().toISOString()
    })
  }));

  assert.equal(res.status,200);
  assert.equal(authCalls,1);
  assert.equal(serviceCalls,1);
  assert.equal((await res.json()).reasonCode,'superseded-by-newer-request');
});
