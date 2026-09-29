-- Foundation Layer 55: Defence owner reconciliation receipts.
-- Gives the addressed Defence owner a least-privilege, read-only projection of
-- completed integrity-verified Layer-54 reconciliation outcomes for its own handoffs.
-- No underlying ledger SELECT, mutation, approval or execution authority is granted.

create or replace function foundation.get_readiness_dependency_remediation_owner_outcome_receipts_v1(
  p_environment text default 'production',
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $layer55_receipts$
declare
  rec record;
  reconciliation_status jsonb;
  handoff_status jsonb;
  items jsonb := '[]'::jsonb;
  receipt_count integer := 0;
  visible_count integer := 0;
  invalid_count integer := 0;
begin
  if p_environment is null or btrim(p_environment)='' then
    raise exception 'readiness-owner-outcome-receipts-environment-required';
  end if;

  if p_limit is null or p_limit<1 or p_limit>100 then
    raise exception 'readiness-owner-outcome-receipts-limit-invalid';
  end if;

  for rec in
    select
      h.handoff_id,
      h.proposal_id,
      h.readiness_incident_event_id,
      h.environment,
      h.owner_component,
      h.dependency_service_id,
      h.routed_scopes,
      h.condition_fingerprint as handoff_condition_fingerprint,
      h.routing_fingerprint,
      h.created_at as handoff_created_at,
      e.evidence_return_id,
      e.owner_reported_outcome,
      e.returned_at,
      r.evidence_retest_id,
      r.retest_cycle_id,
      r.canonical_readiness_state,
      r.canonical_condition_fingerprint,
      r.retested_at,
      x.reconciliation_id,
      x.canonical_outcome,
      x.verdict,
      x.reason_code,
      x.source_readiness_state,
      x.source_condition_fingerprint,
      x.reconciliation_sha256,
      x.reconciled_at
    from foundation.readiness_dependency_remediation_handoffs h
    join foundation.readiness_dependency_remediation_evidence_returns e
      on e.handoff_id=h.handoff_id
    join foundation.readiness_dependency_remediation_evidence_retests r
      on r.evidence_return_id=e.evidence_return_id
    join foundation.readiness_dependency_remediation_outcome_reconciliations x
      on x.evidence_retest_id=r.evidence_retest_id
    where h.environment=p_environment
      and h.owner_component='universe'
      and h.dependency_service_id='foundation.defence'
    order by x.reconciliation_sequence desc
  loop
    reconciliation_status :=
      foundation.get_readiness_dependency_remediation_outcome_reconciliation_status_v1(
        rec.evidence_retest_id
      );

    if reconciliation_status->>'state'<>'completed'
       or coalesce(reconciliation_status->>'integrityVerified','false')<>'true'
       or reconciliation_status->>'reconciliationId'
            is distinct from rec.reconciliation_id::text then
      invalid_count := invalid_count + 1;
      continue;
    end if;

    receipt_count := receipt_count + 1;

    if visible_count<p_limit then
      handoff_status :=
        foundation.get_readiness_dependency_remediation_handoff_status_v1(
          rec.handoff_id
        );

      items := items || jsonb_build_array(
        jsonb_build_object(
          'handoffId',rec.handoff_id,
          'proposalId',rec.proposal_id,
          'sourceReadinessIncidentEventId',rec.readiness_incident_event_id,
          'environment',rec.environment,
          'ownerComponent',rec.owner_component,
          'dependencyServiceId',rec.dependency_service_id,
          'routedScopes',rec.routed_scopes,
          'handoffState',coalesce(handoff_status->>'state','unknown'),
          'handoffConditionFingerprint',rec.handoff_condition_fingerprint,
          'routingFingerprint',rec.routing_fingerprint,
          'evidenceReturnId',rec.evidence_return_id,
          'ownerReportedOutcome',rec.owner_reported_outcome,
          'evidenceReturnedAt',rec.returned_at,
          'evidenceRetestId',rec.evidence_retest_id,
          'retestCycleId',rec.retest_cycle_id,
          'sourceReadinessState',rec.source_readiness_state,
          'canonicalReadinessState',rec.canonical_readiness_state,
          'canonicalConditionFingerprint',rec.canonical_condition_fingerprint,
          'retestedAt',rec.retested_at,
          'reconciliationId',rec.reconciliation_id,
          'canonicalOutcome',rec.canonical_outcome,
          'verdict',rec.verdict,
          'reasonCode',rec.reason_code,
          'conditionChanged',
            rec.source_condition_fingerprint is distinct
              from rec.canonical_condition_fingerprint,
          'reconciliationSha256',rec.reconciliation_sha256,
          'reconciledAt',rec.reconciled_at,
          'receiptState','verified',
          'integrityVerified',true,
          'readinessChanged',false,
          'incidentClosurePerformed',false,
          'approvalGranted',false,
          'executionAuthorityGranted',false,
          'executesRemediation',false
        )
      );

      visible_count := visible_count + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'foundationReadinessOwnerOutcomeReceipts',
      'shine-foundation/readiness-owner-outcome-receipts-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'ownerComponent','universe',
    'dependencyServiceId','foundation.defence',
    'readerRole','shine_defence_runtime',
    'receiptCount',receipt_count,
    'visibleCount',visible_count,
    'invalidCount',invalid_count,
    'hasMore',receipt_count>visible_count,
    'items',items,
    'readinessChanged',false,
    'incidentClosurePerformed',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesRemediation',false
  );
end;
$layer55_receipts$;

revoke all on function foundation.get_readiness_dependency_remediation_owner_outcome_receipts_v1(
  text,integer
) from public,anon,authenticated,foundation_runtime,foundation_gateway,service_role;
grant execute on function foundation.get_readiness_dependency_remediation_owner_outcome_receipts_v1(
  text,integer
) to shine_defence_runtime;
