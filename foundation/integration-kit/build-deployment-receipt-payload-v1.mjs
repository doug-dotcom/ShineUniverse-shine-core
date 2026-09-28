#!/usr/bin/env node

const fail=message=>{ throw new Error(message); };
const env=process.env;

const serviceId=env.FOUNDATION_SERVICE_ID??'foundation.gateway';
const environment=env.FOUNDATION_ENVIRONMENT??'production';
const provider=env.FOUNDATION_PROVIDER??'supabase-edge';
const runtimeRef=env.FOUNDATION_RUNTIME_REF??'supabase://sjpxqeyewahraxvidvcc/functions/foundation-gateway';
const runtimeVersion=env.FOUNDATION_RUNTIME_VERSION;
const artifactSha256=env.FOUNDATION_ARTIFACT_SHA256;
const runtimeState=env.FOUNDATION_RUNTIME_STATE??'active';
const sourceCommit=env.FOUNDATION_SOURCE_COMMIT;
const providerEvidenceRef=env.FOUNDATION_PROVIDER_EVIDENCE_REF;
const providerObservedAt=env.FOUNDATION_PROVIDER_OBSERVED_AT;
const submittedBy=env.FOUNDATION_SUBMITTED_BY??'github-actions';
const rollback=(env.FOUNDATION_ROLLBACK??'false')==='true';

if(!runtimeVersion||runtimeVersion.length>128) fail('FOUNDATION_RUNTIME_VERSION is required');
if(!artifactSha256||!/^[a-fA-F0-9]{64}$/.test(artifactSha256)) fail('FOUNDATION_ARTIFACT_SHA256 must be 64 hex characters');
if(!sourceCommit||!/^[a-fA-F0-9]{40}$/.test(sourceCommit)) fail('FOUNDATION_SOURCE_COMMIT must be a 40-character commit SHA');
if(!providerEvidenceRef||providerEvidenceRef.length>1000) fail('FOUNDATION_PROVIDER_EVIDENCE_REF is required');
if(!providerObservedAt||Number.isNaN(Date.parse(providerObservedAt))) fail('FOUNDATION_PROVIDER_OBSERVED_AT must be an ISO timestamp');
if(!['active','inactive','failed'].includes(runtimeState)) fail('FOUNDATION_RUNTIME_STATE is invalid');

const payload={
  p_service_id:serviceId,
  p_environment:environment,
  p_provider:provider,
  p_runtime_ref:runtimeRef,
  p_runtime_version:runtimeVersion,
  p_artifact_sha256:artifactSha256.toLowerCase(),
  p_runtime_state:runtimeState,
  p_source_ref:`github://doug-dotcom/ShineUniverse-shine-core/commit/${sourceCommit.toLowerCase()}`,
  p_provider_evidence_ref:providerEvidenceRef,
  p_provider_observed_at:new Date(providerObservedAt).toISOString(),
  p_submitted_by:submittedBy,
  p_metadata:{
    transport:'github-actions-workflow-dispatch',
    workflowRunId:env.GITHUB_RUN_ID??null,
    workflowRunAttempt:env.GITHUB_RUN_ATTEMPT??null,
    repository:env.GITHUB_REPOSITORY??null,
    rollback
  }
};

process.stdout.write(JSON.stringify(payload));
