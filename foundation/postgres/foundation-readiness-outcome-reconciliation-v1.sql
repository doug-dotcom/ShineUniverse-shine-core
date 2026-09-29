-- Foundation Layer 54: owner-vs-canonical remediation outcome reconciliation.
-- Compares a Layer-52 owner report with the Layer-53 independent Foundation retest.
-- Reconciliation is append-only evidence only: it does not alter readiness, close an
-- incident, approve work, or execute remediation.

create table foundation.readiness_dependency_remediation_outcome_reconciliations(
  reconciliation_sequence bigint generated always as identity primary key,
  reconciliation_id uuid not null unique default gen_random_uuid(),
  evidence_retest_id uuid not null unique
    references foundation.readiness_dependency_remediation_evidence_retests(evidence_retest_id),
  evidence_return_id uuid not null
    references foundation.readiness_dependency_remediation_evidence_returns(evidence_return_id),
  retest_cycle_id uuid not null
    references foundation.foundation_readiness_retest_cycles(cycle_id),
  source_readiness_incident_event_id uuid not null
    references foundation.foundation_readiness_incident_events(event_id),
  environment text not null,
  owner_reported_outcome text not null
    check(owner_reported_outcome in ('resolved','improved','unchanged','worsened','inconclusive')),
  source_readiness_state text not null
    check(source_readiness_state in ('ready','restricted','degraded','not-ready','unknown')),
  canonical_readiness_state text not null
    check(canonical_readiness_state in ('ready','restricted','degraded','not-ready','unknown')),
  canonical_outcome text not null
    check(canonical_outcome in ('resolved','improved','unchanged','worsened','inconclusive')),
  verdict text not null
    check(verdict in ('confirmed','contradicted','unresolved')),
  reason_code text not null
    check(reason_code ~ '^[a-z0-9][a-z0-9._:-]*$'),
  source_condition_fingerprint text not null
    check(source_condition_fingerprint ~ '^[a-f0-9]{32}$'),
  canonical_condition_fingerprint text not null
    check(canonical_condition_fingerprint ~ '^[a-f0-9]{32}$'),
  source_evidence_return_sha256 text not null
    check(source_evidence_return_sha256 ~ '^[a-f0-9]{64}$'),
  source_retest_proof_sha256 text not null
    check(source_retest_proof_sha256 ~ '^[a-f0-9]{64}$'),
  reconciliation jsonb not null check(jsonb_typeof(reconciliation)='object'),
  reconciliation_sha256 text not null check(reconciliation_sha256 ~ '^[a-f0-9]{64}$'),
  reconciled_at timestamptz not null,
  recorded_at timestamptz not null default now()
);

alter table foundation.readiness_dependency_remediation_outcome_reconciliations
  enable row level security;

create policy foundation_runtime_readiness_outcome_reconciliations_select
on foundation.readiness_dependency_remediation_outcome_reconciliations
for select to foundation_runtime using(true);

revoke all on foundation.readiness_dependency_remediation_outcome_reconciliations
  from public,anon,authenticated,foundation_gateway,service_role,shine_defence_runtime;
grant select on foundation.readiness_dependency_remediation_outcome_reconciliations
  to foundation_runtime,service_role;

create index readiness_outcome_reconciliations_evidence_return_idx
  on foundation.readiness_dependency_remediation_outcome_reconciliations(evidence_return_id);
create index readiness_outcome_reconciliations_retest_cycle_idx
  on foundation.readiness_dependency_remediation_outcome_reconciliations(retest_cycle_id);
create index readiness_outcome_reconciliations_incident_idx
  on foundation.readiness_dependency_remediation_outcome_reconciliations(source_readiness_incident_event_id);

create trigger readiness_dependency_remediation_outcome_reconciliations_append_only
before update or delete on foundation.readiness_dependency_remediation_outcome_reconciliations
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.classify_readiness_dependency_remediation_outcome_v1(
  p_owner_reported_outcome text,
  p_source_readiness_state text,
  p_canonical_readiness_state text,
  p_source_condition_fingerprint text,
  p_canonical_condition_fingerprint text
)
returns jsonb
language plpgsql
immutable
security invoker
set search_path=''
as $layer54_classify$
declare
  source_rank integer;
  canonical_rank integer;
  canonical_outcome text;
  verdict text;
  reason_code text;
