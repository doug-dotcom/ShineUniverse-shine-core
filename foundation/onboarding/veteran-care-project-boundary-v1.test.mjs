import test from 'node:test';
import assert from 'node:assert/strict';
import {VETERAN_CARE_ISSUER} from './veteran-care-identity-v1.mjs';
import {VETERAN_CARE_PROJECT_URL as url,assessVeteranCareProjectBoundary as assess,createVeteranCareBoundIdentityVerifier as create} from './veteran-care-project-boundary-v1.mjs';
const config=()=>({mode:'veteran_care',issuer:VETERAN_CARE_ISSUER,authProjectUrl:url,databaseProjectUrl:url,storageProjectUrl:url});
const legacy='https://sjpxqeyewahraxvidvcc.supabase.co';
const denied={status:'denied',reasonCode:'vc-project-boundary-invalid'};
const jwt=iss=>'e30.'+Buffer.from(JSON.stringify({iss})).toString('base64url')+'.c2ln';
const identity={shineId:'11111111-1111-4111-8111-111111111111',authSubject:'22222222-2222-4222-8222-222222222222',providerId:'supabase:veteran-care'};
function fixture(configuration=config()){
  const calls=[];
  const verify=create({configuration,appId:'shine.veteran-care',providerId:identity.providerId,
    verifyAppCaller:async()=>{calls.push('app');return {appId:'shine.veteran-care'};},
    verifyIdentity:async()=>{calls.push('identity');return identity;}});
  return {verify,calls};
}
const request={authContext:{jwt:jwt(VETERAN_CARE_ISSUER),appToken:'synthetic-app-token'}};
test('coherent dedicated descriptor permits existing server authority chain',async()=>{
  assert.equal(assess(config()).status,'ready');
  const f=fixture();assert.deepEqual(await f.verify(request),{status:'verified',identity});assert.deepEqual(f.calls,['app','identity']);
});
test('each mixed project endpoint blocks with zero authority calls',async()=>{
  for(const key of ['authProjectUrl','databaseProjectUrl','storageProjectUrl']){
    const f=fixture({...config(),[key]:legacy});assert.deepEqual(await f.verify(request),denied);assert.deepEqual(f.calls,[]);
  }
});
test('legacy issuer blocks dedicated endpoints',async()=>{
  const f=fixture({...config(),issuer:legacy+'/auth/v1'});assert.deepEqual(await f.verify(request),denied);assert.deepEqual(f.calls,[]);
});
test('offline legacy missing and unknown modes never fall back',()=>{
  for(const mode of ['offline_preview','foundation',undefined,'unknown']) assert.equal(assess({...config(),mode}).status,'blocked');
});
test('noncanonical and lookalike endpoints reject',()=>{
  for(const candidate of [url+'/',url+':443',url+'/rest/v1',url+'?x=1',url+'#x',url+'.evil.test',url.replace('https://','https://user@'),url.replace('https','http')])
    for(const key of ['authProjectUrl','databaseProjectUrl','storageProjectUrl']) assert.equal(assess({...config(),[key]:candidate}).status,'blocked');
});
test('incomplete extra secret and symbol properties reject',()=>{
  for(const key of Object.keys(config())){const c=config();delete c[key];assert.equal(assess(c).status,'blocked');}
  for(const key of ['serviceRoleKey','gatewayUrl',Symbol('extra')]) assert.equal(assess({...config(),[key]:'synthetic'}).status,'blocked');
});
test('accessors are rejected without executing them',()=>{
  const c=config();Object.defineProperty(c,'issuer',{get(){throw new Error('must not execute');}});assert.equal(assess(c).status,'blocked');
});
test('malformed inherited and hostile descriptors fail closed',()=>{
  for(const c of [null,undefined,[],Object.create(config()),new Proxy({},{getPrototypeOf(){throw new Error('synthetic');}})]) assert.equal(assess(c).status,'blocked');
});
test('configuration mutation cannot alter constructed boundary decision',async()=>{
  const good=config(),f=fixture(good);good.databaseProjectUrl=legacy;assert.equal((await f.verify(request)).status,'verified');
  const bad={...config(),mode:'foundation'},g=fixture(bad);bad.mode='veteran_care';assert.deepEqual(await g.verify(request),denied);assert.deepEqual(g.calls,[]);
});
test('valid descriptor does not authenticate legacy tokens or grant data access',async()=>{
  const f=fixture();assert.equal((await f.verify({authContext:{jwt:jwt(legacy+'/auth/v1')}})).reasonCode,'vc-identity-provider-mismatch');assert.deepEqual(f.calls,[]);
  assert.throws(()=>create({configuration:config()}),TypeError);
});
