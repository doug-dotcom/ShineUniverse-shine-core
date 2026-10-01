-- Foundation Layer 106: read-only bounded Layer-97 execution summary.

create or replace function foundation.get_case_audit_layer102_reconcile_exec_summary_v1(
  p_environment text default 'production',
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer106_summary$
declare
  v_items jsonb := '[]'::jsonb;
  v_total integer := 0;
  v_executed integer := 0;
  v_denied integer := 0;
  v_failed integer := 0;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_limit is null
     or p_limit<1
     or p_limit>100 then
    raise exception 'case-audit-layer97-reconcile-exec-summary-input-invalid';
  end if;

  select
    count(*),
    count(*) filter (where event_type='executed'),
    count(*) filter (where event_type='denied'),
    count(*) filter (where event_type='failed')
  into v_total,v_executed,v_denied,v_failed
  from foundation.case_audit_layer102_reconcile_exec_events
  where environment=p_environment;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'eventId',x.event_id,
        'targetLayer101EventId',x.target_layer101_event_id,
        'coverageIncidentEventId',x.coverage_incident_event_id,
        'actionKey',x.action_key,
        'causeClass',x.cause_class,
        'eventType',x.event_type,
        'reasonCode',x.reason_code,
        'policyFingerprint',x.policy_fingerprint,
        'actionResult',x.action_result,
        'requestedAt',x.requested_at
      )
      order by x.event_sequence desc
    ),
    '[]'::jsonb
  )
  into v_items
  from (
    select *
    from foundation.case_audit_layer102_reconcile_exec_events
    where environment=p_environment
    order by event_sequence desc
    limit p_limit
  ) x;

  return jsonb_build_object(
    'foundationCaseAuditLayer102ReconciliationExecutorSummary',
      'shine-foundation/case-audit-layer102-reconciliation-executor-summary-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'totalCount',v_total,
    'executedCount',v_executed,
    'deniedCount',v_denied,
    'failedCount',v_failed,
    'visibleCount',jsonb_array_length(v_items),
    'hasMore',v_total>jsonb_array_length(v_items),
    'items',v_items,
    'directLayer102ServiceRoleBypassAllowed',false,
    'layer101RerunPerformed',false,
    'layer97RerunPerformed',false,
    'layer91RerunPerformed',false,
    'layer87RerunPerformed',false,
    'layer86RerunPerformed',false,
    'layer82RerunPerformed',false,
    'layer81RerunPerformed',false,
    'verificationRerunPerformed',false,
    'evidenceMutationPerformed',false,
    'layer102ReceiptRewritePerformed',false,
    'layer101ReceiptRewritePerformed',false,
    'layer97ReceiptRewritePerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false
  );
end;
$layer106_summary$;

revoke all on function foundation.get_case_audit_layer102_reconcile_exec_summary_v1(
  text,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_case_audit_layer102_reconcile_exec_summary_v1(
  text,integer
) to foundation_runtime,service_role;
