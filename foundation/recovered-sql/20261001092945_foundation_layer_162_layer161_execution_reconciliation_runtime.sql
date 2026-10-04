
create or replace function foundation.run_case_audit_layer161_execution_reconciliation_v1(
  p_layer161_event_id uuid,
  p_reconciled_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_exec foundation.case_audit_layer157_reconcile_exec_events%rowtype;
  v_recon foundation.case_audit_layer156_exec_reconciliations%rowtype;
  v_incident foundation.case_audit_layer157_coverage_incident_events%rowtype;
  v_existing foundation.case_audit_layer161_exec_reconciliations%rowtype;
  v_reconciliation_id uuid;
  v_gate_incident_id uuid;
  v_admission_hash text;
  v_coverage_semantic_fingerprint text;
  v_incident_semantic_fingerprint text;
  v_state text;
  v_reason text;
  v_proof jsonb;
  v_hash text;
begin
  if p_layer161_event_id is null then
    raise exception 'case-audit-layer161-reconciliation-event-id-required';
  end if;

  if p_reconciled_at is null
     or p_reconciled_at<now()-interval '5 minutes'
     or p_reconciled_at>now()+interval '5 minutes' then
    raise exception 'case-audit-layer161-reconciliation-time-invalid';
  end if;

  select x.* into v_exec
  from foundation.case_audit_layer157_reconcile_exec_events x
  where x.event_id=p_layer161_event_id;

  if v_exec.event_id is null then
    return jsonb_build_object(
      'status','not-applicable',
      'reasonCode','case-audit-layer161-event-not-found',
      'mutationPerformed',false
    );
  end if;

  if v_exec.event_type<>'executed' then
    return jsonb_build_object(
      'status','not-applicable',
      'reasonCode','case-audit-layer161-source-not-executed',
      'mutationPerformed',false
    );
  end if;

  select x.* into v_existing
  from foundation.case_audit_layer161_exec_reconciliations x
  where x.layer161_event_id=v_exec.event_id;

  if v_existing.reconciliation_id is not null then
    return jsonb_build_object(
      'status','existing',
      'reconciliationId',v_existing.reconciliation_id,
      'reconciliationState',v_existing.reconciliation_state,
      'mutationPerformed',false
    );
  end if;

  select x.* into v_recon
  from foundation.case_audit_layer156_exec_reconciliations x
  where x.layer156_event_id=v_exec.target_layer156_event_id;

  begin
    v_gate_incident_id:=nullif(v_exec.decision_snapshot->>'incidentEventId','')::uuid;
  exception when invalid_text_representation then
    v_gate_incident_id:=null;
  end;

  if v_exec.coverage_incident_event_id is not null then
    select x.* into v_incident
    from foundation.case_audit_layer157_coverage_incident_events x
    where x.event_id=v_exec.coverage_incident_event_id
      and x.environment=v_exec.environment;
  end if;

  v_admission_hash:=encode(
    extensions.digest(convert_to(v_exec.decision_snapshot::text,'UTF8'),'sha256'),
    'hex'
  );

  v_coverage_semantic_fingerprint:=
    nullif(v_exec.decision_snapshot->>'coverageSemanticFingerprint','');

  if v_incident.event_id is not null then
    v_incident_semantic_fingerprint:=
      foundation.get_case_audit_layer157_coverage_semantic_fingerprint_v1(
        v_incident.snapshot
      );
  end if;

  if v_recon.reconciliation_id is null then
    v_state:='missing-layer157-receipt';
    v_reason:='case-audit-layer161-layer157-receipt-missing';

  elsif v_exec.action_result->>'reconciliationId'
        is distinct from v_recon.reconciliation_id::text then
    v_state:='execution-receipt-mismatch';
    v_reason:='case-audit-layer161-receipt-mismatch';

  elsif v_exec.decision_snapshot->>'foundationCaseAuditLayer157ReconciliationAdmissionValidation'
        is distinct from
        'shine-foundation/case-audit-layer157-reconciliation-admission-validation-v1'
        or coalesce((v_exec.decision_snapshot->>'admitted')::boolean,false)<>true
        or v_exec.decision_snapshot->>'causeClass'<>'layer157-reconciliation-omission' then
    v_state:='admission-validation-drift';
    v_reason:='case-audit-layer161-admission-validation-drift';

  elsif v_exec.decision_snapshot#>>'{decision,decision}'<>'admit'
        or v_exec.decision_snapshot#>>'{decision,requiredControl}'<>'layer-157-bounded-reconciler'
        or v_exec.decision_snapshot#>>'{decision,causeClass}'<>'layer157-reconciliation-omission' then
    v_state:='policy-drift';
    v_reason:='case-audit-layer161-policy-drift';

  elsif v_exec.decision_snapshot->>'incidentState' not in('watching','critical')
        or v_incident.event_type not in('detected','opened','changed') then
    v_state:='incident-state-drift';
    v_reason:='case-audit-layer161-incident-state-drift';

  elsif v_gate_incident_id is null
        or v_exec.coverage_incident_event_id is distinct from v_gate_incident_id
        or v_incident.event_id is null
        or v_incident.event_id is distinct from v_gate_incident_id then
    v_state:='incident-binding-drift';
    v_reason:='case-audit-layer161-incident-binding-drift';

  elsif coalesce((v_exec.decision_snapshot->>'incidentEvidenceCurrent')::boolean,false)<>true
        or v_coverage_semantic_fingerprint is null
        or v_incident_semantic_fingerprint is null
        or v_exec.decision_snapshot->>'incidentSemanticFingerprint'
             is distinct from v_incident_semantic_fingerprint
        or v_coverage_semantic_fingerprint
             is distinct from v_incident_semantic_fingerprint
        or v_exec.decision_snapshot#>>'{decision,currentIncidentSemanticFingerprint}'
             is distinct from v_incident_semantic_fingerprint
        or v_exec.decision_snapshot#>>'{decision,coverageSemanticFingerprint}'
             is distinct from v_coverage_semantic_fingerprint
        or v_exec.decision_snapshot->>'coverageState'
             is distinct from v_incident.source_state then
    v_state:='semantic-freshness-drift';
    v_reason:='case-audit-layer161-semantic-freshness-drift';

  else
    v_state:='reconciled';
    v_reason:='case-audit-layer161-complete';
  end if;

  v_reconciliation_id:=gen_random_uuid();

  v_proof:=jsonb_build_object(
    'foundationCaseAuditLayer161ExecutionReconciliationProof',
      'shine-foundation/case-audit-layer161-execution-reconciliation-proof-v1',
    'schemaVersion','1.0.0',
    'reconciliationId',v_reconciliation_id,
    'layer161EventId',v_exec.event_id,
    'environment',v_exec.environment,
    'targetLayer156EventId',v_exec.target_layer156_event_id,
    'coverageIncidentEventId',v_exec.coverage_incident_event_id,
    'admissionIncidentEventId',v_gate_incident_id,
    'layer157ReconciliationId',v_recon.reconciliation_id,
    'semanticAdmissionValidationSha256',v_admission_hash,
    'coverageSemanticFingerprint',v_coverage_semantic_fingerprint,
    'incidentSemanticFingerprint',v_incident_semantic_fingerprint,
    'incidentState',v_exec.decision_snapshot->>'incidentState',
    'incidentEventType',v_incident.event_type,
    'incidentSourceState',v_incident.source_state,
    'reconciliationState',v_state,
    'reasonCode',v_reason,
    'authorityExpansion',false,
    'upstreamRerunPerformed',false,
    'evidenceMutationPerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false,
    'mutationPerformed',false,
    'reconciledAt',p_reconciled_at
  );

  v_hash:=encode(
    extensions.digest(convert_to(v_proof::text,'UTF8'),'sha256'),
    'hex'
  );

  insert into foundation.case_audit_layer161_exec_reconciliations(
    reconciliation_id,layer161_event_id,environment,target_layer156_event_id,
    coverage_incident_event_id,layer157_reconciliation_id,
    semantic_admission_validation_sha256,coverage_semantic_fingerprint,
    incident_semantic_fingerprint,reconciliation_state,reason_code,
    reconciliation_proof,reconciliation_proof_sha256,reconciled_at
  )
  values(
    v_reconciliation_id,v_exec.event_id,v_exec.environment,
    v_exec.target_layer156_event_id,v_exec.coverage_incident_event_id,
    v_recon.reconciliation_id,v_admission_hash,v_coverage_semantic_fingerprint,
    v_incident_semantic_fingerprint,v_state,v_reason,
    v_proof,v_hash,p_reconciled_at
  );

  return jsonb_build_object(
    'foundationCaseAuditLayer161ExecutionReconciliation',
      'shine-foundation/case-audit-layer161-execution-reconciliation-v1',
    'schemaVersion','1.0.0',
    'status','recorded',
    'reconciliationId',v_reconciliation_id,
    'layer161EventId',v_exec.event_id,
    'coverageIncidentEventId',v_exec.coverage_incident_event_id,
    'admissionIncidentEventId',v_gate_incident_id,
    'layer157ReconciliationId',v_recon.reconciliation_id,
    'semanticAdmissionValidationSha256',v_admission_hash,
    'coverageSemanticFingerprint',v_coverage_semantic_fingerprint,
    'incidentSemanticFingerprint',v_incident_semantic_fingerprint,
    'reconciliationState',v_state,
    'reasonCode',v_reason,
    'reconciliationProofSha256',v_hash,
    'authorityExpansion',false,
    'upstreamRerunPerformed',false,
    'evidenceMutationPerformed',false,
    'mutationPerformed',false
  );
end $$;

revoke all on function foundation.run_case_audit_layer161_execution_reconciliation_v1(
  uuid,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.run_case_audit_layer161_execution_reconciliation_v1(
  uuid,timestamptz
) to service_role;
