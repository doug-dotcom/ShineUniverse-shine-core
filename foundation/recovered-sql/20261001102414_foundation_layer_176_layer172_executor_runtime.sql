
create or replace function foundation.execute_case_audit_overdue_layer172_reconciliation_v1(
  p_layer171_event_id uuid,
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
  v_ctx jsonb;
  v_gate jsonb;
  v_result jsonb;
  v_event_id uuid;
  v_incident_id uuid;
  v_event_type text;
  v_reason text;
begin
  if p_layer171_event_id is null
     or p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_requested_at is null
     or p_requested_at<now()-interval '5 minutes'
     or p_requested_at>now()+interval '5 minutes'
     or p_reconciliation_grace_seconds not between 60 and 3600 then
    raise exception 'case-audit-layer172-executor-input-invalid';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_layer171_event_id::text,176)
  );

  v_ctx:=foundation.get_case_audit_layer172_execution_context_v1(
    p_layer171_event_id,p_environment,p_requested_at,p_reconciliation_grace_seconds
  );

  if coalesce((v_ctx->>'targetFound')::boolean,false)=false then
    return jsonb_build_object(
      'status','not-applicable',
      'reasonCode','case-audit-layer172-target-not-found',
      'boundedLayer172ReconcilerOnly',true
    );
  end if;

  if nullif(v_ctx->>'priorExecutedEventId','') is not null then
    return jsonb_build_object(
      'status','existing',
      'eventId',v_ctx->>'priorExecutedEventId',
      'boundedLayer172ReconcilerOnly',true
    );
  end if;

  v_gate:=v_ctx->'gate';

  begin
    v_incident_id:=nullif(v_gate->>'incidentEventId','')::uuid;
  exception when invalid_text_representation then
    v_incident_id:=null;
  end;

  if v_ctx->>'targetEventType'<>'executed'
     or nullif(v_ctx->>'existingReconciliationId','') is not null
     or coalesce((v_ctx->>'ageEligible')::boolean,false)=false
     or coalesce((v_gate->>'admitted')::boolean,false)=false
     or coalesce((v_gate->>'incidentEvidenceIntegrity')::boolean,false)=false
     or coalesce((v_gate->>'incidentEvidenceCurrent')::boolean,false)=false
     or v_incident_id is null then
    v_event_type:='denied';
    v_reason:='case-audit-layer172-executor-not-admitted';
  else
    v_result:=foundation.run_case_audit_layer171_execution_reconciliation_v1(
      p_layer171_event_id,p_requested_at
    );

    if v_result->>'status' in('recorded','existing') then
      v_event_type:='executed';
      v_reason:='case-audit-layer172-reconciliation-ran';
    else
      v_event_type:='failed';
      v_reason:='case-audit-layer172-reconciliation-failed';
      v_result:=null;
    end if;
  end if;

  v_event_id:=gen_random_uuid();

  insert into foundation.case_audit_layer172_reconcile_exec_events(
    event_id,environment,target_layer171_event_id,coverage_incident_event_id,
    action_key,cause_class,event_type,reason_code,decision_snapshot,
    action_result,requested_at
  )
  values(
    v_event_id,p_environment,p_layer171_event_id,v_incident_id,
    'run-independent-layer172-reconciliation',
    coalesce(v_gate->>'causeClass','unknown'),
    v_event_type,v_reason,v_gate,v_result,p_requested_at
  );

  return jsonb_build_object(
    'foundationCaseAuditOverdueLayer172ReconciliationExecution',
      'shine-foundation/case-audit-overdue-layer172-reconciliation-execution-v1',
    'schemaVersion','1.0.0',
    'status',v_event_type,
    'eventId',v_event_id,
    'layer171EventId',p_layer171_event_id,
    'coverageIncidentEventId',v_incident_id,
    'incidentEvidenceIntegrity',v_gate->'incidentEvidenceIntegrity',
    'incidentEvidenceCurrent',v_gate->'incidentEvidenceCurrent',
    'incidentSemanticFingerprint',v_gate->>'incidentSemanticFingerprint',
    'coverageSemanticFingerprint',v_gate->>'coverageSemanticFingerprint',
    'reasonCode',v_reason,
    'actionResult',v_result,
    'boundedLayer172ReconcilerOnly',true,
    'authorityExpansion',false,
    'upstreamRerunPerformed',false,
    'evidenceMutationPerformed',false
  );
end $$;

revoke all on function foundation.execute_case_audit_overdue_layer172_reconciliation_v1(
  uuid,text,timestamptz,integer
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.execute_case_audit_overdue_layer172_reconciliation_v1(
  uuid,text,timestamptz,integer
) to service_role;
