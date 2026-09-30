import test from 'node:test';
import assert from 'node:assert/strict';
import {
  SHINE_DEFENCE_AUTHORITY_HEARTBEAT_MAX_AGE_SECONDS,
  verifyLiveDefenceAttestationAuthority
} from './shine-defence-active-authority-v1.mjs';

const SHA='7bfd7fe685b4b2da814ac53dafdbfac2350591c8';
const REF='doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-release-attestation-v1.yml@'+SHA;
const BLOB='71218df29b79919af76115b9180a6afbbd8dbf79';

const healthySummary=(age=120)=>({
  state:'pass',
  reasonCode:'attestation-authority-sync-current',
  receiptAgeSeconds:age,
  currentAuthority:{
    lineageSequence:1,
    authoritySha:SHA,
    authorityRef:REF
  },
  latestReceipt:{
    receiptId:'11111111-1111-4111-8111-111111111111',
    lineageSequence:1,
    authoritySha:SHA,
    publisherCommitSha:'a'.repeat(40),
    githubRunId:'123456',
    githubRunAttempt:'1'
  }
});

const sqlReturning=rows=>async()=>rows;
const currentRow=overrides=>({
  authority_sha:SHA,
  authority_ref:REF,
  workflow_blob_sha:BLOB,
  activation_sequence:1,
  activation_kind:'bootstrap',
  activated_at:'2026-09-30T06:58:39Z',
  sync_summary:healthySummary(),
  ...overrides
});

test('live authority verifier accepts current authority only with a fresh matching sync heartbeat',async()=>{
  const result=await verifyLiveDefenceAttestationAuthority({
    sql:sqlReturning([currentRow()]),
    identity:{jobWorkflowSha:SHA,jobWorkflowRef:REF}
  });
  assert.equal(result.authoritySha,SHA);
  assert.equal(result.authorityRef,REF);
  assert.equal(result.activationSequence,1);
  assert.equal(result.syncReceiptAgeSeconds,120);
  assert.equal(result.syncGithubRunId,'123456');
});

test('live authority verifier rejects stale, mismatched and missing heartbeat state',async()=>{
  await assert.rejects(
    ()=>verifyLiveDefenceAttestationAuthority({
      sql:sqlReturning([currentRow({
        sync_summary:{...healthySummary(SHINE_DEFENCE_AUTHORITY_HEARTBEAT_MAX_AGE_SECONDS+1),state:'warning',reasonCode:'attestation-authority-sync-receipt-stale'}
      })]),
      identity:{jobWorkflowSha:SHA,jobWorkflowRef:REF}
    }),
    /OIDC attestation authority heartbeat stale or mismatched/
  );

  await assert.rejects(
    ()=>verifyLiveDefenceAttestationAuthority({
      sql:sqlReturning([currentRow({
        sync_summary:{
          ...healthySummary(),
          latestReceipt:{...healthySummary().latestReceipt,authoritySha:'e'.repeat(40)}
        }
      })]),
      identity:{jobWorkflowSha:SHA,jobWorkflowRef:REF}
    }),
    /OIDC attestation authority heartbeat stale or mismatched/
  );

  await assert.rejects(
    ()=>verifyLiveDefenceAttestationAuthority({
      sql:sqlReturning([currentRow({sync_summary:null})]),
      identity:{jobWorkflowSha:SHA,jobWorkflowRef:REF}
    }),
    /OIDC attestation authority heartbeat stale or mismatched/
  );
});

test('live authority verifier still fails closed on authority claim/state errors',async()=>{
  await assert.rejects(
    ()=>verifyLiveDefenceAttestationAuthority({
      sql:sqlReturning([currentRow({authority_sha:'e'.repeat(40),authority_ref:REF.replace(SHA,'e'.repeat(40))})]),
      identity:{jobWorkflowSha:SHA,jobWorkflowRef:REF}
    }),
    /OIDC attestation authority mismatch/
  );

  await assert.rejects(
    ()=>verifyLiveDefenceAttestationAuthority({
      sql:sqlReturning([currentRow()]),
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

  await assert.rejects(
    ()=>verifyLiveDefenceAttestationAuthority({
      sql:async()=>{throw new Error('database unavailable')},
      identity:{jobWorkflowSha:SHA,jobWorkflowRef:REF}
    }),
    /OIDC active attestation authority heartbeat unavailable/
  );
});
