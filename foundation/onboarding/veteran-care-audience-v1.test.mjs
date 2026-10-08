import test from 'node:test';
import assert from 'node:assert/strict';
import {createVeteranCareAudienceIdentityVerifier as create} from './veteran-care-audience-v1.mjs';
import {VETERAN_CARE_ISSUER as issuer} from './veteran-care-identity-v1.mjs';
import {VETERAN_CARE_PROJECT_URL as url} from './veteran-care-project-boundary-v1.mjs';
const appId='shine.veteran-care';
const identity={shineId:'11111111-1111-4111-8111-111111111111',authSubject:'22222222-2222-4222-8222-222222222222',providerId:'supabase:veteran-care'};
const jwt=(extra={})=>'e30.'+Buffer.from(JSON.stringify({iss:issuer,aud:'authenticated',...extra})).toString('base64url')+'.c2ln';
const configuration=()=>({mode:'veteran_care',issuer,authProjectUrl:url,databaseProjectUrl:url,storageProjectUrl:url});
const claims=()=>({iss:issuer,aud:'authenticated',sub:identity.authSubject,role:'authenticated'});
function fixture({verifiedClaims=claims(),claimsResult,caller=appId,config=configuration(),getClaims}={}){
  const calls=[];
  const auth={getClaims:async token=>{calls.push(['claims',token]);return getClaims?getClaims(token):claimsResult??{data:{claims:verifiedClaims},error:null};}};
  const verify=create({configuration:config,appId,providerId:identity.providerId,auth,
    verifyAppCaller:async()=>{calls.push(['app']);return {appId:caller};},
    verifyIdentity:async()=>{calls.push(['identity']);return identity;}});
  return {verify,calls,auth};
}
const request=()=>({authContext:{jwt:jwt(),appToken:'synthetic-vc-app-token'}});
test('verified dedicated user token returns app-bound server context only',async()=>{
  const f=fixture(),r=request();
  assert.deepEqual(await f.verify(r),{status:'verified',identity,audience:{appId,issuer,tokenAudience:'authenticated'}});
  assert.deepEqual(f.calls,[['app'],['identity'],['claims',r.authContext.jwt]]);
});
test('foreign app token cannot reach identity or claims authority',async()=>{
  const f=fixture({caller:'shine.travel'});assert.equal((await f.verify(request())).reasonCode,'vc-app-caller-unverified');assert.deepEqual(f.calls,[['app']]);
});
test('another project token with identical generic audience is rejected',async()=>{
  const f=fixture();assert.equal((await f.verify({authContext:{jwt:jwt({iss:'https://sjpxqeyewahraxvidvcc.supabase.co/auth/v1'})}})).reasonCode,'vc-identity-provider-mismatch');assert.deepEqual(f.calls,[]);
});
test('verified foreign missing wildcard anonymous and multiple audiences reject',async()=>{
  for(const aud of [undefined,null,'anon','shine.travel','*','',['authenticated','shine.travel'],['authenticated','authenticated'],[],{},42]){
    const f=fixture({verifiedClaims:{...claims(),aud}});assert.equal((await f.verify(request())).reasonCode,'vc-token-audience-mismatch');
  }
});
test('single authenticated array audience is accepted',async()=>{
  const f=fixture({verifiedClaims:{...claims(),aud:['authenticated']}});assert.equal((await f.verify(request())).status,'verified');
});
test('decoded or caller-declared audience cannot override verified claims',async()=>{
  const f=fixture({verifiedClaims:{...claims(),aud:'shine.travel'}}),r=request();
  Object.assign(r.authContext,{aud:'authenticated',claims:claims(),appId});assert.equal((await f.verify(r)).reasonCode,'vc-token-audience-mismatch');
});
test('verified issuer subject and user role must agree with identity authority',async()=>{
  for(const [key,value,reason] of [['iss','https://other.supabase.co/auth/v1','vc-token-issuer-mismatch'],['sub','33333333-3333-4333-8333-333333333333','vc-token-identity-mismatch'],['role','service_role','vc-token-identity-mismatch']]){
    const f=fixture({verifiedClaims:{...claims(),[key]:value}});assert.equal((await f.verify(request())).reasonCode,reason);
  }
});
test('claims verification failure withholds even apparently valid decoded token',async()=>{
  for(const result of [{data:{claims:claims()},error:{message:'synthetic-private-error'}},{data:null,error:null},{data:{},error:null}]){
    const f=fixture({claimsResult:result});assert.deepEqual(await f.verify(request()),{status:'denied',reasonCode:'vc-token-unverified'});
  }
});
test('claims authority outage is bounded and returns no identity or error detail',async()=>{
  const f=fixture({getClaims:async()=>{throw new Error('synthetic-secret');}});assert.deepEqual(await f.verify(request()),{status:'unavailable',reasonCode:'vc-token-authority-unavailable'});
});
test('invalid dedicated configuration stops all authorities',async()=>{
  const f=fixture({config:{...configuration(),mode:'foundation'}});assert.equal((await f.verify(request())).reasonCode,'vc-project-boundary-invalid');assert.deepEqual(f.calls,[]);
});
test('proof is snapshotted and concurrent requests cannot borrow audience success',async()=>{
  let resolve,arrived;
  const reached=new Promise(r=>{arrived=r;});
  const f=fixture({getClaims:token=>{if(token===jwt({aud:'foreign'}))return {data:{claims:{...claims(),aud:'foreign'}}};arrived();return new Promise(r=>{resolve=r;});}});
  const r=request(),good=f.verify(r);await reached;r.authContext.jwt=jwt({aud:'foreign'});
  assert.equal((await f.verify(requestWithForeign())).reasonCode,'vc-token-audience-mismatch');
  resolve({data:{claims:claims()}});assert.equal((await good).status,'verified');
  assert.equal(f.calls.filter(c=>c[0]==='claims')[0][1],jwt());
  function requestWithForeign(){return {authContext:{appToken:'synthetic',jwt:jwt({aud:'foreign'})}};}
});
test('verified-claims authority is mandatory and no ambient session is used',async()=>{
  for(const auth of [undefined,{}, {getSession:()=>claims()}, {decode:()=>claims()}])assert.throws(()=>create({auth}),TypeError);
  const f=fixture();f.auth.getClaims=()=>{throw new Error('changed after construction');};assert.equal((await f.verify(request())).status,'verified');
});
