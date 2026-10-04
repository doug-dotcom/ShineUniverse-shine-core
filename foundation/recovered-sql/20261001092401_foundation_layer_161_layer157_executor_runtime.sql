
create or replace function foundation.execute_case_audit_overdue_layer157_reconciliation_v1(
  p_layer156_event_id uuid,
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
  v_exec foundation.case_audit_layer152_reconcile_exec_events%rowtype;
  v_recon foundation.case_audit_layer156_exec_reconciliations%rowtype;
  v_prior foundation.case_audit_layer157_reconcile_exec_events%rowtype;
  v_gate jsonb;
  v_result jsonb;
  v_event_id uuid;
  v_incident_id uuid;
  v_event_type text;
  v_reason text;
begin
  if p_layer156_event_id is null then
    raise exception 'case-audit-layer157-executor-target-required';
  end if;

  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_requested_at is null
     or p_requested_at<now()-interval '5 minutes'
     or p_requested_at>now()+interval '5 minutes'
     or p_reconciliation_grace_seconds is null
     or p_reconciliation_grace_seconds<60
     or p_reconciliation_grace_seconds>3600 then
    raise exception 'case-audit-layer157-executor-input-invalid';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_layer156_event_id::text,161)
  );

  select x.* into v_exec
  from foundation.case_audit_layer152_reconcile_exec_events x
  where x.event_id=p_layer156_event_id
    and x.environment=p_environment;

  if v_exec.event_id is null then
    return jsonb_build_object(
      'status','not-applicable',
      'reasonCode','case-audit-layer157-target-not-found',
      'boundedLayer157ReconcilerOnly',true,
      'upstreamRerunPerformed',false,
      'evidenceMutationPerformed',false
    );
  end if;

  select x.* into v_prior
  from foundation.case_audit_layer157_reconcile_exec_events x
  where x.target_layer156_event_id=v_exec.event_id
    and x.event_type='executed'
  order by x.event_sequence desc
  limit 1;

  if v_prior.event_id is not null then
    return jsonb_build_object(
      'status','existing',
      'eventId',v_prior.event_id,
      'coverageIncidentEventId',v_prior.coverage_incident_event_id,
      'actionResult',v_prior.action_result,
      'boundedLayer157ReconcilerOnly',true,
      'upstreamRerunPerformed',false,
      'evidenceMutationPerformed',false
    );
  end if;

  select x.* into v_recon
  from foundation.case_audit_layer156_exec_reconciliations x
  where x.layer156_event_id=v_exec.event_id;

  v_gate:=foundation.validate_case_audit_layer157_reconciliation_admission_v1(
    p_environment,p_requested_at,p_reconciliation_grace_seconds
  );

  begin
    v_incident_id:=nullif(v_gate->>'incidentEventId','')::uuid;
  exception when invalid_text_representation then
    v_incident_id:=null;
  end;

  if v_exec.event_type<>'executed'
     or v_recon.reconciliation_id is not null
     or p_requested_at-v_exec.requested_at<=make_interval(secs=>p_reconciliation_grace_seconds)
     or coalesce((v_gate->>'admitted')::boolean,false)<>true
     or v_incident_id is null then
    v_event_type:='denied';
    v_reason:='case-audit-layer157-executor-not-admitted';
    v_result:=null;
  else
    v_result:=foundation.run_case_audit_layer156_execution_reconciliation_v1(
      v_exec.event_id,p_requested_at
    );

    if v_result->>'status' in('recorded','existing') then
      v_event_type:='executed';
      v_reason:='case-audit-layer157-reconciliation-ran';
    else
      v_event_type:='failed';
      v_reason:='case-audit-layer157-reconciliation-failed';
      v_result:=null;
    end if;
  end if;

  v_event_id:=gen_random_uuid();

  insert into foundation.case_audit_layer157_reconcile_exec_events(
    event_id,environment,target_layer156_event_id,coverage_incident_event_id,
    action_key,cause_class,event_type,reason_code,decision_snapshot,
    action_result,requested_at
  )
  values(
    v_event_id,p_environment,v_exec.event_id,v_incident_id,
    'run-independent-layer157-reconciliation',
    coalesce(v_gate->>'causeClass','unknown'),
    v_event_type,v_reason,v_gate,v_result,p_requested_at
  );

  return jsonb_build_object(
    'foundationCaseAuditOverdueLayer157ReconciliationExecution',
      'shine-foundation/case-audit-overdue-layer157-reconciliation-execution-v1',
    'schemaVersion','1.0.0',
    'status',v_event_type,
    'eventId',v_event_id,
    'layer156EventId',v_exec.event_id,
    'coverageIncidentEventId',v_incident_id,
    'incidentState',v_gate->>'incidentState',
    'incidentEvidenceCurrent',v_gate->'incidentEvidenceCurrent',
    'incidentSemanticFingerprint',v_gate->>'incidentSemanticFingerprint',
    'coverageSemanticFingerprint',v_gate->>'coverageSemanticFingerprint',
    'reasonCode',v_reason,
    'actionResult',v_result,
    'boundedLayer157ReconcilerOnly',true,
    'authorityExpansion',false,
    'upstreamRerunPerformed',false,
    'evidenceMutationPerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false
  );
end $$;

revoke all on function foundation.execute_case_audit_overdue_layer157_reconciliation_v1(
  uuid,text,timestamptz,integer
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.execute_case_audit_overdue_layer157_reconciliation_v1(
  uuid,text,timestamptz,integer
) to service_role;
