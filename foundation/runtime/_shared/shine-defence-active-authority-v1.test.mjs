import test from 'node:test';
import assert from 'node:assert/strict';
import {verifyLiveDefenceAttestationAuthority} from './shine-defence-active-authority-v1.mjs';

const SHA='7bfd7fe685b4b2da814ac53dafdbfac2350591c8';
const REF='doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-release-attestation-v1.yml@'+SHA;

const sqlReturning=rows=>async()=>rows;

test('live authority verifier accepts the current signed reusable-workflow authority',async()=>{
  const result=await verifyLiveDefenceAttestationAuthority({
    sql:sqlReturning([{
      authority_sha:SHA,
      authority_ref:REF,
      workflow_blob_sha:'71218df29b79919af76115b9180a6afbbd8dbf79',
      activation_sequence:1,
      activation_kind:'bootstrap',
      activated_at:'2026-09-30T06:58:39Z'
    }]),
    identity:{jobWorkflowSha:SHA,jobWorkflowRef:REF}
  });
  assert.equal(result.authoritySha,SHA);
  assert.equal(result.authorityRef,REF);
  assert.equal(result.activationSequence,1);
});

test('live authority verifier rejects stale, missing and absent Foundation authority state',async()=>{
  await assert.rejects(
    ()=>verifyLiveDefenceAttestationAuthority({
      sql:sqlReturning([{authority_sha:'e'.repeat(40),authority_ref:REF.replace(SHA,'e'.repeat(40))}]),
      identity:{jobWorkflowSha:SHA,jobWorkflowRef:REF}
    }),
    /OIDC attestation authority mismatch/
  );

  await assert.rejects(
    ()=>verifyLiveDefenceAttestationAuthority({
      sql:sqlReturning([{authority_sha:SHA,authority_ref:REF}]),
      identity:{jobWorkflowSha:'',jobWorkflowRef:''}
    }),
    /OIDC reusable workflow authority claims missing/
  );

  await assert.rejects(
    ()=>verifyLiveDefenceAttestationAuthority({
      sql:sqlReturning([]),
      identity:{jobWorkflowSha:SHA,jobWorkflowRef:REF}
    }),
    /OIDC active attestation authority missing/
  );
});
