import test from 'node:test';
import assert from 'node:assert/strict';
import {createSupabaseRuntimeAdapters,sha256Hex} from './supabase-runtime-adapters-v1.mjs';
import {createFoundationRuntimeDefenceGateV1} from './runtime-defence-gate-v1.mjs';

const shineId='11111111-1111-4111-8111-111111111111';
const resourceId='22222222-2222-4222-8222-222222222222';
const grantId='33333333-3333-4333-8333-333333333333';

const makeSql=()=>{
  const audit=[];
  const sql=async(strings,...values)=>{
    const q=strings.join('?').replace(/\s+/g,' ').trim().toLowerCase();
    if(q.includes('from foundation.effective_app_credentials')){
      return values[0]==='4c0ffa9a073e5e47ee51e8352cee4b05d0c21f75b501e314e2ffae28fd635909'
        ? [{credential_id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',app_id:'shine.travel'}] : [];
    }
    if(q.includes('from foundation.identity_bindings')) return [{shine_id:shineId}];
    if(q.includes('from foundation.app_registry')){
      return [{manifest:{appId:'shine.travel',foundation:{requestedScopes:[]}}}];
    }
    if(q.includes('from foundation.vault_resources')){
      return [{resource_id:resourceId,owner_shine_id:shineId,category:'profile.location',
        sensitivity:'personal',content_type:'application/json',storage_ref:'vault://home-airport'}];
    }
    if(q.includes('from foundation.effective_access_grants')){
      return [{grant_id:grantId,owner_shine_id:shineId,app_id:'shine.travel',
        scope:'vault.location.read',purpose:'travel.home-airport',resource_id:resourceId,
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

const makeAdapters=()=>{
  const {sql,audit}=makeSql();
  return {
    audit,
    adapters:createSupabaseRuntimeAdapters({
      sql,
      authClient:{auth:{getClaims:async()=>({data:{claims:{sub:'auth-user',session_id:'session-1'}}})}},
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

test('maps verified Supabase auth subject to canonical Shine ID',async()=>{
  const {adapters}=makeAdapters();
  const result=await adapters.verifyIdentity({authContext:{jwt:'jwt'}});
  assert.equal(result.shineId,shineId);
  assert.equal(result.sessionId,'session-1');
});

test('reads Vault metadata and effective grants without Vault content',async()=>{
  const {adapters}=makeAdapters();
  const resource=await adapters.getVaultResource({resourceId,ownerShineId:shineId});
  const grants=await adapters.getEffectiveGrants({
    shineId,appId:'shine.travel',scope:'vault.location.read',purpose:'travel.home-airport'
  });
  assert.equal(resource.storageRef,'vault://home-airport');
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

test('audit writes are persisted through the runtime surface',async()=>{
  const {adapters,audit}=makeAdapters();
  await adapters.writeAuditEvent({
    eventId:'55555555-5555-4555-8555-555555555555',
    requestId:'44444444-4444-4444-8444-444444444444',
    appId:'shine.travel',shineId,scope:'vault.location.read',
    purpose:'travel.home-airport',resourceId,decision:'allow',
    reasonCode:'grant-match',grantId,occurredAt:'2026-09-26T07:00:00Z'
  });
  assert.equal(audit.length,1);
});
