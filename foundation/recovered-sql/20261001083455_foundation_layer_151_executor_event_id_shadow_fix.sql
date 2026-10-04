
create or replace function foundation.execute_case_audit_overdue_layer147_reconciliation_v1(
  p_layer146_event_id uuid,
  p_environment text default 'production',
  p_requested_at timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_exec foundation.case_audit_layer142_reconcile_exec_events%rowtype;
  v_recon foundation.case_audit_layer146_exec_reconciliations%rowtype;
  v_prior foundation.case_audit_layer147_reconcile_exec_events%rowtype;
  v_decision jsonb;
  v_result jsonb;
  v_event_id uuid;
  v_incident_id uuid;
  v_event_type text;
  v_reason text;
begin
  if p_layer146_event_id is null then
    raise exception 'case-audit-layer147-executor-target-required';
  end if;

  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_requested_at is null
     or p_requested_at<now()-interval '5 minutes'
     or p_requested_at>now()+interval '5 minutes'
     or p_reconciliation_grace_seconds is null
     or p_reconciliation_grace_seconds<60
     or p_reconciliation_grace_seconds>3600 then
    raise exception 'case-audit-layer147-executor-input-invalid';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_layer146_event_id::text,151)
  );

  select x.* into v_exec
  from foundation.case_audit_layer142_reconcile_exec_events x
  where x.event_id=p_layer146_event_id
    and x.environment=p_environment;

  if v_exec.event_id is null then
    return jsonb_build_object(
      'status','not-applicable',
      'reasonCode','case-audit-layer147-target-not-found',
      'boundedLayer147ReconcilerOnly',true,
      'upstreamRerunPerformed',false,
      'evidenceMutationPerformed',false
    );
  end if;

  select x.* into v_prior
  from foundation.case_audit_layer147_reconcile_exec_events x
  where x.target_layer146_event_id=v_exec.event_id
    and x.event_type='executed'
  order by x.event_sequence desc
  limit 1;

  if v_prior.event_id is not null then
    return jsonb_build_object(
      'status','existing',
      'eventId',v_prior.event_id,
      'coverageIncidentEventId',v_prior.coverage_incident_event_id,
      'actionResult',v_prior.action_result,
      'boundedLayer147ReconcilerOnly',true,
      'upstreamRerunPerformed',false,
      'evidenceMutationPerformed',false
    );
  end if;

  select x.* into v_recon
  from foundation.case_audit_layer146_exec_reconciliations x
  where x.layer146_event_id=v_exec.event_id;

  v_decision:=foundation.evaluate_case_audit_layer147_coverage_incident_response_v1(
    'run-independent-layer147-reconciliation',
    p_environment,p_requested_at,p_reconciliation_grace_seconds
  );

  begin
    v_incident_id:=nullif(v_decision#>>'{cause,currentIncidentEventId}','')::uuid;
  exception when invalid_text_representation then
    v_incident_id:=null;
  end;

  if v_exec.event_type<>'executed'
     or v_recon.reconciliation_id is not null
     or p_requested_at-v_exec.requested_at<=make_interval(secs=>p_reconciliation_grace_seconds)
     or v_decision->>'decision'<>'admit'
     or v_decision->>'requiredControl'<>'layer-147-bounded-reconciler'
     or v_decision->>'causeClass'<>'layer147-reconciliation-omission'
     or v_decision->>'incidentState' not in('watching','critical')
     or v_incident_id is null
     or coalesce(v_decision->>'authorityExpansion','true')<>'false'
     or coalesce(v_decision->>'automaticReconciliationAllowed','true')<>'false'
     or coalesce(v_decision->>'automaticRepairAllowed','true')<>'false'
     or coalesce(v_decision->>'upstreamRerunAllowed','true')<>'false'
     or coalesce(v_decision->>'executesAction','true')<>'false' then
    v_event_type:='denied';
    v_reason:='case-audit-layer147-executor-not-admitted';
    v_result:=null;
  else
    v_result:=foundation.run_case_audit_layer146_execution_reconciliation_v1(
      v_exec.event_id,p_requested_at
    );

    if v_result->>'status' in('recorded','existing') then
      v_event_type:='executed';
      v_reason:='case-audit-layer147-reconciliation-ran';
    else
      v_event_type:='failed';
      v_reason:='case-audit-layer147-reconciliation-failed';
      v_result:=null;
    end if;
  end if;

  v_event_id:=gen_random_uuid();

  insert into foundation.case_audit_layer147_reconcile_exec_events(
    event_id,environment,target_layer146_event_id,coverage_incident_event_id,
    action_key,cause_class,event_type,reason_code,decision_snapshot,
    action_result,requested_at
  )
  values(
    v_event_id,p_environment,v_exec.event_id,v_incident_id,
    'run-independent-layer147-reconciliation',
    coalesce(v_decision->>'causeClass','unknown'),
    v_event_type,v_reason,v_decision,v_result,p_requested_at
  );

  return jsonb_build_object(
    'foundationCaseAuditOverdueLayer147ReconciliationExecution',
      'shine-foundation/case-audit-overdue-layer147-reconciliation-execution-v1',
    'schemaVersion','1.0.0',
    'status',v_event_type,
    'eventId',v_event_id,
    'layer146EventId',v_exec.event_id,
    'coverageIncidentEventId',v_incident_id,
    'incidentState',v_decision->>'incidentState',
    'reasonCode',v_reason,
    'actionResult',v_result,
    'boundedLayer147ReconcilerOnly',true,
    'authorityExpansion',false,
    'upstreamRerunPerformed',false,
    'evidenceMutationPerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false
  );
end $$;

revoke all on function foundation.execute_case_audit_overdue_layer147_reconciliation_v1(
  uuid,text,timestamptz,integer
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.execute_case_audit_overdue_layer147_reconciliation_v1(
  uuid,text,timestamptz,integer
) to service_role;