begin
  if p_owner_reported_outcome not in ('resolved','improved','unchanged','worsened','inconclusive') then
    raise exception 'readiness-outcome-reconciliation-owner-outcome-invalid';
  end if;

  if p_source_readiness_state not in ('ready','restricted','degraded','not-ready','unknown')
     or p_canonical_readiness_state not in ('ready','restricted','degraded','not-ready','unknown') then
    raise exception 'readiness-outcome-reconciliation-readiness-state-invalid';
  end if;

  if p_source_condition_fingerprint is null
     or p_source_condition_fingerprint !~ '^[a-f0-9]{32}$'
     or p_canonical_condition_fingerprint is null
     or p_canonical_condition_fingerprint !~ '^[a-f0-9]{32}$' then
    raise exception 'readiness-outcome-reconciliation-condition-fingerprint-invalid';
  end if;

  source_rank:=case p_source_readiness_state
    when 'ready' then 0
    when 'restricted' then 1
    when 'degraded' then 2
    when 'not-ready' then 3
    when 'unknown' then 4
  end;

  canonical_rank:=case p_canonical_readiness_state
    when 'ready' then 0
    when 'restricted' then 1
    when 'degraded' then 2
    when 'not-ready' then 3
    when 'unknown' then 4
  end;

  canonical_outcome:=case
    when p_source_readiness_state='unknown'
      or p_canonical_readiness_state='unknown' then 'inconclusive'
    when p_canonical_readiness_state='ready' then 'resolved'
    when canonical_rank<source_rank then 'improved'
    when canonical_rank>source_rank then 'worsened'
    else 'unchanged'
  end;

  verdict:=case
    when p_owner_reported_outcome='inconclusive'
      or canonical_outcome='inconclusive' then 'unresolved'
    when p_owner_reported_outcome=canonical_outcome then 'confirmed'
    when p_owner_reported_outcome='improved'
      and canonical_outcome='resolved' then 'confirmed'
    else 'contradicted'
  end;

  reason_code:=case
    when verdict='confirmed'
      and p_owner_reported_outcome='improved'
      and canonical_outcome='resolved'
      then 'owner-improvement-confirmed-by-canonical-resolution'
    when verdict='confirmed'
      then 'owner-outcome-confirmed-by-canonical-retest'
    when verdict='unresolved'
      and p_owner_reported_outcome='inconclusive'
      then 'owner-outcome-inconclusive'
    when verdict='unresolved'
      then 'canonical-outcome-inconclusive'
    else 'owner-outcome-contradicted-by-canonical-retest'
  end;

  return jsonb_build_object(
    'canonicalOutcome',canonical_outcome,
    'verdict',verdict,
    'reasonCode',reason_code,
    'sourceReadinessRank',source_rank,
    'canonicalReadinessRank',canonical_rank,
    'readinessRankDelta',canonical_rank-source_rank,
    'conditionChanged',
      p_source_condition_fingerprint is distinct from p_canonical_condition_fingerprint
  );
end;
$layer54_classify$;

revoke all on function foundation.classify_readiness_dependency_remediation_outcome_v1(
  text,text,text,text,text
) from public,anon,authenticated,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.classify_readiness_dependency_remediation_outcome_v1(
  text,text,text,text,text
) to foundation_runtime,service_role;


