import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {webcrypto} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {createGithubActionsOidcVerifier,GITHUB_ACTIONS_OIDC_ISSUER} from './github-actions-oidc-v1.mjs';
import {SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY,SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY_REF,SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY_SHA,SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY_VERSION} from './shine-defence-release-attestation-authority-v1.mjs';

const fixedNow=Date.parse('2026-09-30T03:30:00Z');
const nowSeconds=Math.floor(fixedNow/1000);
const b64=value=>Buffer.from(typeof value==='string'?value:JSON.stringify(value)).toString('base64url');

async function makeKey(kid){
  const pair=await webcrypto.subtle.generateKey(
    {name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},
    true,
    ['sign','verify']
  );
  const jwk=await webcrypto.subtle.exportKey('jwk',pair.publicKey);
  return {pair,jwk:{...jwk,kid,use:'sig',alg:'RS256'}};
}

async function signJwt(payload,key,{kid=key.jwk.kid,alg='RS256'}={}){
  const header=b64({alg,kid,typ:'JWT'});
  const body=b64(payload);
  const input=header+'.'+body;
  const signature=await webcrypto.subtle.sign({name:'RSASSA-PKCS1-v1_5'},key.pair.privateKey,Buffer.from(input));
  return input+'.'+Buffer.from(signature).toString('base64url');
}

const basePayload=()=>({
  iss:GITHUB_ACTIONS_OIDC_ISSUER,
  aud:'shine-defence-release-head',
  exp:nowSeconds+600,
  nbf:nowSeconds-10,
  iat:nowSeconds-10,
  repository:'doug-dotcom/example',
  repository_id:'456789',
  repository_owner:'doug-dotcom',
  repository_owner_id:'225530237',
  ref:'refs/heads/main',
  ref_type:'branch',
  workflow_ref:'doug-dotcom/example/.github/workflows/shine-defence-release-head.yml@refs/heads/main',
  event_name:'schedule',
  runner_environment:'github-hosted',
  workflow_sha:'b'.repeat(40),
  run_id:'1234',
  run_attempt:'2',
  actor:'doug-dotcom',
  actor_id:'225530237',
  sha:'a'.repeat(40),
  sub:'repo:doug-dotcom/example:ref:refs/heads/main'
});

const policy={
  audience:'shine-defence-release-head',
  expectedRef:'refs/heads/main',
  expectedWorkflow:{path:'.github/workflows/shine-defence-release-head.yml',branch:'main'},
  expectedRepositoryOwner:'doug-dotcom',
  expectedRepositoryOwnerId:'225530237',
  expectedRefType:'branch',
  expectedRunnerEnvironment:'github-hosted',
  subjectMode:'repository-ref',
  allowedEvents:['schedule','workflow_dispatch','push']
};

test('shared verifier accepts current key and refreshes immediately on signing-key rotation',async()=>{
  const first=await makeKey('kid-1');
  const second=await makeKey('kid-2');
  let keys=[first.jwk];
  let metadataFetches=0;
  let jwksFetches=0;
  const fetchImpl=async url=>{
    if(String(url).endsWith('/.well-known/openid-configuration')){
      metadataFetches++;
      return {ok:true,json:async()=>({issuer:GITHUB_ACTIONS_OIDC_ISSUER,jwks_uri:GITHUB_ACTIONS_OIDC_ISSUER+'/.well-known/jwks'})};
    }
    if(String(url)===GITHUB_ACTIONS_OIDC_ISSUER+'/.well-known/jwks'){
      jwksFetches++;
      return {ok:true,json:async()=>({keys})};
    }
    throw new Error('unexpected fetch '+url);
  };
  const verifier=createGithubActionsOidcVerifier({fetchImpl,cryptoImpl:webcrypto,now:()=>fixedNow,jwksTtlMs:300000});

  const firstToken=await signJwt(basePayload(),first);
  const firstIdentity=await verifier.verify(firstToken,policy);
  assert.equal(firstIdentity.kid,'kid-1');
  assert.equal(firstIdentity.repository,'doug-dotcom/example');
  assert.equal(firstIdentity.repositoryId,'456789');
  assert.equal(firstIdentity.repositoryOwnerId,'225530237');
  assert.equal(firstIdentity.workflowSha,'b'.repeat(40));
  assert.equal(firstIdentity.runnerEnvironment,'github-hosted');
  assert.equal(jwksFetches,1);
  assert.equal(metadataFetches,1);

  await verifier.verify(firstToken,policy);
  assert.equal(jwksFetches,1,'fresh JWKS should be reused');

  keys=[second.jwk];
  const secondToken=await signJwt(basePayload(),second);
  const secondIdentity=await verifier.verify(secondToken,policy);
  assert.equal(secondIdentity.kid,'kid-2');
  assert.equal(jwksFetches,2,'unknown kid should force one immediate JWKS refresh');
  assert.equal(metadataFetches,1,'JWKS rotation should not require metadata rediscovery');
});

