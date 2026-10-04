
create or replace function foundation.get_case_audit_layer127_reconciliation_coverage_v1(
 p_environment text default 'production',p_as_of timestamptz default now(),p_reconciliation_grace_seconds integer default 300,p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if p_environment is null or p_environment !~ '^[a-z0-9][a-z0-9._-]*$' or p_as_of is null or p_reconciliation_grace_seconds<60 or p_reconciliation_grace_seconds>3600 or p_limit<1 or p_limit>100 then raise exception 'case-audit-layer127-coverage-input-invalid';end if;
 with x as(
  select e.event_sequence,e.event_id,e.environment,e.target_layer121_event_id,e.requested_at,greatest(0,floor(extract(epoch from(p_as_of-e.requested_at)))::int) age_seconds,
   r.reconciliation_id,r.reconciliation_state,r.reason_code,r.reconciliation_proof,r.reconciliation_proof_sha256,r.reconciled_at
  from foundation.case_audit_layer122_reconcile_exec_events e
  left join foundation.case_audit_layer126_exec_reconciliations r on r.layer126_event_id=e.event_id
  where e.environment=p_environment and e.event_type='executed' and e.requested_at<=p_as_of
 ),y as(
  select x.*,case when reconciliation_id is null and age_seconds<=p_reconciliation_grace_seconds then 'pending'
   when reconciliation_id is null then 'overdue'
   when encode(extensions.digest(convert_to(reconciliation_proof::text,'UTF8'),'sha256'),'hex') is distinct from reconciliation_proof_sha256 then 'invalid-reconciliation'
   else reconciliation_state end coverage_state from x
 ),t as(
  select count(*)::int total,count(*) filter(where reconciliation_id is not null)::int receipts,count(*) filter(where coverage_state='reconciled')::int healthy,
   count(*) filter(where coverage_state='pending')::int pending,count(*) filter(where coverage_state='overdue')::int overdue,count(*) filter(where coverage_state='invalid-reconciliation')::int invalid,
   count(*) filter(where coverage_state='missing-layer122-receipt')::int missing122,count(*) filter(where coverage_state='execution-receipt-mismatch')::int mismatch,count(*) filter(where coverage_state='policy-drift')::int policy from y
 ),v as(
  select coalesce(jsonb_agg(jsonb_build_object('layer126EventId',z.event_id,'targetLayer121EventId',z.target_layer121_event_id,'coverageState',z.coverage_state,'layer127ReconciliationId',z.reconciliation_id,'layer127ReconciliationState',z.reconciliation_state,'reconciledAt',z.reconciled_at) order by z.event_sequence desc),'[]'::jsonb)items from(select * from y order by event_sequence desc limit p_limit)z
 )
 select jsonb_build_object('foundationCaseAuditLayer127ReconciliationCoverage','shine-foundation/case-audit-layer127-reconciliation-coverage-v1','schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
 'state',case when t.total=0 then 'idle' when t.invalid>0 then 'invalid' when t.overdue+t.missing122+t.mismatch+t.policy>0 then 'gap' when t.pending>0 then 'pending' else 'normal' end,
 'successfulLayer126ExecutionCount',t.total,'layer127ReconciliationRequiredCount',t.total,'layer127ReconciliationReceiptCount',t.receipts,'reconciledCount',t.healthy,'pendingCount',t.pending,'overdueCount',t.overdue,'invalidLayer127ReconciliationCount',t.invalid,'missingLayer122ReceiptCount',t.missing122,'executionReceiptMismatchCount',t.mismatch,'policyDriftCount',t.policy,'problemCount',t.overdue+t.invalid+t.missing122+t.mismatch+t.policy,
 'layer127ReconciliationCoveragePercent',case when t.total=0 then 100.00 else round((100.0*t.receipts/t.total)::numeric,2)end,'healthyLayer127ReconciliationPercent',case when t.total=0 then 100.00 else round((100.0*t.healthy/t.total)::numeric,2)end,
 'items',v.items,'layer127ProofIntegrityRecomputed',true,'layer127ReconciliationPerformed',false,'upstreamRerunPerformed',false,'evidenceMutationPerformed',false,'releaseTruthMutationPerformed',false,'incidentHistoryMutationPerformed',false,'mutationPerformed',false)into result from t cross join v;
 return result;
end $$;
revoke all on function foundation.get_case_audit_layer127_reconciliation_coverage_v1(text,timestamptz,integer,integer) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.get_case_audit_layer127_reconciliation_coverage_v1(text,timestamptz,integer,integer) to foundation_runtime,service_role;
