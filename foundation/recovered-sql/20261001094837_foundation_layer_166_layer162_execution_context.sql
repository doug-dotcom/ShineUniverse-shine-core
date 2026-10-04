
create or replace function foundation.get_case_audit_layer162_execution_context_v1(
  p_layer161_event_id uuid,
  p_environment text,
  p_requested_at timestamptz,
  p_reconciliation_grace_seconds integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_exec foundation.case_audit_layer157_reconcile_exec_events%rowtype;
  v_recon foundation.case_audit_layer161_exec_reconciliations%rowtype;
  v_prior foundation.case_audit_layer162_reconcile_exec_events%rowtype;
  v_gate jsonb;
begin
  select x.* into v_exec
  from foundation.case_audit_layer157_reconcile_exec_events x
  where x.event_id=p_layer161_event_id
    and x.environment=p_environment;

  if v_exec.event_id is null then
    return jsonb_build_object('targetFound',false);
  end if;

  select x.* into v_recon
  from foundation.case_audit_layer161_exec_reconciliations x
  where x.layer161_event_id=v_exec.event_id;

  select x.* into v_prior
  from foundation.case_audit_layer162_reconcile_exec_events x
  where x.target_layer161_event_id=v_exec.event_id
    and x.event_type='executed'
  order by x.event_sequence desc
  limit 1;

  v_gate:=foundation.validate_case_audit_layer162_reconciliation_admission_v1(
    p_environment,p_requested_at,p_reconciliation_grace_seconds
  );

  return jsonb_build_object(
    'targetFound',true,
    'targetEventType',v_exec.event_type,
    'targetRequestedAt',v_exec.requested_at,
    'priorExecutedEventId',v_prior.event_id,
    'existingReconciliationId',v_recon.reconciliation_id,
    'ageEligible',
      p_requested_at-v_exec.requested_at>make_interval(secs=>p_reconciliation_grace_seconds),
    'gate',v_gate
  );
end $$;

revoke all on function foundation.get_case_audit_layer162_execution_context_v1(
  uuid,text,timestamptz,integer
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.get_case_audit_layer162_execution_context_v1(
  uuid,text,timestamptz,integer
) to service_role;