test('shared verifier fails closed after refresh and enforces consumer claim policy',async()=>{
  const key=await makeKey('kid-current');
  let jwksFetches=0;
  const fetchImpl=async url=>{
    if(String(url).endsWith('/.well-known/openid-configuration')) return {ok:true,json:async()=>({issuer:GITHUB_ACTIONS_OIDC_ISSUER,jwks_uri:GITHUB_ACTIONS_OIDC_ISSUER+'/.well-known/jwks'})};
    jwksFetches++;
    return {ok:true,json:async()=>({keys:[key.jwk]})};
  };
  const verifier=createGithubActionsOidcVerifier({fetchImpl,cryptoImpl:webcrypto,now:()=>fixedNow,jwksTtlMs:300000});
  await verifier.verify(await signJwt(basePayload(),key),policy);

  const wrongAudience=await signJwt({...basePayload(),aud:'some-other-audience'},key);
  await assert.rejects(()=>verifier.verify(wrongAudience,policy),/OIDC audience mismatch/);

  const wrongWorkflow=await signJwt({...basePayload(),workflow_ref:'doug-dotcom/example/.github/workflows/other.yml@refs/heads/main'},key);
  await assert.rejects(()=>verifier.verify(wrongWorkflow,policy),/OIDC workflow mismatch/);

  const wrongRepositoryId=await signJwt({...basePayload(),repository_id:'999'},key);
  await assert.rejects(()=>verifier.verify(wrongRepositoryId,{...policy,expectedRepositoryId:'456789'}),/OIDC repository id mismatch/);

  const selfHosted=await signJwt({...basePayload(),runner_environment:'self-hosted'},key);
  await assert.rejects(()=>verifier.verify(selfHosted,policy),/OIDC runner environment mismatch/);

  const badRefType=await signJwt({...basePayload(),ref_type:'tag'},key);
  await assert.rejects(()=>verifier.verify(badRefType,policy),/OIDC ref type mismatch/);

  const badWorkflowSha=await signJwt({...basePayload(),workflow_sha:'not-a-sha'},key);
  await assert.rejects(()=>verifier.verify(badWorkflowSha,policy),/OIDC workflow sha claim invalid/);

  const badSubject=await signJwt({...basePayload(),sub:'repo:doug-dotcom/other:ref:refs/heads/main'},key);
  await assert.rejects(()=>verifier.verify(badSubject,policy),/OIDC subject mismatch/);

  const immutablePayload={...basePayload(),sub:'repo:doug-dotcom@225530237/example@456789:ref:refs/heads/main'};
  const immutableIdentity=await verifier.verify(await signJwt(immutablePayload,key),policy);
  assert.equal(immutableIdentity.subject,immutablePayload.sub);

  const reusablePayload={
    ...basePayload(),
    job_workflow_ref:'doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-release-attestation-v1.yml@deadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
    job_workflow_sha:'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef'
  };
  const reusablePolicy={
    ...policy,
    expectedJobWorkflowRef:reusablePayload.job_workflow_ref,
    expectedJobWorkflowSha:reusablePayload.job_workflow_sha
  };
  const reusableIdentity=await verifier.verify(await signJwt(reusablePayload,key),reusablePolicy);
  assert.equal(reusableIdentity.jobWorkflowRef,reusablePayload.job_workflow_ref);
  assert.equal(reusableIdentity.jobWorkflowSha,reusablePayload.job_workflow_sha);

  const wrongJobWorkflow=await signJwt({...reusablePayload,job_workflow_sha:'c'.repeat(40)},key);
  await assert.rejects(()=>verifier.verify(wrongJobWorkflow,reusablePolicy),/OIDC job workflow sha mismatch/);

  const missingReusableAuthority=await signJwt(basePayload(),key);
  await assert.rejects(()=>verifier.verify(missingReusableAuthority,reusablePolicy),/OIDC job workflow ref mismatch/);


  const expired=await signJwt({...basePayload(),exp:nowSeconds-60},key);
  await assert.rejects(()=>verifier.verify(expired,policy),/OIDC token expired/);

  const stale=await signJwt({...basePayload(),iat:nowSeconds-700,nbf:nowSeconds-700,exp:nowSeconds+60},key);
  await assert.rejects(()=>verifier.verify(stale,policy),/OIDC token too old/);

  const missingIssuedAt=await signJwt(Object.fromEntries(Object.entries(basePayload()).filter(([k])=>k!=='iat')),key);
  await assert.rejects(()=>verifier.verify(missingIssuedAt,policy),/OIDC issued-at claim missing/);

  const missingRunId=await signJwt({...basePayload(),run_id:''},key);
  await assert.rejects(()=>verifier.verify(missingRunId,policy),/OIDC run id claim invalid/);

  const unknownKid=await signJwt(basePayload(),key,{kid:'kid-unknown'});
  const before=jwksFetches;
  await assert.rejects(()=>verifier.verify(unknownKid,policy),/OIDC signing key not found after refresh/);
  assert.equal(jwksFetches,before+1,'unknown kid must refresh exactly once before rejection');
});

