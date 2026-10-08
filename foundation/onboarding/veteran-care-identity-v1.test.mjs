import test from 'node:test';
import assert from 'node:assert/strict';
import {createSupabaseRuntimeAdapters} from '../runtime/supabase-runtime-adapters-v1.mjs';
import {createVeteranCareIdentityVerifier} from './veteran-care-identity-v1.mjs';
const appId='shine.veteran-care'; // Fixture identifier; not a claim of live registration.
const providerId='supabase:veteran-care'; // Fixture identifier; provisioned ID must be supplied.
const issuer='https://akyzwuvfvugzyauaptsk.supabase.co/auth/v1';
const shineId='11111111-1111-4111-8111-111111111111';
const subject='22222222-2222-4222-8222-222222222222';
const jwt=(iss=issuer)=>'header.'+Buffer.from(JSON.stringify({iss,sub:'forged-subject',email:'same@example.test',shineId:'forged'})).toString('base64url')+'.signature';
function fixture({app=true,provider=true,bound=true,verified=true,outage=false}={}){
  const calls=[];
  const sql=async(strings,...values)=>{
    const query=strings.join('?');
    calls.push({query,values});
    if(outage) throw new Error('private backend failure');
    if(query.includes('effective_app_credentials'))return app?[{app_id:appId,credential_id:'fixture'}]:[];
    if(query.includes('identity_providers')){
      assert.deepEqual(values,[issuer,appId]);
      assert.match(query,/p.status='active'/);
      assert.match(query,/a.status='active'/);
      return provider?[{provider_id:providerId,project_url:issuer.replace('/auth/v1',''),publishable_key:'fixture-public'}]:[];
    }
    if(query.includes('identity_bindings')){
      assert.deepEqual(values,[providerId,subject]);
      assert.match(query,/b.verified_at is not null/);
      assert.match(query,/i.account_state='active'/);
      assert.doesNotMatch(query,/email/);
      return bound?[{shine_id:shineId}]:[];
    }
    throw new Error('Unexpected SQL operation');
  };
  const adapters=createSupabaseRuntimeAdapters({sql,defenceGate:async()=>({decision:'allow'}),fetchImpl:async(url,options)=>{
    calls.push({url});
    assert.equal(url,issuer.replace('/auth/v1','')+'/auth/v1/user');
    assert.equal(options.headers.Authorization,'Bearer '+jwt());
    return {ok:verified,json:async()=>({id:subject,email:'same@example.test',user_metadata:{shineId:'forged'}})};
  }});
  return {calls,verify:createVeteranCareIdentityVerifier({appId,providerId,verifyAppCaller:adapters.verifyAppCaller,verifyIdentity:adapters.verifyIdentity})};
}
const authContext={appToken:'synthetic-app-token',jwt:jwt()};
test('maps provider-verified subject, ignores caller and user metadata, creates no grants',async()=>{
  const f=fixture();
  assert.deepEqual(await f.verify({authContext:{...authContext,email:'same@example.test',shineId:'forged'},claimedAppId:'shine.other'}),{status:'verified',identity:{shineId,authSubject:subject,providerId}});
  assert.equal(f.calls.length,4);
  assert.ok(f.calls.every(c=>!c.query||!/(insert|update|delete|grant)/i.test(c.query)));
});
test('same email cannot bind an unbound dedicated account',async()=>{
  assert.deepEqual(await fixture({bound:false}).verify({authContext}),{status:'denied',reasonCode:'vc-user-identity-unverified'});
});
test('unapproved provider performs no user verification',async()=>{
  const f=fixture({provider:false});
  assert.equal((await f.verify({authContext})).status,'denied');
  assert.ok(f.calls.every(c=>!c.url));
});
test('unverified app performs no user lookup',async()=>{
  const f=fixture({app:false});
  assert.deepEqual(await f.verify({authContext}),{status:'denied',reasonCode:'vc-app-caller-unverified'});
  assert.equal(f.calls.length,1);
});
test('invalid provider token never reaches bindings',async()=>{
  const f=fixture({verified:false});
  assert.equal((await f.verify({authContext})).status,'denied');
  assert.ok(f.calls.every(c=>!c.query?.includes('identity_bindings')));
});
test('old Foundation issuer is rejected before any authority call',async()=>{
  const f=fixture();
  assert.equal((await f.verify({authContext:{...authContext,jwt:jwt('https://sjpxqeyewahraxvidvcc.supabase.co/auth/v1')}})).reasonCode,'vc-identity-provider-mismatch');
  assert.equal(f.calls.length,0);
});
test('missing, malformed, oversized and mixed user proofs are rejected without calls',async()=>{
  const f=fixture();
  for(const context of [{},{...authContext,jwt:'bad'},{...authContext,jwt:'x'.repeat(16385)},{...authContext,userToken:'opaque'}])
    assert.equal((await f.verify({authContext:context})).reasonCode,'vc-user-proof-invalid');
  assert.equal(f.calls.length,0);
});
test('authority outage returns bounded error without disclosing details',async()=>{
  assert.deepEqual(await fixture({outage:true}).verify({authContext}),{status:'unavailable',reasonCode:'vc-identity-authority-unavailable'});
});
test('wrong verified provider, malformed identity and mismatched app are denied',async()=>{
  for(const identity of [{shineId,authSubject:subject,providerId:'supabase:other'},{shineId:'forged',authSubject:subject,providerId},{shineId,authSubject:'forged',providerId},null]){
    const verify=createVeteranCareIdentityVerifier({appId,providerId,verifyAppCaller:async()=>({appId}),verifyIdentity:async()=>identity});
    assert.equal((await verify({authContext})).status,'denied');
  }
  let reads=0;
  const verify=createVeteranCareIdentityVerifier({appId,providerId,verifyAppCaller:async()=>({appId:'shine.other'}),verifyIdentity:async()=>{reads++;}});
  assert.equal((await verify({authContext})).status,'denied');
  assert.equal(reads,0);
});
test('missing registered configuration cannot construct an identity verifier',()=>{
  assert.throws(()=>createVeteranCareIdentityVerifier({}));
});
