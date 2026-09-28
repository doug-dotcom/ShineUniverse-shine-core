import test from 'node:test';
import assert from 'node:assert/strict';
import {createSupabaseRuntimeAdapters,sha256Hex} from './supabase-runtime-adapters-v1.mjs';
import {createFoundationRuntimeDefenceGateV1} from './runtime-defence-gate-v1.mjs';

const shineId='11111111-1111-4111-8111-111111111111';
const resourceId='22222222-2222-4222-8222-222222222222';
const grantId='33333333-3333-4333-8333-333333333333';
const issuer='https://identity.example.test/auth/v1';
const jwt=(payload)=>'eyJhbGciOiJub25lIn0.'+Buffer.from(JSON.stringify(payload)).toString('base64url')+'.sig';

const makeSql=()=> {
  const audit=[];
  const sql=async(strings,...values)=>{
    const q=strings.join('?').replace(/\s+/g,' ').trim().toLowerCase();
    if(q.includes('from foundation.effective_integration_client_credentials')){
      return [{
        credential_id:'99999999-9999-4999-8999-999999999999',
        client_id:'shine.companion',
        client_kind:'first-party-companion'
      }];
    }
    if(q.includes('from foundation.effective_app_credentials')){
      return values[0]==='4c0ffa9a073e5e47ee51e8352cee4b05d0c21f75b501e314e2ffae28fd635909'
        ? [{credential_id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',app_id:'shine.travel'}] : [];
    }
    if(q.includes('from foundation.identity_providers')){
      if(q.includes('join foundation.app_claim_identity_providers')){
        return values[0]==='supabase:test' && values[1]===issuer && values[2]==='shine.ski'
          ? [{provider_id:'supabase:test',kind:'supabase-auth',project_url:'https://identity.example.test',publishable_key:'public-key'}]
          : [];
      }
      if(q.includes("p.kind='supabase-auth'")){
        return values[0]===issuer && values[1]==='shine.travel'
          ? [{provider_id:'supabase:test',kind:'supabase-auth',project_url:'https://identity.example.test',publishable_key:'public-key'}]
          : [];
      }
      if(q.includes("p.kind='supabase-opaque-vault'")){
        if(q.includes('p.provider_id=?')){
          return values[0]==='supabase:ski-session' && values[1]==='shine.ski'
            ? [{provider_id:'supabase:ski-session',kind:'supabase-opaque-vault',project_url:'https://ski.example.test',publishable_key:'public-key',verification_resource:'ski_foundation_sessions',subject_field:'session_hash',token_header:'x-shine-ski-token'}]
            : [];
        }
        return values[0]==='shine.dive'
          ? [{provider_id:'supabase:dive-vault',kind:'supabase-opaque-vault',project_url:'https://dive.example.test',publishable_key:'public-key',verification_resource:'dive_companions',subject_field:'vault_hash',token_header:'x-shine-vault-token'}]
          : [];
      }
    }
    if(q.includes('from foundation.identity_bindings')) return [{shine_id:shineId}];
    if(q.includes('from foundation.complete_identity_claim_v1')){
      return [{outcome:'linked',reason_code:'identity-claim-linked'}];
    }
    if(q.includes('from foundation.issue_access_grant_v1')){
      return [{outcome:'granted',reason_code:'grant-consent-recorded',grant_id:grantId}];
    }
    if(q.includes('from foundation.revoke_access_grant_v1')){
      return [{outcome:'revoked',reason_code:'grant-revoked-by-user',revocation_id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'}];
    }
    if(q.includes('from foundation.list_app_revocations_v1')){
      return [{sequence_no:7,event_payload:{event:'shine-foundation/grant-revocation-v1'},created_at:'2026-09-27T13:20:00Z'}];
    }
    if(q.includes('from foundation.record_app_revocation_delivery_v1')){
      return [{delivery_id:'dddddddd-dddd-4ddd-8ddd-dddddddddddd',terminal_sequence:7,event_count:1}];
    }
    if(q.includes('from foundation.ack_app_revocations_v2')){
      return [{outcome:'advanced',reason_code:'revocation-checkpoint-advanced',checkpoint_sequence:7}];
    }
    if(q.includes('from foundation.get_app_revocation_status_v1')){
      return [{checkpoint_sequence:6,last_ack_at:'2026-09-27T13:00:00Z',latest_sequence:7,pending_count:1,oldest_pending_at:'2026-09-27T13:20:00Z'}];
    }
    if(q.includes('from foundation.get_app_revocation_health_v1')){
      return [{app_id:'shine.travel',checkpoint_sequence:6,latest_sequence:7,pending_count:1,oldest_pending_at:'2026-09-27T13:20:00Z',pending_age_seconds:600,max_pending_age_seconds:900,freshness_state:'pending',stale_action:'observe',recommended_action:'consume-revocations'}];
    }
    if(q.includes('foundation.list_discoverable_capabilities_v1')){
      return [{capabilities:[{
        capabilityId:'travel.plan_trip',
        appId:'shine.travel',
        invocationState:'declared',
        invocable:false
      }]}];
    }
    if(q.includes('foundation.get_app_operational_status_v1')){
      return [{status:{appId:'shine.travel',operationalState:'revocation-pending',operationalHealth:'attention'}}];
    }
    if(q.includes('foundation.evaluate_gateway_route_policy_v1')){
      return [{policy:{
        gatewayRoutePolicyResponse:'shine-foundation/gateway-route-policy-response-v1',
        schemaVersion:'1.0.0',
        environment:'production',
        method:'POST',
        path:'/v1/grants/consent',
        routeSymbol:'grantConsentPath',
        operationKey:'grant.consent',
        riskClass:'permission-write',
        effectClass:'write',
        policyState:'admit',
        reasonCode:'dependency-admission-clear',
        policy:{
          policyState:'admit',
          reasonCode:'dependency-admission-clear'
        }
      }}];
    }
    if(q.includes('foundation.evaluate_gateway_operation_policy_v1')){
      return [{policy:{
        gatewayOperationPolicyResponse:'shine-foundation/gateway-operation-policy-response-v1',
        schemaVersion:'1.0.0',
        operationKey:'access.evaluate',
        environment:'production',
        policyState:'admit',
        reasonCode:'dependency-admission-clear',
        policyEvidenceRef:'foundation:operation-policy:gateway:access-evaluate:v1',
        admission:{
          serviceId:'foundation.gateway',
          environment:'production',
          operation:'access.evaluate',
          impactScope:'protected-operations',
          admissionState:'admit',
          reasonCode:'dependency-admission-clear',
          ownState:'operational',
          effectiveState:'operational',
          safeMode:'normal',
          bindingEvidenceRef:'foundation:admission-binding:gateway:access-evaluate:v1',
          dependencyEvidence:[]
        }
      }}];
    }
    if(q.includes('from foundation.app_registry')){
      return [{manifest:{appId:'shine.travel',foundation:{requestedScopes:[]}}}];
    }
    if(q.includes('from foundation.vault_resources')){
      return [{resource_id:resourceId,owner_shine_id:shineId,category:'foundation.pilot',
        sensitivity:'personal',content_type:'application/json',storage_ref:'foundation://pilot'}];
    }
    if(q.includes('from foundation.effective_access_grants')){
      return [{grant_id:grantId,owner_shine_id:shineId,app_id:'shine.travel',
        scope:'vault.foundation.pilot.read',purpose:'travel.foundation-pilot',resource_id:resourceId,
        resource_category:null,effective_status:'active',issued_at:'2026-09-01T00:00:00Z',
        not_before:null,expires_at:'2026-12-01T00:00:00Z',revoked_at:null}];
    }
    if(q.startsWith('insert into foundation.access_audit_events')){
      audit.push({values});
      return [{request_id:'44444444-4444-4444-8444-444444444444'}];
    }
    if(q.includes('from foundation.access_audit_events')) return [];
    throw new Error('unexpected SQL: '+q);
  };
  return {sql,audit};
};

const makeAdapters=({fetchImpl}={})=>{
  const {sql,audit}=makeSql();
  return {
    audit,
    adapters:createSupabaseRuntimeAdapters({
      sql,
      fetchImpl:fetchImpl??(async(url,options)=>{
        assert.equal(url,'https://identity.example.test/auth/v1/user');
        assert.equal(options.headers.apikey,'public-key');
        return Response.json({id:'auth-user'});
      }),
      defenceGate:createFoundationRuntimeDefenceGateV1()
    })
  };
};

test('hashes app credentials without retaining raw token',async()=>{
  assert.equal(await sha256Hex('travel-test-secret'),
    '4c0ffa9a073e5e47ee51e8352cee4b05d0c21f75b501e314e2ffae28fd635909');
});

test('verifies registered integration client against active hashed credential',async()=>{
  const {adapters}=makeAdapters();
  const result=await adapters.verifyIntegrationClient({
    authContext:{clientToken:'integration-test-secret'},
    claimedClientId:'shine.companion'
  });
  assert.deepEqual(result,{
    clientId:'shine.companion',
    credentialId:'99999999-9999-4999-8999-999999999999',
    clientKind:'first-party-companion'
  });
});

test('integration client verification requires both token and claimed client id',async()=>{
  const {adapters}=makeAdapters();
  assert.equal(await adapters.verifyIntegrationClient({
    authContext:{},claimedClientId:'shine.companion'
  }),null);
  assert.equal(await adapters.verifyIntegrationClient({
    authContext:{clientToken:'integration-test-secret'},claimedClientId:''
  }),null);
});

test('verifies app caller against active hashed credential',async()=>{
  const {adapters}=makeAdapters();
  const result=await adapters.verifyAppCaller({
    authContext:{appToken:'travel-test-secret'},claimedAppId:'shine.travel'
  });
  assert.equal(result.appId,'shine.travel');
});

test('registered external issuer verifies user then maps canonical Shine ID',async()=>{
  const {adapters}=makeAdapters();
  const token=jwt({iss:issuer,sub:'auth-user',session_id:'session-1'});
  const result=await adapters.verifyIdentity({authContext:{jwt:token},claimedAppId:'shine.travel'});
  assert.equal(result.shineId,shineId);
  assert.equal(result.authSubject,'auth-user');
  assert.equal(result.providerId,'supabase:test');
  assert.equal(result.sessionId,'session-1');
});

test('unregistered issuer is denied without contacting external Auth',async()=>{
  let calls=0;
  const {adapters}=makeAdapters({fetchImpl:async()=>{calls++;return Response.json({id:'x'})}});
  const result=await adapters.verifyIdentity({
    authContext:{jwt:jwt({iss:'https://evil.example/auth/v1',sub:'x'})},claimedAppId:'shine.travel'
  });
  assert.equal(result,null);
  assert.equal(calls,0);
});

test('registered issuer token rejected by provider is not mapped',async()=>{
  const {adapters}=makeAdapters({fetchImpl:async()=>new Response('{}',{status:401})});
  const result=await adapters.verifyIdentity({authContext:{jwt:jwt({iss:issuer,sub:'auth-user'})},claimedAppId:'shine.travel'});
  assert.equal(result,null);
});

test('reads Vault metadata and effective grants without Vault content',async()=>{
  const {adapters}=makeAdapters();
  const resource=await adapters.getVaultResource({resourceId,ownerShineId:shineId});
  const grants=await adapters.getEffectiveGrants({
    shineId,appId:'shine.travel',scope:'vault.foundation.pilot.read',purpose:'travel.foundation-pilot'
  });
  assert.equal(resource.storageRef,'foundation://pilot');
  assert.equal(Object.hasOwn(resource,'content'),false);
  assert.equal(grants[0].grantId,grantId);
});

test('runtime Defence gate rejects oversized untrusted context',async()=>{
  const gate=createFoundationRuntimeDefenceGateV1({maxContextBytes:20});
  const result=await gate({
    envelope:{permission:{context:{value:'this is definitely too large'}}},
    verifiedIdentity:{shineId},appManifest:{appId:'shine.travel'}
  });
  assert.equal(result.decision,'deny');
});

test('audit writes can record pre-identity denial with null Shine ID',async()=>{
  const {adapters,audit}=makeAdapters();
  await adapters.writeAuditEvent({
    eventId:'55555555-5555-4555-8555-555555555555',
    requestId:'44444444-4444-4444-8444-444444444444',
    appId:'shine.travel',shineId:null,scope:'vault.foundation.pilot.read',
    purpose:'travel.foundation-pilot',decision:'deny',
    reasonCode:'app-caller-unverified',occurredAt:'2026-09-26T08:30:00Z'
  });
  assert.equal(audit.length,1);
});


test('registered issuer is denied when it is not linked to the requesting app',async()=>{
  let calls=0;
  const {adapters}=makeAdapters({fetchImpl:async()=>{calls++;return Response.json({id:'auth-user'})}});
  const token=jwt({iss:issuer,sub:'auth-user'});
  const result=await adapters.verifyIdentity({
    authContext:{jwt:token},
    claimedAppId:'shine.dive'
  });
  assert.equal(result,null);
  assert.equal(calls,0);
});

test('opaque Dive vault token is independently verified through provider RLS and maps to Shine ID',async()=>{
  const raw='a'.repeat(64);
  const expected=await sha256Hex(raw);
  let verified=false;
  const {sql}=makeSql();
  const adapters=createSupabaseRuntimeAdapters({
    sql,
    defenceGate:createFoundationRuntimeDefenceGateV1(),
    fetchImpl:async(url,options)=>{
      verified=true;
      const parsed=new URL(url);
      assert.equal(parsed.origin,'https://dive.example.test');
      assert.equal(parsed.pathname,'/rest/v1/dive_companions');
      assert.equal(parsed.searchParams.get('vault_hash'),'eq.'+expected);
      assert.equal(options.headers.apikey,'public-key');
      assert.equal(options.headers['x-shine-vault-token'],raw);
      return Response.json([{vault_hash:expected}]);
    }
  });
  const result=await adapters.verifyIdentity({
    authContext:{userToken:raw},
    claimedAppId:'shine.dive'
  });
  assert.equal(verified,true);
  assert.equal(result.shineId,shineId);
  assert.equal(result.authSubject,expected);
  assert.equal(result.providerId,'supabase:dive-vault');
});

test('opaque user token is rejected for an app without an opaque provider link',async()=>{
  let calls=0;
  const {adapters}=makeAdapters({fetchImpl:async()=>{calls++;return Response.json([])}});
  const result=await adapters.verifyIdentity({
    authContext:{userToken:'b'.repeat(64)},
    claimedAppId:'shine.travel'
  });
  assert.equal(result,null);
  assert.equal(calls,0);
});


test('verifies unbound claim source without requiring an existing Shine binding',async()=>{
  const raw='d'.repeat(64);
  const expected=await sha256Hex(raw);
  let called=false;
  const {sql}=makeSql();
  const adapters=createSupabaseRuntimeAdapters({
    sql,
    defenceGate:createFoundationRuntimeDefenceGateV1(),
    fetchImpl:async(url,options)=>{
      called=true;
      const parsed=new URL(url);
      assert.equal(parsed.origin,'https://ski.example.test');
      assert.equal(parsed.pathname,'/rest/v1/ski_foundation_sessions');
      assert.equal(parsed.searchParams.get('session_hash'),'eq.'+expected);
      assert.equal(options.headers['x-shine-ski-token'],raw);
      return Response.json([{session_hash:expected}]);
    }
  });
  const result=await adapters.verifyClaimSource({
    appId:'shine.ski',
    providerId:'supabase:ski-session',
    userToken:raw
  });
  assert.equal(called,true);
  assert.deepEqual(result,{providerId:'supabase:ski-session',authSubject:expected});
});

test('claim target must be app-approved and map to an active canonical Shine ID',async()=>{
  const {adapters}=makeAdapters();
  const token=jwt({iss:issuer,sub:'auth-user'});
  const result=await adapters.verifyClaimTarget({
    appId:'shine.ski',
    providerId:'supabase:test',
    jwt:token
  });
  assert.equal(result.providerId,'supabase:test');
  assert.equal(result.authSubject,'auth-user');
  assert.equal(result.shineId,shineId);
});

test('unapproved claim target is rejected before external Auth call',async()=>{
  let calls=0;
  const {adapters}=makeAdapters({fetchImpl:async()=>{calls++;return Response.json({id:'auth-user'})}});
  const result=await adapters.verifyClaimTarget({
    appId:'shine.dive',
    providerId:'supabase:test',
    jwt:jwt({iss:issuer,sub:'auth-user'})
  });
  assert.equal(result,null);
  assert.equal(calls,0);
});

test('complete identity claim delegates to atomic database function',async()=>{
  const {adapters}=makeAdapters();
  const result=await adapters.completeIdentityClaim({
    claimId:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    requestId:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    appId:'shine.ski',
    sourceProviderId:'supabase:ski-session',
    sourceSubject:'source-hash',
    targetProviderId:'supabase:test',
    targetSubject:'auth-user',
    targetShineId:shineId,
    occurredAt:'2026-09-26T12:30:00Z'
  });
  assert.deepEqual(result,{outcome:'linked',reason_code:'identity-claim-linked'});
});


test('explicit grant consent delegates to the atomic database function',async()=>{
  const {adapters}=makeAdapters();
  const result=await adapters.issueAccessGrant({
    consentId:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    grantId,
    requestId:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    ownerShineId:shineId,
    appId:'shine.travel',
    scope:'vault.foundation.pilot.read',
    purpose:'travel.foundation-pilot',
    resourceId:null,
    resourceCategory:'foundation.pilot',
    occurredAt:'2026-09-26T13:15:00Z'
  });
  assert.deepEqual(result,{outcome:'granted',reason_code:'grant-consent-recorded',grant_id:grantId});
});


test('explicit grant revoke delegates to the atomic database function',async()=>{
  const {adapters}=makeAdapters();
  const result=await adapters.revokeAccessGrant({
    eventId:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    revocationId:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    requestId:'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    grantId,
    ownerShineId:shineId,
    appId:'shine.travel',
    occurredAt:'2026-09-27T13:20:00Z'
  });
  assert.deepEqual(result,{outcome:'revoked',reason_code:'grant-revoked-by-user',revocation_id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'});
});


test('revocation propagation adapters map feed, receipt, ack and freshness contracts',async()=>{
  const {adapters}=makeAdapters();
  const feed=await adapters.listAppRevocations({appId:'shine.travel',afterSequence:6,limit:2});
  assert.deepEqual(feed,[{
    sequenceNo:7,
    event:{event:'shine-foundation/grant-revocation-v1'},
    createdAt:'2026-09-27T13:20:00Z'
  }]);

  const delivery=await adapters.recordAppRevocationDelivery({
    deliveryId:'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    appId:'shine.travel',afterSequence:6,sequenceNos:[7],
    occurredAt:'2026-09-27T13:30:00Z'
  });
  assert.deepEqual(delivery,{
    deliveryId:'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    terminalSequence:7,eventCount:1
  });

  const ack=await adapters.acknowledgeAppRevocations({
    ackId:'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    requestId:'ffffffff-ffff-4fff-8fff-ffffffffffff',
    deliveryId:'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    appId:'shine.travel',sequenceNo:7,occurredAt:'2026-09-27T13:31:00Z'
  });
  assert.deepEqual(ack,{
    outcome:'advanced',
    reasonCode:'revocation-checkpoint-advanced',
    checkpointSequence:7
  });

  const status=await adapters.getAppRevocationStatus({appId:'shine.travel'});
  assert.equal(status.pendingCount,1);
  assert.equal(status.checkpointSequence,6);

  const health=await adapters.getAppRevocationHealth({appId:'shine.travel'});
  assert.equal(health.freshnessState,'pending');
  assert.equal(health.recommendedAction,'consume-revocations');
});


test('capability discovery delegates to the hosted database function',async()=>{
  const {adapters}=makeAdapters();
  const result=await adapters.listDiscoverableCapabilities({appId:'shine.travel'});
  assert.deepEqual(result,[{
    capabilityId:'travel.plan_trip',
    appId:'shine.travel',
    invocationState:'declared',
    invocable:false
  }]);
});

test('app operational status delegates to the hosted database function',async()=>{
  const {adapters}=makeAdapters();
  const result=await adapters.getAppOperationalStatus({appId:'shine.travel'});
  assert.deepEqual(result,{appId:'shine.travel',operationalState:'revocation-pending',operationalHealth:'attention'});
});

test('dependency admission delegates to the hosted database function',async()=>{
  const {adapters}=makeAdapters();
  const result=await adapters.evaluateDependencyAdmission({
    serviceId:'foundation.gateway',
    environment:'production',
    operation:'access.evaluate',
    asOf:'2026-09-28T01:55:00Z'
  });
  assert.equal(result.admissionState,'admit');
  assert.equal(result.impactScope,'protected-operations');
  assert.equal(result.reasonCode,'dependency-admission-clear');
});

test('universal route policy delegates to the hosted database broker',async()=>{
  const {adapters}=makeAdapters();
  const result=await adapters.evaluateGatewayRoutePolicy({
    method:'POST',
    path:'/v1/grants/consent',
    environment:'production',
    asOf:'2026-09-28T03:45:00Z'
  });
  assert.equal(result.policyState,'admit');
  assert.equal(result.operationKey,'grant.consent');
  assert.equal(result.path,'/v1/grants/consent');
});

test('runtime exposes the complete Gateway adapter surface',()=>{
  const {adapters}=makeAdapters();
  const required=[
    'verifyIntegrationClient','verifyAppCaller','verifyIdentity',
    'verifyIntegrationIdentity','verifyIntegrationDelegation',
    'linkIntegrationClient','grantIntegrationClientCapability',
    'revokeIntegrationClientGrant','revokeIntegrationClientLink',
    'listIntegrationClientGrants','createIntegrationLinkRequest',
    'resolveIntegrationLinkApproval','approveIntegrationLinkRequest',
    'getIntegrationLinkRequestStatus','exchangeIntegrationLinkRequest',
    'rotateIntegrationDelegation','rotateIntegrationDelegationV2',
    'planConciergeRequest','gateConciergeExecution','explainConciergeDenial',
    'recordConciergeExecutionEvent','getConciergeResumeState',
    'recordConciergeStepCheckpoint','queueConciergeRetry',
    'claimDueConciergeRetry','finishConciergeRetry','getConciergeFleetStatus',
    'listConnectedIntegrations','listUserAccessHistory',
    'explainCapabilityAccess','cancelConciergeRequest','listUserConciergeJobs',
    'resolveIntegrationSubjectOwner','getIntegrationContextPublishEvent',
    'publishIntegrationContextSnapshot','redeemCapabilityInvocationTicket',
    'issueCapabilityInvocationTicket','getCapabilityAdapterHealth',
    'recordCapabilityAdapterHealth','invokeCapability',
    'listDiscoverableCapabilities','getAppOperationalStatus',
    'evaluateDependencyAdmission','evaluateGatewayRoutePolicy','getAppManifest','getVaultResource',
    'getEffectiveGrants','evaluateDefence','writeAuditEvent'
  ];
  const missing=required.filter(name=>typeof adapters[name]!=='function');
  assert.deepEqual(missing,[]);
});

