-- Foundation Layer 53: independently controlled retest consumption of owner evidence.
-- A current Layer-52 evidence return may trigger a fresh canonical Foundation retest,
-- but only through the existing service_role retest authority. Owner claims never
-- become readiness truth and no remediation execution authority is granted.

create table foundation.readiness_dependency_remediation_evidence_retests(
  evidence_retest_sequence bigint generated always as identity primary key,
  evidence_retest_id uuid not null unique default gen_random_uuid(),
  evidence_return_id uuid not null unique
    references foundation.readiness_dependency_remediation_evidence_returns(evidence_return_id),
  retest_cycle_id uuid not null unique
    references foundation.foundation_readiness_retest_cycles(cycle_id),
  environment text not null,
  source_condition_fingerprint text not null
    check(source_condition_fingerprint ~ '^[a-f0-9]{32}$'),
  source_evidence_return_sha256 text not null
    check(source_evidence_return_sha256 ~ '^[a-f0-9]{64}$'),
  owner_reported_outcome text not null
    check(owner_reported_outcome in ('resolved','improved','unchanged','worsened','inconclusive')),
  canonical_readiness_state text not null,
  canonical_condition_fingerprint text not null
    check(canonical_condition_fingerprint ~ '^[a-f0-9]{32}$'),
  canonical_raw_evidence_fingerprint text not null
    check(canonical_raw_evidence_fingerprint ~ '^[a-f0-9]{32}$'),
  transition_type text not null,
  retest_proof jsonb not null check(jsonb_typeof(retest_proof)='object'),
  retest_proof_sha256 text not null check(retest_proof_sha256 ~ '^[a-f0-9]{64}$'),
  retested_at timestamptz not null,
  recorded_at timestamptz not null default now()
);

alter table foundation.readiness_dependency_remediation_evidence_retests enable row level security;

create policy foundation_runtime_readiness_evidence_retests_select
on foundation.readiness_dependency_remediation_evidence_retests
for select to foundation_runtime using(true);

revoke all on foundation.readiness_dependency_remediation_evidence_retests
  from public,anon,authenticated,foundation_gateway,service_role,shine_defence_runtime;
grant select on foundation.readiness_dependency_remediation_evidence_retests
  to foundation_runtime,service_role;

