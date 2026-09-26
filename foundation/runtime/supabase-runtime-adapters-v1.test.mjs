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
      return values[0]===issuer
        ? [{provider_id:'supabase:test',project_url:'https://identity.example.test',publishable_key:'public-key'}]
        : [];
    }
    if(q.includes('from foundation.identity_bindings')) return [{shine_id:shineId}];
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
      defenceGate:createFoundationRuntimeDefenceGateV1(),
      localAuthUrl:'https://foundation.test'
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
  const result=await adapters.verifyIdentity({authContext:{jwt:token}});
  assert.equal(result.shineId,shineId);
  assert.equal(result.authSubject,'auth-user');
  assert.equal(result.providerId,'supabase:test');
  assert.equal(result.sessionId,'session-1');
});

test('unregistered issuer is denied without contacting external Auth',async()=>{
  let calls=0;
  const {adapters}=makeAdapters({fetchImpl:async()=>{calls++;return Response.json({id:'x'})}});
  const result=await adapters.verifyIdentity({
    authContext:{jwt:jwt({iss:'https://evil.example/auth/v1',sub:'x'})}
  });
  assert.equal(result,null);
  assert.equal(calls,0);
});

test('registered issuer token rejected by provider is not mapped',async()=>{
  const {adapters}=makeAdapters({fetchImpl:async()=>new Response('{}',{status:401})});
  const result=await adapters.verifyIdentity({authContext:{jwt:jwt({iss:issuer,sub:'auth-user'})}});
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


test('verifies a trusted external Shine Supabase issuer before identity mapping',async()=>{
  const externalShineId='99999999-9999-4999-8999-999999999999';
  const issuer='https://shine-l.test/auth/v1';
  const payload=Buffer.from(JSON.stringify({iss:issuer,sub:'untrusted-sub'})).toString('base64url');
  const jwt='x.'+payload+'.x';
  const sql=async(strings,...values)=>{
    const q=strings.join('?').replace(/\s+/g,' ').trim().toLowerCase();
    if(q.includes('from foundation.trusted_auth_issuers')){
      assert.equal(values[0],issuer);
      return [{issuer_id:'supabase:shine-l',issuer_url:issuer,api_url:'https://shine-l.test',publishable_key:'public'}];
    }
    if(q.includes('from foundation.identity_bindings')){
      assert.equal(values[0],'supabase:shine-l');
      assert.equal(values[1],externalShineId);
      return [{shine_id:externalShineId}];
    }
    throw new Error('unexpected SQL '+q);
  };
  const adapters=createSupabaseRuntimeAdapters({
    sql,
    authClient:{auth:{getClaims:async()=>{throw new Error('local auth must not verify external token')}}},
    defenceGate:createFoundationRuntimeDefenceGateV1(),
    localAuthUrl:'https://foundation.test',
    fetchFn:async(url,options)=>{
      assert.equal(url,'https://shine-l.test/auth/v1/user');
      assert.equal(options.headers.apikey,'public');
      assert.equal(options.headers.Authorization,'Bearer '+jwt);
      return Response.json({id:externalShineId});
    }
  });
  const result=await adapters.verifyIdentity({authContext:{jwt}});
  assert.equal(result.shineId,externalShineId);
  assert.equal(result.authProvider,'supabase:shine-l');
});