test('OIDC discovery cannot redirect JWKS trust to another origin',async()=>{
  const verifier=createGithubActionsOidcVerifier({
    fetchImpl:async()=>({ok:true,json:async()=>({issuer:GITHUB_ACTIONS_OIDC_ISSUER,jwks_uri:'https://evil.example/jwks'})}),
    cryptoImpl:webcrypto,
    now:()=>fixedNow
  });
  const key=await makeKey('kid-1');
  const token=await signJwt(basePayload(),key);
  await assert.rejects(()=>verifier.verify(token,policy),/OIDC jwks_uri origin mismatch/);
});

test('all Foundation OIDC consumers delegate cryptography to the shared verifier',()=>{
  const root=fileURLToPath(new URL('../../../',import.meta.url));
  const consumers=[
    'foundation/runtime/defence-reattest/index.ts',
    'foundation/runtime/defence-provider-ingest/index.ts',
    'foundation/runtime/deployment-receipt-ingest/index.ts',
    'foundation/runtime/defence-rollback-readiness/index.ts',
    'foundation/runtime/defence-release-head-ingest/index.ts',
    'foundation/runtime/defence-attestation-authority-ingest/index.ts'
  ];
  const contract=JSON.parse(readFileSync(root+'security/shine-defence/github-actions-oidc-verifier-v1.json','utf8'));
  assert.deepEqual(contract.consumers,consumers);
  for(const path of consumers){
    const source=readFileSync(root+path,'utf8');
    assert.match(source,/from '\.\.\/_shared\/github-actions-oidc-v1\.mjs'/,path+' must import the shared verifier');
    assert.match(source,/verifyGithubActionsOidc\(auth\.slice\(7\),OIDC_POLICY\)/,path+' must apply an explicit local claim policy');
    assert.match(source,/github-oidc-operation-v1\.mjs/,path+' must import the shared OIDC replay binder');
    assert.match(source,/bindGithubOidcOperation\(/,path+' must bind verified run identity to request semantics');
    assert.match(source,/expectedRepositoryOwner:'doug-dotcom'/,path+' must pin the repository owner name');
    assert.match(source,/expectedRepositoryOwnerId:'225530237'/,path+' must pin the immutable repository owner id');
    assert.match(source,/expectedRefType:'branch'/,path+' must restrict OIDC to branch refs');
    assert.match(source,/expectedRunnerEnvironment:'github-hosted'/,path+' must reject self-hosted runner tokens');
    assert.match(source,/subjectMode:'repository-ref'/,path+' must enforce repository-ref subject semantics');
    assert.doesNotMatch(source,/token\.actions\.githubusercontent\.com/,path+' must not own issuer discovery');
    assert.doesNotMatch(source,/crypto\.subtle\.verify/,path+' must not implement JWT signature verification');
    assert.doesNotMatch(source,/getJwks|oidcMetadataPromise|jwksPromise/,path+' must not own JWKS caching');
  }
});

test('authority-state sync is hourly, receipt-backed and atomic for authority mutations',()=>{
  const root=fileURLToPath(new URL('../../../',import.meta.url));
  const source=readFileSync(root+'foundation/runtime/defence-attestation-authority-ingest/index.ts','utf8');
  const workflow=readFileSync(root+'.github/workflows/shine-defence-authority-state.yml','utf8');

  assert.match(source,/allowedEvents:\['push','workflow_dispatch','schedule'\]/);
  assert.match(source,/record_defence_attestation_authority_sync_receipt_v1/);
  assert.match(source,/get_defence_attestation_authority_sync_summary_v1/);
  assert.match(source,/sql\.begin\(/,'promotion/rollback sync must use one database transaction');
  assert.match(workflow,/schedule:\s*\n\s*- cron: '17 \* \* \* \*'/);
  assert.match(workflow,/audience=shine-defence-authority-state/);
});

test('dynamic release consumers bind signed immutable repository ids to Foundation target metadata and one shared authority pin',()=>{
  const root=fileURLToPath(new URL('../../../',import.meta.url));
  const authority=JSON.parse(readFileSync(root+'security/shine-defence/release-attestation-authority-v1.json','utf8'));
  assert.equal(authority.runtimeBinding.path,'foundation/runtime/_shared/shine-defence-release-attestation-authority-v1.mjs');
  assert.equal(authority.runtimeBinding.version,SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY_VERSION);
  assert.equal(authority.reusableWorkflow.repository,SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY.repository);
  assert.equal(authority.reusableWorkflow.repositoryId,SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY.repositoryId);
  assert.equal(authority.reusableWorkflow.path,SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY.workflowPath);
  assert.equal(authority.reusableWorkflow.authoritySha,SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY_SHA);
  assert.equal(authority.enforcement.requiredJobWorkflowRef,SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY_REF);
  assert.equal(authority.enforcement.requiredJobWorkflowSha,SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY_SHA);

  const release=readFileSync(root+'foundation/runtime/defence-release-head-ingest/index.ts','utf8');
  const rollback=readFileSync(root+'foundation/runtime/defence-rollback-readiness/index.ts','utf8');
  for(const [name,source] of [['release-head',release],['rollback',rollback]]){
    assert.match(source,/sourceRepositoryId/,name+' must load immutable repository id from target metadata');
    assert.match(source,/sourceRepositoryOwnerId/,name+' must load immutable owner id from target metadata');
    assert.match(source,/identity\.repositoryId/,name+' must compare the signed repository id');
    assert.match(source,/identity\.repositoryOwnerId/,name+' must compare the signed owner id');
    assert.match(source,/shine-defence-release-attestation-authority-v1\.mjs/,name+' must import the shared Core authority pin');
    assert.match(source,/expectedJobWorkflowRef:SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY_REF/,name+' must consume the shared authority ref');
    assert.match(source,/expectedJobWorkflowSha:SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY_SHA/,name+' must consume the shared authority sha');
    assert.doesNotMatch(source,/EXPECTED_JOB_WORKFLOW_REF|EXPECTED_JOB_WORKFLOW_SHA/,name+' must not own a local reusable-workflow pin');
  }
});

test('fixed Core OIDC consumers pin the immutable Core repository id',()=>{
  const root=fileURLToPath(new URL('../../../',import.meta.url));
  for(const path of [
    'foundation/runtime/defence-provider-ingest/index.ts',
    'foundation/runtime/deployment-receipt-ingest/index.ts',
    'foundation/runtime/defence-reattest/index.ts',
    'foundation/runtime/defence-attestation-authority-ingest/index.ts'
  ]){
    const source=readFileSync(root+path,'utf8');
    assert.match(source,/expectedRepositoryId:'1072897952'/,path+' must pin Core repository id');
  }
});
