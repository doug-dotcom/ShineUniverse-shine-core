-- Foundation Layer 106: exact-target bounded executor for Layer-97 reconciliation.

create or replace function foundation.execute_case_audit_overdue_layer102_reconciliation_v1(
  p_layer101_event_id uuid,
  p_environment text default 'production',
  p_requested_at timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer106_execute$
declare
  v_target foundation.case_audit_layer97_reconcile_exec_events%rowtype;
  v_prior foundation.case_audit_layer102_reconcile_exec_events%rowtype;
  v_l97 foundation.case_audit_layer101_exec_reconciliations%rowtype;
  v_decision jsonb;
  v_incident jsonb;
  v_before jsonb;
  v_after jsonb;
  v_target_snapshot jsonb;
  v_fp text;
  v_incident_event_id uuid;
  v_age integer;
  v_result jsonb;
  v_event_id uuid;
  v_reason text;
  v_error text;
begin
  if p_layer101_event_id is null then
    raise exception 'case-audit-overdue-layer102-reconciliation-event-id-required';
  end if;

  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_requested_at is null
     or p_requested_at<now()-interval '5 minutes'
     or p_requested_at>now()+interval '5 minutes'
     or p_reconciliation_grace_seconds is null
     or p_reconciliation_grace_seconds<60
     or p_reconciliation_grace_seconds>3600 then
    raise exception 'case-audit-overdue-layer102-reconciliation-input-invalid';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_layer101_event_id::text,106)
  );

  select * into v_target
  from foundation.case_audit_layer102_reconcile_exec_events
  where event_id=p_layer101_event_id
    and environment=p_environment;

  if v_target.event_id is null then
    return jsonb_build_object(
      'foundationCaseAuditOverdueLayer102ReconciliationExecution',
        'shine-foundation/case-audit-overdue-layer102-reconciliation-execution-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'layer101EventId',p_layer101_event_id,
      'environment',p_environment,
      'reasonCode','case-audit-overdue-layer102-reconciliation-target-not-found',
      'boundedLayer102ReconcilerOnly',true,
      'layer96RerunPerformed',false,
      'layer92RerunPerformed',false,
      'layer91RerunPerformed',false,
      'layer87RerunPerformed',false,
      'layer86RerunPerformed',false,
      'layer82RerunPerformed',false,
      'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,
      'evidenceMutationPerformed',false,
      'layer97ReceiptRewritePerformed',false,
      'layer96ReceiptRewritePerformed',false,
      'layer92ReceiptRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false
    );
  end if;

  select * into v_prior
  from foundation.case_audit_layer102_reconcile_exec_events
  where target_layer101_event_id=v_target.event_id
    and event_type='executed'
  order by event_sequence desc
  limit 1;

  if v_prior.event_id is not null then
    return jsonb_build_object(
      'foundationCaseAuditOverdueLayer102ReconciliationExecution',
        'shine-foundation/case-audit-overdue-layer102-reconciliation-execution-v1',
      'schemaVersion','1.0.0',
      'status','existing',
      'eventId',v_prior.event_id,
      'layer101EventId',v_prior.target_layer101_event_id,
      'environment',v_prior.environment,
      'incidentEventId',v_prior.coverage_incident_event_id,
      'reasonCode',v_prior.reason_code,
      'policyFingerprint',v_prior.policy_fingerprint,
      'actionResult',v_prior.action_result,
      'boundedLayer102ReconcilerOnly',true,
      'layer96RerunPerformed',false,
      'layer92RerunPerformed',false,
      'layer91RerunPerformed',false,
      'layer87RerunPerformed',false,
      'layer86RerunPerformed',false,
      'layer82RerunPerformed',false,
      'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,
      'evidenceMutationPerformed',false,
      'layer97ReceiptRewritePerformed',false,
      'layer96ReceiptRewritePerformed',false,
      'layer92ReceiptRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false
    );
  end if;

  v_age := greatest(
    0,
    floor(extract(epoch from (p_requested_at-v_target.requested_at)))::integer
  );

  select * into v_l97
  from foundation.case_audit_layer101_exec_reconciliations
  where layer101_event_id=v_target.event_id;

  v_incident := foundation.get_case_audit_layer102_coverage_incident_summary_v1(
    p_environment,p_requested_at,p_reconciliation_grace_seconds
  );

  v_decision := foundation.evaluate_case_audit_layer102_coverage_incident_response_v1(
    'run-independent-layer102-reconciliation',
    p_environment,p_requested_at,p_reconciliation_grace_seconds
  );

  v_before := foundation.get_case_audit_layer102_reconciliation_coverage_v1(
    p_environment,p_requested_at,p_reconciliation_grace_seconds,100
  );

  begin
    v_incident_event_id := nullif(v_incident#>>'{currentEvent,eventId}','')::uuid;
  exception when invalid_text_representation then
    v_incident_event_id := null;
  end;

  v_target_snapshot := jsonb_build_object(
    'layer101EventId',v_target.event_id,
    'targetLayer96EventId',v_target.target_layer91_event_id,
    'coverageIncidentEventId',v_target.coverage_incident_event_id,
    'actionKey',v_target.action_key,
    'causeClass',v_target.cause_class,
    'policyFingerprint',v_target.policy_fingerprint,
    'eventType',v_target.event_type,
    'reasonCode',v_target.reason_code,
    'requestedAt',v_target.requested_at,
    'ageSeconds',v_age,
    'reconciliationGraceSeconds',p_reconciliation_grace_seconds,
    'layer102ReconciliationId',v_l97.reconciliation_id,
    'layer102ReconciliationState',v_l97.reconciliation_state,
    'layer102ReconciliationAbsent',v_l97.reconciliation_id is null
  );

  v_fp := foundation.case_audit_layer102_reconcile_exec_policy_fp_v1(
    v_decision,v_incident,v_target_snapshot
  );

  if v_target.event_type<>'executed'
     or v_age<=p_reconciliation_grace_seconds
     or v_l97.reconciliation_id is not null
     or v_incident->>'state' not in ('watching','critical')
     or v_incident_event_id is null
     or v_decision->>'decision'<>'admit'
     or v_decision->>'requiredControl'<>'layer-102-bounded-reconciler'
     or v_decision->>'causeClass'<>'layer102-reconciliation-omission'
     or coalesce(v_decision->>'authorityExpansion','true')<>'false'
     or coalesce(v_decision->>'automaticLayer102ReconciliationAllowed','true')<>'false'
     or coalesce(v_decision->>'automaticReconciliationAllowed','true')<>'false'
     or coalesce(v_decision->>'automaticRepairAllowed','true')<>'false'
     or coalesce(v_decision->>'layer102ReceiptRewriteAllowed','true')<>'false'
     or coalesce(v_decision->>'layer101ReceiptRewriteAllowed','true')<>'false'
     or coalesce(v_decision->>'layer97ReceiptRewriteAllowed','true')<>'false'
     or coalesce(v_decision->>'historyRewriteAllowed','true')<>'false'
     or coalesce(v_decision->>'layer101RerunAllowed','true')<>'false'
     or coalesce(v_decision->>'layer97RerunAllowed','true')<>'false'
     or coalesce(v_decision->>'layer91RerunAllowed','true')<>'false'
     or coalesce(v_decision->>'layer87RerunAllowed','true')<>'false'
     or coalesce(v_decision->>'layer86RerunAllowed','true')<>'false'
     or coalesce(v_decision->>'layer82RerunAllowed','true')<>'false'
     or coalesce(v_decision->>'layer81RerunAllowed','true')<>'false'
     or coalesce(v_decision->>'verificationRerunAllowed','true')<>'false'
     or coalesce(v_decision->>'executesAction','true')<>'false'
     or coalesce(v_decision->>'mutatesLayer102Receipt','true')<>'false'
     or coalesce(v_decision->>'mutatesLayer101Receipt','true')<>'false'
     or coalesce(v_decision->>'mutatesLayer97Receipt','true')<>'false'
     or coalesce(v_decision->>'rerunsLayer101','true')<>'false'
     or coalesce(v_decision->>'rerunsLayer97','true')<>'false'
     or coalesce(v_decision->>'rerunsLayer91','true')<>'false'
     or coalesce(v_decision->>'rerunsLayer87','true')<>'false'
     or coalesce(v_decision->>'rerunsLayer86','true')<>'false'
     or coalesce(v_decision->>'rerunsLayer82','true')<>'false'
     or coalesce(v_decision->>'rerunsLayer81','true')<>'false'
     or coalesce(v_decision->>'rerunsVerification','true')<>'false'
     or coalesce(v_decision->>'mutatesAuthoritativeTruth','true')<>'false'
     or coalesce(v_decision->>'mutatesIncidentHistory','true')<>'false' then

    v_reason := case
      when v_target.event_type<>'executed'
        then 'case-audit-overdue-layer102-reconciliation-target-not-successful'
      when v_age<=p_reconciliation_grace_seconds
        then 'case-audit-overdue-layer102-reconciliation-within-grace'
      when v_l97.reconciliation_id is not null
        then 'case-audit-overdue-layer102-reconciliation-already-reconciled'
      when v_incident->>'state' not in ('watching','critical')
        then 'case-audit-overdue-layer102-reconciliation-incident-not-active'
      else 'case-audit-overdue-layer102-reconciliation-policy-not-admitted'
    end;

    v_event_id := gen_random_uuid();

    insert into foundation.case_audit_layer102_reconcile_exec_events(
      event_id,environment,target_layer101_event_id,coverage_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,requested_at
    )
    values(
      v_event_id,p_environment,v_target.event_id,v_incident_event_id,
      'run-independent-layer102-reconciliation',
      coalesce(v_decision->>'causeClass','unknown'),
      v_fp,'denied',v_reason,
      v_decision,v_incident,v_target_snapshot,v_before,p_requested_at
    );

    return jsonb_build_object(
      'foundationCaseAuditOverdueLayer102ReconciliationExecution',
        'shine-foundation/case-audit-overdue-layer102-reconciliation-execution-v1',
      'schemaVersion','1.0.0',
      'status','denied',
      'eventId',v_event_id,
      'layer101EventId',v_target.event_id,
      'environment',p_environment,
      'incidentEventId',v_incident_event_id,
      'reasonCode',v_reason,
      'policyFingerprint',v_fp,
      'boundedLayer102ReconcilerOnly',true,
      'layer96RerunPerformed',false,
      'layer92RerunPerformed',false,
      'layer91RerunPerformed',false,
      'layer87RerunPerformed',false,
      'layer86RerunPerformed',false,
      'layer82RerunPerformed',false,
      'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,
      'evidenceMutationPerformed',false,
      'layer97ReceiptRewritePerformed',false,
      'layer96ReceiptRewritePerformed',false,
      'layer92ReceiptRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false
    );
  end if;

  begin
    v_result := foundation.run_case_audit_layer101_execution_reconciliation_v1(
      v_target.event_id,p_requested_at
    );

    if v_result->>'status' not in ('recorded','existing')
       or v_result->>'reconciliationState' not in (
         'reconciled',
         'missing-layer97-receipt',
         'invalid-layer97-receipt',
         'execution-receipt-mismatch',
         'policy-drift',
         'incident-drift',
         'coverage-drift'
       ) then
      raise exception 'case-audit-overdue-layer102-reconciliation-result-invalid';
    end if;

    v_after := foundation.get_case_audit_layer102_reconciliation_coverage_v1(
      p_environment,p_requested_at,p_reconciliation_grace_seconds,100
    );

    v_event_id := gen_random_uuid();

    insert into foundation.case_audit_layer102_reconcile_exec_events(
      event_id,environment,target_layer101_event_id,coverage_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    )
    values(
      v_event_id,p_environment,v_target.event_id,v_incident_event_id,
      'run-independent-layer102-reconciliation',
      coalesce(v_decision->>'causeClass','unknown'),
      v_fp,'executed','case-audit-overdue-layer102-reconciliation-ran',
      v_decision,v_incident,v_target_snapshot,v_before,
      v_result,v_after,p_requested_at
    );

    return jsonb_build_object(
      'foundationCaseAuditOverdueLayer102ReconciliationExecution',
        'shine-foundation/case-audit-overdue-layer102-reconciliation-execution-v1',
      'schemaVersion','1.0.0',
      'status','executed',
      'eventId',v_event_id,
      'layer101EventId',v_target.event_id,
      'environment',p_environment,
      'incidentEventId',v_incident_event_id,
      'reasonCode','case-audit-overdue-layer102-reconciliation-ran',
      'policyFingerprint',v_fp,
      'actionResult',v_result,
      'afterCoverageState',v_after->>'state',
      'boundedLayer102ReconcilerOnly',true,
      'layer96RerunPerformed',false,
      'layer92RerunPerformed',false,
      'layer91RerunPerformed',false,
      'layer87RerunPerformed',false,
      'layer86RerunPerformed',false,
      'layer82RerunPerformed',false,
      'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,
      'evidenceMutationPerformed',false,
      'layer97ReceiptRewritePerformed',false,
      'layer96ReceiptRewritePerformed',false,
      'layer92ReceiptRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false
    );

  exception when others then
    v_error := sqlerrm;
    v_event_id := gen_random_uuid();

    insert into foundation.case_audit_layer102_reconcile_exec_events(
      event_id,environment,target_layer101_event_id,coverage_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      error_detail,requested_at
    )
    values(
      v_event_id,p_environment,v_target.event_id,v_incident_event_id,
      'run-independent-layer102-reconciliation',
      coalesce(v_decision->>'causeClass','unknown'),
      v_fp,'failed','case-audit-overdue-layer102-reconciliation-failed',
      v_decision,v_incident,v_target_snapshot,v_before,
      v_error,p_requested_at
    );

    return jsonb_build_object(
      'foundationCaseAuditOverdueLayer102ReconciliationExecution',
        'shine-foundation/case-audit-overdue-layer102-reconciliation-execution-v1',
      'schemaVersion','1.0.0',
      'status','failed',
      'eventId',v_event_id,
      'layer101EventId',v_target.event_id,
      'environment',p_environment,
      'incidentEventId',v_incident_event_id,
      'reasonCode','case-audit-overdue-layer102-reconciliation-failed',
      'errorDetail',v_error,
      'policyFingerprint',v_fp,
      'boundedLayer102ReconcilerOnly',true,
      'layer96RerunPerformed',false,
      'layer92RerunPerformed',false,
      'layer91RerunPerformed',false,
      'layer87RerunPerformed',false,
      'layer86RerunPerformed',false,
      'layer82RerunPerformed',false,
      'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,
      'evidenceMutationPerformed',false,
      'layer97ReceiptRewritePerformed',false,
      'layer96ReceiptRewritePerformed',false,
      'layer92ReceiptRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false
    );
  end;
end;
$layer106_execute$;

revoke all on function foundation.execute_case_audit_overdue_layer102_reconciliation_v1(
  uuid,text,timestamptz,integer
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.execute_case_audit_overdue_layer102_reconciliation_v1(
  uuid,text,timestamptz,integer
) to service_role;

revoke execute on function foundation.run_case_audit_layer101_execution_reconciliation_v1(
  uuid,timestamptz
) from service_role;
