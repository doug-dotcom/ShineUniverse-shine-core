import test from 'node:test';
import assert from 'node:assert/strict';
import {createVeteranCareSessionIdentityVerifier as create} from './veteran-care-session-v1.mjs';
import {VETERAN_CARE_ISSUER as issuer} from './veteran-care-identity-v1.mjs';
import {VETERAN_CARE_PROJECT_URL as url} from './veteran-care-project-boundary-v1.mjs';
const appId='shine.veteran-care',sessionId='33333333-3333-4333-8333-333333333333';
const identity={shineId:'11111111-1111-4111-8111-111111111111',authSubject:'22222222-2222-4222-8222-222222222222',providerId:'supabase:veteran-care'};
const configuration={mode:'veteran_care',issuer,authProjectUrl:url,databaseProjectUrl:url,storageProjectUrl:url};
const claims=()=>({iss:issuer,aud:'authenticated',role:'authenticated',sub:identity.authSubject,session_id:sessionId,exp:2000});
const state=()=>({status:'active',sessionId,authSubject:identity.authSubject,issuer,expiresAt:null});
const request=()=>({authContext:{appToken:'synthetic',jwt:'e30.'+Buffer.from(JSON.stringify({iss:issuer})).toString('base64url')+'.c2ln'}});
function fixture({tokenClaims=claims(),sessionState=state(),lookup,clock=()=>1000000,caller=appId}={}){
  const calls=[];
  const verify=create({configuration,appId,providerId:identity.providerId,clock,
    auth:{getClaims:async()=>({data:{claims:tokenClaims},error:null})},
    verifyAppCaller:async()=>({appId:caller}),verifyIdentity:async()=>identity,
    getSessionState:async query=>{calls.push(query);return lookup?lookup(query):sessionState;}});
  return {verify,calls};
}
const denial={status:'denied',reasonCode:'vc-session-not-current'};
test('active session uses verified session and subject, with no token in lookup',async()=>{
  const f=fixture(),r=request();Object.assign(r.authContext,{sessionId:'forged',sessionState:state()});
  assert.equal((await f.verify(r)).status,'verified');assert.deepEqual(f.calls,[{sessionId,authSubject:identity.authSubject,providerId:identity.providerId,appId,issuer}]);
});
test('missing revoked expired and inactive authority states deny',async()=>{
  for(const sessionState of [null,undefined,{...state(),status:'revoked'},{...state(),status:'expired'},{...state(),status:'inactive'}])
    assert.deepEqual(await fixture({sessionState:sessionState??null}).verify(request()),denial);
});
test('missing malformed and foreign session IDs never reach lookup',async()=>{
  for(const session_id of [undefined,null,'*','not-a-uuid',3]){const f=fixture({tokenClaims:{...claims(),session_id}});assert.deepEqual(await f.verify(request()),denial);assert.deepEqual(f.calls,[]);}
});
test('token expiry requires bounded numeric seconds and rejects exact boundary',async()=>{
  for(const exp of [undefined,null,'2000',NaN,Infinity,Number.MAX_SAFE_INTEGER,1000,999,0,-1,1000.5]){
    const f=fixture({tokenClaims:{...claims(),exp}});assert.deepEqual(await f.verify(request()),denial);assert.deepEqual(f.calls,[]);
  }
});
test('future and malformed not-before reject while present boundary is valid',async()=>{
  for(const nbf of [1001,null,'1000',NaN]) assert.deepEqual(await fixture({tokenClaims:{...claims(),nbf}}).verify(request()),denial);
  assert.equal((await fixture({tokenClaims:{...claims(),nbf:1000}}).verify(request())).status,'verified');
});
test('session row must match verified user session and project',async()=>{
  for(const [key,value] of [['sessionId','44444444-4444-4444-8444-444444444444'],['authSubject','55555555-5555-4555-8555-555555555555'],['issuer','https://other.supabase.co/auth/v1']])
    assert.deepEqual(await fixture({sessionState:{...state(),[key]:value}}).verify(request()),denial);
});
test('session policy expiry is enforced and must explicitly be null or seconds',async()=>{
  for(const expiresAt of [undefined,'2000',NaN,1000,999]) assert.deepEqual(await fixture({sessionState:{...state(),expiresAt}}).verify(request()),denial);
  assert.equal((await fixture({sessionState:{...state(),expiresAt:1001}}).verify(request())).status,'verified');
});
test('expiry during lookup withholds token and session success',async()=>{
  for(const sessionOnly of [false,true]){let n=0;const f=fixture({clock:()=>n++===0?1000000:2000000,tokenClaims:{...claims(),exp:sessionOnly?3000:2000},sessionState:{...state(),expiresAt:sessionOnly?2000:null}});assert.deepEqual(await f.verify(request()),denial);}
});
test('invalid or regressing server clock fails closed',async()=>{
  for(const clock of [()=>NaN,()=>-1,()=>Infinity,(()=>{let n=0;return()=>n++===0?1000000:999999;})()])
    assert.deepEqual(await fixture({clock}).verify(request()),{status:'unavailable',reasonCode:'vc-session-authority-unavailable'});
});
test('session authority outage returns bounded unavailable without identity',async()=>{
  const f=fixture({lookup:async()=>{throw new Error('synthetic-secret');}});assert.deepEqual(await f.verify(request()),{status:'unavailable',reasonCode:'vc-session-authority-unavailable'});
});
test('each request rechecks revocation without caching successful session',async()=>{
  let current=state();const f=fixture({lookup:async()=>current});assert.equal((await f.verify(request())).status,'verified');current=null;assert.deepEqual(await f.verify(request()),denial);assert.equal(f.calls.length,2);
});
test('foreign audience or caller cannot reach session authority',async()=>{
  for(const options of [{caller:'shine.travel'},{tokenClaims:{...claims(),aud:'shine.travel'}}]){const f=fixture(options);assert.equal((await f.verify(request())).status,'denied');assert.deepEqual(f.calls,[]);}
});
test('concurrent requests cannot share another session authority result',async()=>{
  let release,arrived;const reached=new Promise(r=>{arrived=r;});let n=0;
  const f=fixture({lookup:async()=>{if(n++===0){arrived();return new Promise(r=>{release=r;});}return null;}});
  const pending=f.verify(request());await reached;assert.deepEqual(await f.verify(request()),denial);release(state());assert.equal((await pending).status,'verified');
});
test('session authority is mandatory for the session-bound factory',()=>{
  assert.throws(()=>create({}),TypeError);assert.throws(()=>create({getSessionState:()=>null,clock:1}),TypeError);
});
