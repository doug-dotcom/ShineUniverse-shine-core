import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';

const script=new URL('./build-deployment-receipt-payload-v1.mjs',import.meta.url);

function run(overrides={}){
  const env={
    ...process.env,
    FOUNDATION_RUNTIME_VERSION:'86',
    FOUNDATION_ARTIFACT_SHA256:'a'.repeat(64),
    FOUNDATION_SOURCE_COMMIT:'b'.repeat(40),
    FOUNDATION_PROVIDER_EVIDENCE_REF:'supabase:management-api:foundation-gateway:v86',
    FOUNDATION_PROVIDER_OBSERVED_AT:'2026-09-28T06:40:00Z',
    GITHUB_RUN_ID:'12345',
    GITHUB_RUN_ATTEMPT:'2',
    GITHUB_REPOSITORY:'doug-dotcom/ShineUniverse-shine-core',
    ...overrides
  };
  return spawnSync(process.execPath,[script.pathname],{env,encoding:'utf8'});
}

test('builds a non-secret canonical deployment receipt payload',()=>{
  const r=run();
  assert.equal(r.status,0,r.stderr);
  const body=JSON.parse(r.stdout);
  assert.equal(body.p_service_id,'foundation.gateway');
  assert.equal(body.p_environment,'production');
  assert.equal(body.p_provider,'supabase-edge');
  assert.equal(body.p_runtime_version,'86');
  assert.equal(body.p_artifact_sha256,'a'.repeat(64));
  assert.equal(body.p_source_ref,'github://doug-dotcom/ShineUniverse-shine-core/commit/'+('b'.repeat(40)));
  assert.equal(body.p_submitted_by,'github-actions');
  assert.equal(body.p_metadata.transport,'github-actions-workflow-dispatch');
  assert.equal(body.p_metadata.workflowRunId,'12345');
  assert.equal(body.p_metadata.rollback,false);
  assert.equal('serviceRoleKey' in body,false);
  assert.equal('providerToken' in body,false);
});

test('marks explicit rollback metadata',()=>{
  const r=run({FOUNDATION_ROLLBACK:'true'});
  assert.equal(r.status,0,r.stderr);
  assert.equal(JSON.parse(r.stdout).p_metadata.rollback,true);
});

test('rejects malformed artefact hash',()=>{
  const r=run({FOUNDATION_ARTIFACT_SHA256:'bad'});
  assert.notEqual(r.status,0);
  assert.match(r.stderr,/64 hex characters/);
});

test('rejects non-exact source commit',()=>{
  const r=run({FOUNDATION_SOURCE_COMMIT:'main'});
  assert.notEqual(r.status,0);
  assert.match(r.stderr,/40-character commit SHA/);
});

test('rejects missing provider evidence',()=>{
  const r=run({FOUNDATION_PROVIDER_EVIDENCE_REF:''});
  assert.notEqual(r.status,0);
  assert.match(r.stderr,/PROVIDER_EVIDENCE_REF is required/);
});
