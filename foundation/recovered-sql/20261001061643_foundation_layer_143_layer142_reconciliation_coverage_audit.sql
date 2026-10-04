
create or replace function foundation.get_case_audit_layer142_reconciliation_coverage_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300,
  p_limit integer default 50
)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if p_environment is null or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
    or p_as_of is null or p_reconciliation_grace_seconds is null
    or p_reconciliation_grace_seconds<60 or p_reconciliation_grace_seconds>3600
    or p_limit is null or p_limit<1 or p_limit>100
 then raise exception 'case-audit-layer142-coverage-input-invalid'; end if;

 with x as(
  select e.event_sequence,e.event_id,e.environment,e.target_layer136_event_id,e.requested_at,
   greatest(0,floor(extract(epoch from(p_as_of-e.requested_at)))::int) age_seconds,
   r.reconciliation_id,r.reconciliation_state,r.reason_code,
   r.reconciliation_proof,r.reconciliation_proof_sha256,r.reconciled_at
  from foundation.case_audit_layer137_reconcile_exec_events e
  left join foundation.case_audit_layer141_exec_reconciliations r
    on r.layer141_event_id=e.event_id
  where e.environment=p_environment and e.event_type='executed' and e.requested_at<=p_as_of
 ), y as(
  select x.*,case
   when reconciliation_id is null and age_seconds<=p_reconciliation_grace_seconds then 'pending'
   when reconciliation_id is null then 'overdue'
   when encode(extensions.digest(convert_to(reconciliation_proof::text,'UTF8'),'sha256'),'hex')
        is distinct from reconciliation_proof_sha256 then 'invalid-reconciliation'
   else reconciliation_state end coverage_state
  from x
 ), t as(
  select count(*)::int total,
   count(*) filter(where reconciliation_id is not null)::int receipts,
   count(*) filter(where coverage_state='reconciled')::int healthy,
   count(*) filter(where coverage_state='pending')::int pending,
   count(*) filter(where coverage_state='overdue')::int overdue,
   count(*) filter(where coverage_state='invalid-reconciliation')::int invalid,
   count(*) filter(where coverage_state='missing-layer137-receipt')::int missing137,
   count(*) filter(where coverage_state='execution-receipt-mismatch')::int mismatch,
   count(*) filter(where coverage_state='policy-drift')::int policy,
   count(*) filter(where coverage_state='incident-state-drift')::int incident_state_drift
  from y
 ), v as(
  select coalesce(jsonb_agg(jsonb_build_object(
   'layer141EventId',z.event_id,
   'targetLayer136EventId',z.target_layer136_event_id,
   'executionRequestedAt',z.requested_at,
   'executionAgeSeconds',z.age_seconds,
   'coverageState',z.coverage_state,
   'layer142ReconciliationId',z.reconciliation_id,
   'layer142ReconciliationState',z.reconciliation_state,
   'reasonCode',z.reason_code,
   'incidentState',z.reconciliation_proof->>'incidentState',
   'reconciledAt',z.reconciled_at
  ) order by z.event_sequence desc),'[]'::jsonb) items
  from(select * from y order by event_sequence desc limit p_limit)z
 )
 select jsonb_build_object(
  'foundationCaseAuditLayer142ReconciliationCoverage','shine-foundation/case-audit-layer142-reconciliation-coverage-v1',
  'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
  'reconciliationGraceSeconds',p_reconciliation_grace_seconds,
  'state',case
   when t.total=0 then 'idle'
   when t.invalid>0 then 'invalid'
   when t.overdue+t.missing137+t.mismatch+t.policy+t.incident_state_drift>0 then 'gap'
   when t.pending>0 then 'pending'
   else 'normal' end,
  'reasonCode',case
   when t.total=0 then 'case-audit-layer142-no-executions'
   when t.invalid>0 then 'case-audit-layer142-receipt-invalid'
   when t.overdue>0 then 'case-audit-layer142-overdue'
   when t.missing137>0 then 'case-audit-layer141-layer137-receipt-missing'
   when t.mismatch>0 then 'case-audit-layer141-receipt-mismatch'
   when t.policy>0 then 'case-audit-layer141-policy-drift'
   when t.incident_state_drift>0 then 'case-audit-layer141-incident-state-drift'
   when t.pending>0 then 'case-audit-layer142-within-grace'
   else 'case-audit-layer142-covered' end,
  'successfulLayer141ExecutionCount',t.total,
  'layer142ReconciliationRequiredCount',t.total,
  'layer142ReconciliationReceiptCount',t.receipts,
  'reconciledCount',t.healthy,'pendingCount',t.pending,'overdueCount',t.overdue,
  'invalidLayer142ReconciliationCount',t.invalid,
  'missingLayer137ReceiptCount',t.missing137,
  'executionReceiptMismatchCount',t.mismatch,
  'policyDriftCount',t.policy,
  'incidentStateDriftCount',t.incident_state_drift,
  'problemCount',t.overdue+t.invalid+t.missing137+t.mismatch+t.policy+t.incident_state_drift,
  'layer142ReconciliationCoveragePercent',case when t.total=0 then 100.00 else round((100.0*t.receipts/t.total)::numeric,2) end,
  'healthyLayer142ReconciliationPercent',case when t.total=0 then 100.00 else round((100.0*t.healthy/t.total)::numeric,2) end,
  'visibleCount',jsonb_array_length(v.items),'hasMore',t.total>jsonb_array_length(v.items),
  'items',v.items,'layer142ProofIntegrityRecomputed',true,'incidentStateDriftIncluded',true,
  'layer142ReconciliationPerformed',false,'upstreamRerunPerformed',false,
  'evidenceMutationPerformed',false,'releaseTruthMutationPerformed',false,
  'incidentHistoryMutationPerformed',false,'mutationPerformed',false
 ) into result from t cross join v;
 return result;
end $$;

revoke all on function foundation.get_case_audit_layer142_reconciliation_coverage_v1(
 text,timestamptz,integer,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.get_case_audit_layer142_reconciliation_coverage_v1(
 text,timestamptz,integer,integer
) to foundation_runtime,service_role;