create or replace function foundation.reconcile_readiness_dependency_remediation_outcome_v1(
  p_evidence_retest_id uuid,
  p_reconciled_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $layer54_reconcile$
declare
  r foundation.readiness_dependency_remediation_evidence_retests%rowtype;
  e foundation.readiness_dependency_remediation_evidence_returns%rowtype;
  i foundation.foundation_readiness_incident_events%rowtype;
  existing foundation.readiness_dependency_remediation_outcome_reconciliations%rowtype;
  retest_status jsonb;
  classification jsonb;
  doc jsonb;
  doc_hash text;
  rid uuid;
begin
  if p_evidence_retest_id is null then
    raise exception 'readiness-outcome-reconciliation-evidence-retest-required';
  end if;

  if p_reconciled_at<now()-interval '5 minutes'
     or p_reconciled_at>now()+interval '5 minutes' then
    raise exception 'readiness-outcome-reconciliation-time-invalid';
  end if;

  select * into r
  from foundation.readiness_dependency_remediation_evidence_retests
  where evidence_retest_id=p_evidence_retest_id;

  if r.evidence_retest_id is null then
    return jsonb_build_object(
      'foundationReadinessOutcomeReconciliation',
        'shine-foundation/readiness-remediation-outcome-reconciliation-response-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','readiness-remediation-evidence-retest-not-found',
      'readinessChanged',false,
      'incidentClosurePerformed',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesRemediation',false
    );
  end if;

  select * into existing
  from foundation.readiness_dependency_remediation_outcome_reconciliations
  where evidence_retest_id=r.evidence_retest_id;

  if existing.reconciliation_id is not null then
    return jsonb_build_object(
      'foundationReadinessOutcomeReconciliation',
        'shine-foundation/readiness-remediation-outcome-reconciliation-response-v1',
      'schemaVersion','1.0.0',
      'status','existing',
      'reconciliationId',existing.reconciliation_id,
      'evidenceRetestId',existing.evidence_retest_id,
      'ownerReportedOutcome',existing.owner_reported_outcome,
      'canonicalOutcome',existing.canonical_outcome,
      'verdict',existing.verdict,
      'reasonCode',existing.reason_code,
      'reconciliationSha256',existing.reconciliation_sha256,
      'readinessChanged',false,
      'incidentClosurePerformed',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesRemediation',false
    );
  end if;

  retest_status:=
    foundation.get_readiness_dependency_remediation_evidence_retest_status_v1(
      r.evidence_return_id
    );

  if retest_status->>'state'<>'completed'
     or coalesce(retest_status->>'integrityVerified','false')<>'true'
     or retest_status->>'evidenceRetestId' is distinct from r.evidence_retest_id::text then
    return jsonb_build_object(
      'foundationReadinessOutcomeReconciliation',
        'shine-foundation/readiness-remediation-outcome-reconciliation-response-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','readiness-remediation-evidence-retest-not-verifiable',
      'evidenceRetestState',retest_status->>'state',
      'readinessChanged',false,
      'incidentClosurePerformed',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesRemediation',false
    );
  end if;

  select * into e
  from foundation.readiness_dependency_remediation_evidence_returns
  where evidence_return_id=r.evidence_return_id;

  if e.evidence_return_id is null then
    raise exception 'readiness-outcome-reconciliation-evidence-return-missing';
  end if;

  select * into i
  from foundation.foundation_readiness_incident_events
  where event_id=e.readiness_incident_event_id;

  if i.event_id is null then
    raise exception 'readiness-outcome-reconciliation-source-incident-missing';
  end if;

  if e.evidence_return_sha256 is distinct from r.source_evidence_return_sha256
     or e.condition_fingerprint is distinct from r.source_condition_fingerprint
     or e.owner_reported_outcome is distinct from r.owner_reported_outcome then
    raise exception 'readiness-outcome-reconciliation-source-binding-mismatch';
  end if;

  classification:=
    foundation.classify_readiness_dependency_remediation_outcome_v1(
      r.owner_reported_outcome,
      i.readiness_state,
      r.canonical_readiness_state,
      r.source_condition_fingerprint,
      r.canonical_condition_fingerprint
    );

  doc:=jsonb_build_object(
    'readinessDependencyRemediationOutcomeReconciliation',
      'shine-foundation/readiness-dependency-remediation-outcome-reconciliation-v1',
    'schemaVersion','1.0.0',
    'evidenceRetestId',r.evidence_retest_id,
    'evidenceReturnId',r.evidence_return_id,
    'retestCycleId',r.retest_cycle_id,
    'sourceReadinessIncidentEventId',i.event_id,
    'environment',r.environment,
    'ownerReportedOutcome',r.owner_reported_outcome,
    'sourceReadinessState',i.readiness_state,
    'canonicalReadinessState',r.canonical_readiness_state,
    'canonicalOutcome',classification->>'canonicalOutcome',
    'verdict',classification->>'verdict',
    'reasonCode',classification->>'reasonCode',
    'sourceReadinessRank',(classification->>'sourceReadinessRank')::integer,
    'canonicalReadinessRank',(classification->>'canonicalReadinessRank')::integer,
    'readinessRankDelta',(classification->>'readinessRankDelta')::integer,
    'conditionChanged',(classification->>'conditionChanged')::boolean,
    'sourceConditionFingerprint',r.source_condition_fingerprint,
    'canonicalConditionFingerprint',r.canonical_condition_fingerprint,
    'sourceEvidenceReturnSha256',e.evidence_return_sha256,
    'sourceRetestProofSha256',r.retest_proof_sha256,
    'ownerOutcomeChangesReadiness',false,
    'reconciliationChangesReadiness',false,
    'incidentClosurePerformed',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesRemediation',false,
    'reconciledAt',p_reconciled_at
  );

  doc_hash:=encode(
    extensions.digest(convert_to(doc::text,'UTF8'),'sha256'),
    'hex'
  );

  insert into foundation.readiness_dependency_remediation_outcome_reconciliations(
    evidence_retest_id,evidence_return_id,retest_cycle_id,
    source_readiness_incident_event_id,environment,owner_reported_outcome,
    source_readiness_state,canonical_readiness_state,canonical_outcome,
    verdict,reason_code,source_condition_fingerprint,
    canonical_condition_fingerprint,source_evidence_return_sha256,
    source_retest_proof_sha256,reconciliation,reconciliation_sha256,reconciled_at
  )
  values(
    r.evidence_retest_id,r.evidence_return_id,r.retest_cycle_id,
    i.event_id,r.environment,r.owner_reported_outcome,
    i.readiness_state,r.canonical_readiness_state,
    classification->>'canonicalOutcome',classification->>'verdict',
    classification->>'reasonCode',r.source_condition_fingerprint,
    r.canonical_condition_fingerprint,e.evidence_return_sha256,
    r.retest_proof_sha256,doc,doc_hash,p_reconciled_at
  )
  returning reconciliation_id into rid;

  return jsonb_build_object(
    'foundationReadinessOutcomeReconciliation',
      'shine-foundation/readiness-remediation-outcome-reconciliation-response-v1',
    'schemaVersion','1.0.0',
    'status','recorded',
    'reconciliationId',rid,
    'evidenceRetestId',r.evidence_retest_id,
    'ownerReportedOutcome',r.owner_reported_outcome,
    'canonicalOutcome',classification->>'canonicalOutcome',
    'verdict',classification->>'verdict',
    'reasonCode',classification->>'reasonCode',
    'conditionChanged',(classification->>'conditionChanged')::boolean,
    'reconciliationSha256',doc_hash,
    'readinessChanged',false,
    'incidentClosurePerformed',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesRemediation',false
  );
end;
$layer54_reconcile$;

revoke all on function foundation.reconcile_readiness_dependency_remediation_outcome_v1(
  uuid,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.reconcile_readiness_dependency_remediation_outcome_v1(
  uuid,timestamptz
) to service_role;


create or replace function foundation.get_readiness_dependency_remediation_outcome_reconciliation_status_v1(
  p_evidence_retest_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $layer54_status$
declare
  x foundation.readiness_dependency_remediation_outcome_reconciliations%rowtype;
  expected_hash text;
  retest_status jsonb;
  state text;
begin
  select * into x
  from foundation.readiness_dependency_remediation_outcome_reconciliations
  where evidence_retest_id=p_evidence_retest_id;

  if x.reconciliation_id is null then
    return jsonb_build_object(
      'foundationReadinessOutcomeReconciliationStatus',
        'shine-foundation/readiness-remediation-outcome-reconciliation-status-v1',
      'schemaVersion','1.0.0',
      'state','pending',
      'evidenceRetestId',p_evidence_retest_id,
      'readinessChanged',false,
      'incidentClosurePerformed',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesRemediation',false
    );
  end if;

  expected_hash:=encode(
    extensions.digest(convert_to(x.reconciliation::text,'UTF8'),'sha256'),
    'hex'
  );

  retest_status:=
    foundation.get_readiness_dependency_remediation_evidence_retest_status_v1(
      x.evidence_return_id
    );

  state:=case
    when expected_hash is distinct from x.reconciliation_sha256 then 'invalid'
    when retest_status->>'state'<>'completed'
      or coalesce(retest_status->>'integrityVerified','false')<>'true'
      then 'invalid'
    when retest_status->>'evidenceRetestId' is distinct from x.evidence_retest_id::text
      then 'invalid'
    else 'completed'
  end;

  return jsonb_build_object(
    'foundationReadinessOutcomeReconciliationStatus',
      'shine-foundation/readiness-remediation-outcome-reconciliation-status-v1',
    'schemaVersion','1.0.0',
    'state',state,
    'reconciliationId',x.reconciliation_id,
    'evidenceRetestId',x.evidence_retest_id,
    'evidenceReturnId',x.evidence_return_id,
    'retestCycleId',x.retest_cycle_id,
    'sourceReadinessIncidentEventId',x.source_readiness_incident_event_id,
    'ownerReportedOutcome',x.owner_reported_outcome,
    'sourceReadinessState',x.source_readiness_state,
    'canonicalReadinessState',x.canonical_readiness_state,
    'canonicalOutcome',x.canonical_outcome,
    'verdict',x.verdict,
    'reasonCode',x.reason_code,
    'conditionChanged',
      x.source_condition_fingerprint is distinct from x.canonical_condition_fingerprint,
    'integrityVerified',state='completed',
    'reconciliationSha256',x.reconciliation_sha256,
    'readinessChanged',false,
    'incidentClosurePerformed',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesRemediation',false,
    'reconciledAt',x.reconciled_at
  );
end;
$layer54_status$;

revoke all on function foundation.get_readiness_dependency_remediation_outcome_reconciliation_status_v1(uuid)
  from public,anon,authenticated,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.get_readiness_dependency_remediation_outcome_reconciliation_status_v1(uuid)
  to foundation_runtime,service_role;