create trigger readiness_dependency_remediation_evidence_retests_append_only
before update or delete on foundation.readiness_dependency_remediation_evidence_retests
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.run_readiness_dependency_remediation_evidence_retest_v1(
  p_evidence_return_id uuid,
  p_retested_at timestamptz default now(),
  p_persistence_threshold_seconds integer default 300,
  p_max_evidence_age_seconds integer default 900
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $layer53_retest$
declare
  e foundation.readiness_dependency_remediation_evidence_returns%rowtype;
  existing foundation.readiness_dependency_remediation_evidence_retests%rowtype;
  es jsonb;
  retest jsonb;
  cycle foundation.foundation_readiness_retest_cycles%rowtype;
  doc jsonb;
  doc_hash text;
  rid uuid;
begin
  if p_evidence_return_id is null then
    raise exception 'readiness-evidence-retest-evidence-return-required';
  end if;

  if p_persistence_threshold_seconds is null
     or p_persistence_threshold_seconds<0
     or p_persistence_threshold_seconds>86400 then
    raise exception 'readiness-evidence-retest-persistence-threshold-invalid';
  end if;

  if p_max_evidence_age_seconds is null
     or p_max_evidence_age_seconds<60
     or p_max_evidence_age_seconds>3600 then
    raise exception 'readiness-evidence-retest-max-age-invalid';
  end if;

  if p_retested_at<now()-interval '5 minutes'
     or p_retested_at>now()+interval '5 minutes' then
    raise exception 'readiness-evidence-retest-time-invalid';
  end if;

  select * into e
  from foundation.readiness_dependency_remediation_evidence_returns
  where evidence_return_id=p_evidence_return_id;

  if e.evidence_return_id is null then
    return jsonb_build_object(
      'foundationReadinessEvidenceRetest',
        'shine-foundation/readiness-remediation-evidence-retest-response-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','readiness-remediation-evidence-return-not-found',
      'independentRetest',true,
      'ownerOutcomeAcceptedAsReadiness',false,
      'readinessChangedByOwnerEvidence',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesRemediation',false
    );
  end if;

  select * into existing
  from foundation.readiness_dependency_remediation_evidence_retests
  where evidence_return_id=e.evidence_return_id;

  if existing.evidence_retest_id is not null then
    return jsonb_build_object(
      'foundationReadinessEvidenceRetest',
        'shine-foundation/readiness-remediation-evidence-retest-response-v1',
      'schemaVersion','1.0.0',
      'status','existing',
      'evidenceRetestId',existing.evidence_retest_id,
      'evidenceReturnId',existing.evidence_return_id,
      'retestCycleId',existing.retest_cycle_id,
      'ownerReportedOutcome',existing.owner_reported_outcome,
      'canonicalReadinessState',existing.canonical_readiness_state,
      'canonicalConditionFingerprint',existing.canonical_condition_fingerprint,
      'transitionType',existing.transition_type,
      'retestProofSha256',existing.retest_proof_sha256,
      'independentRetest',true,
      'ownerOutcomeAcceptedAsReadiness',false,
      'readinessChangedByOwnerEvidence',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesRemediation',false
    );
  end if;

  es:=foundation.get_readiness_dependency_remediation_evidence_return_status_v1(
    e.handoff_id
  );

  if es->>'state'<>'current'
     or coalesce(es->>'integrityVerified','false')<>'true'
     or es->>'evidenceReturnId' is distinct from e.evidence_return_id::text then
    return jsonb_build_object(
      'foundationReadinessEvidenceRetest',
        'shine-foundation/readiness-remediation-evidence-retest-response-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','readiness-remediation-evidence-return-not-current',
      'evidenceReturnState',es->>'state',
      'independentRetest',true,
      'ownerOutcomeAcceptedAsReadiness',false,
      'readinessChangedByOwnerEvidence',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesRemediation',false
    );
  end if;

  if e.returned_at < p_retested_at-make_interval(secs=>p_max_evidence_age_seconds)
     or e.returned_at > p_retested_at+interval '5 minutes' then
    return jsonb_build_object(
      'foundationReadinessEvidenceRetest',
        'shine-foundation/readiness-remediation-evidence-retest-response-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','readiness-remediation-evidence-return-too-old',
      'evidenceReturnedAt',e.returned_at,
      'maxEvidenceAgeSeconds',p_max_evidence_age_seconds,
      'independentRetest',true,
      'ownerOutcomeAcceptedAsReadiness',false,
      'readinessChangedByOwnerEvidence',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesRemediation',false
    );
  end if;

  -- Crucial boundary: owner facts/outcome are NOT parameters to the canonical retest.
  -- The evidence packet is only the admission signal to collect Foundation truth again.
  retest:=foundation.run_foundation_readiness_retest_cycle_v1(
    e.environment,
    p_retested_at,
    p_persistence_threshold_seconds
  );

  if retest->>'cycleId' is null
     or retest->>'conditionFingerprint' is null
     or retest->>'rawEvidenceFingerprint' is null
     or retest->>'readinessState' is null
     or retest->>'transitionType' is null then
    raise exception 'readiness-evidence-retest-canonical-result-invalid';
  end if;

  select * into cycle
  from foundation.foundation_readiness_retest_cycles
  where cycle_id=(retest->>'cycleId')::uuid;

  if cycle.cycle_id is null
     or cycle.environment is distinct from e.environment
     or cycle.condition_fingerprint is distinct from retest->>'conditionFingerprint'
     or cycle.raw_evidence_fingerprint is distinct from retest->>'rawEvidenceFingerprint'
     or cycle.readiness_state is distinct from retest->>'readinessState'
     or cycle.transition_type is distinct from retest->>'transitionType' then
    raise exception 'readiness-evidence-retest-cycle-persistence-mismatch';
  end if;

  doc:=jsonb_build_object(
    'readinessDependencyRemediationEvidenceRetest',
      'shine-foundation/readiness-dependency-remediation-evidence-retest-v1',
    'schemaVersion','1.0.0',
    'evidenceReturnId',e.evidence_return_id,
    'handoffId',e.handoff_id,
    'responseId',e.response_id,
    'proposalId',e.proposal_id,
    'sourceReadinessIncidentEventId',e.readiness_incident_event_id,
    'environment',e.environment,
    'sourceConditionFingerprint',e.condition_fingerprint,
    'sourceEvidenceReturnSha256',e.evidence_return_sha256,
    'sourceEvidenceStateAtAdmission','current',
    'ownerReportedOutcome',e.owner_reported_outcome,
    'ownerOutcomeAcceptedAsReadiness',false,
    'sourceEvidenceUsedAsTriggerOnly',true,
    'independentRetest',true,
    'canonicalRetestFunction','foundation.run_foundation_readiness_retest_cycle_v1',
    'retestCycleId',cycle.cycle_id,
    'retestObservationId',cycle.readiness_drift_observation_id,
    'retestIncidentEventId',cycle.readiness_incident_event_id,
    'canonicalReadinessState',cycle.readiness_state,
    'canonicalConditionFingerprint',cycle.condition_fingerprint,
    'canonicalRawEvidenceFingerprint',cycle.raw_evidence_fingerprint,
    'transitionType',cycle.transition_type,
    'readinessChangedByOwnerEvidence',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesRemediation',false,
    'retestedAt',p_retested_at
  );

  doc_hash:=encode(
    extensions.digest(convert_to(doc::text,'UTF8'),'sha256'),
    'hex'
  );

  insert into foundation.readiness_dependency_remediation_evidence_retests(
    evidence_return_id,retest_cycle_id,environment,
    source_condition_fingerprint,source_evidence_return_sha256,
    owner_reported_outcome,canonical_readiness_state,
    canonical_condition_fingerprint,canonical_raw_evidence_fingerprint,
    transition_type,retest_proof,retest_proof_sha256,retested_at
  )
  values(
    e.evidence_return_id,cycle.cycle_id,e.environment,
    e.condition_fingerprint,e.evidence_return_sha256,
    e.owner_reported_outcome,cycle.readiness_state,
    cycle.condition_fingerprint,cycle.raw_evidence_fingerprint,
    cycle.transition_type,doc,doc_hash,p_retested_at
  )
  returning evidence_retest_id into rid;

  return jsonb_build_object(
    'foundationReadinessEvidenceRetest',
      'shine-foundation/readiness-remediation-evidence-retest-response-v1',
    'schemaVersion','1.0.0',
    'status','recorded',
    'evidenceRetestId',rid,
    'evidenceReturnId',e.evidence_return_id,
    'retestCycleId',cycle.cycle_id,
    'ownerReportedOutcome',e.owner_reported_outcome,
    'canonicalReadinessState',cycle.readiness_state,
    'canonicalConditionFingerprint',cycle.condition_fingerprint,
    'transitionType',cycle.transition_type,
    'retestProofSha256',doc_hash,
    'independentRetest',true,
    'ownerOutcomeAcceptedAsReadiness',false,
    'sourceEvidenceUsedAsTriggerOnly',true,
    'readinessChangedByOwnerEvidence',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesRemediation',false
  );
end;
$layer53_retest$;

revoke all on function foundation.run_readiness_dependency_remediation_evidence_retest_v1(
  uuid,timestamptz,integer,integer
) from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.run_readiness_dependency_remediation_evidence_retest_v1(
  uuid,timestamptz,integer,integer
) to service_role;


create or replace function foundation.get_readiness_dependency_remediation_evidence_retest_status_v1(
  p_evidence_return_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $layer53_status$
declare
  r foundation.readiness_dependency_remediation_evidence_retests%rowtype;
  c foundation.foundation_readiness_retest_cycles%rowtype;
  expected_hash text;
  source_state text;
  state text;
begin
  select * into r
  from foundation.readiness_dependency_remediation_evidence_retests
  where evidence_return_id=p_evidence_return_id;

  if r.evidence_retest_id is null then
    return jsonb_build_object(
      'foundationReadinessEvidenceRetestStatus',
        'shine-foundation/readiness-remediation-evidence-retest-status-v1',
      'schemaVersion','1.0.0',
      'state','pending',
      'evidenceReturnId',p_evidence_return_id,
      'independentRetest',true,
      'ownerOutcomeAcceptedAsReadiness',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesRemediation',false
    );
  end if;

  expected_hash:=encode(
    extensions.digest(convert_to(r.retest_proof::text,'UTF8'),'sha256'),
    'hex'
  );

  select * into c
  from foundation.foundation_readiness_retest_cycles
  where cycle_id=r.retest_cycle_id;

  select coalesce(
    foundation.get_readiness_dependency_remediation_evidence_return_status_v1(e.handoff_id)->>'state',
    'unknown'
  )
  into source_state
  from foundation.readiness_dependency_remediation_evidence_returns e
  where e.evidence_return_id=r.evidence_return_id;

  state:=case
    when expected_hash is distinct from r.retest_proof_sha256 then 'invalid'
    when c.cycle_id is null then 'invalid'
    when c.condition_fingerprint is distinct from r.canonical_condition_fingerprint then 'invalid'
    when c.raw_evidence_fingerprint is distinct from r.canonical_raw_evidence_fingerprint then 'invalid'
    else 'completed'
  end;

  return jsonb_build_object(
    'foundationReadinessEvidenceRetestStatus',
      'shine-foundation/readiness-remediation-evidence-retest-status-v1',
    'schemaVersion','1.0.0',
    'state',state,
    'evidenceRetestId',r.evidence_retest_id,
    'evidenceReturnId',r.evidence_return_id,
    'retestCycleId',r.retest_cycle_id,
    'sourceEvidenceCurrentState',source_state,
    'sourceConditionFingerprint',r.source_condition_fingerprint,
    'sourceEvidenceReturnSha256',r.source_evidence_return_sha256,
    'ownerReportedOutcome',r.owner_reported_outcome,
    'ownerOutcomeAcceptedAsReadiness',false,
    'sourceEvidenceUsedAsTriggerOnly',true,
    'independentRetest',true,
    'canonicalReadinessState',r.canonical_readiness_state,
    'canonicalConditionFingerprint',r.canonical_condition_fingerprint,
    'canonicalRawEvidenceFingerprint',r.canonical_raw_evidence_fingerprint,
    'transitionType',r.transition_type,
    'integrityVerified',state='completed',
    'retestProofSha256',r.retest_proof_sha256,
    'readinessChangedByOwnerEvidence',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesRemediation',false,
    'retestedAt',r.retested_at
  );
end;
$layer53_status$;

revoke all on function foundation.get_readiness_dependency_remediation_evidence_retest_status_v1(uuid)
  from public,anon,authenticated,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.get_readiness_dependency_remediation_evidence_retest_status_v1(uuid)
  to foundation_runtime,service_role;
