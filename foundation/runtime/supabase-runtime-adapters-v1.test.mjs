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
