
create or replace function foundation.run_case_audit_layer156_execution_reconciliation_v1(
  p_layer156_event_id uuid,
  p_reconciled_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_exec foundation.case_audit_layer152_reconcile_exec_events%rowtype;
  v_recon foundation.case_audit_layer151_exec_reconciliations%rowtype;
  v_incident foundation.case_audit_layer152_coverage_incident_events%rowtype;
  v_existing foundation.case_audit_layer156_exec_reconciliations%rowtype;
  v_reconciliation_id uuid;
  v_gate_incident_id uuid;
  v_admission_hash text;
  v_coverage_fingerprint text;
  v_state text;
  v_reason text;
  v_proof jsonb;
  v_hash text;
begin
  if p_layer156_event_id is null then
    raise exception 'case-audit-layer156-reconciliation-event-id-required';
  end if;

  if p_reconciled_at is null
     or p_reconciled_at<now()-interval '5 minutes'
     or p_reconciled_at>now()+interval '5 minutes' then
    raise exception 'case-audit-layer156-reconciliation-time-invalid';
  end if;

  select x.* into v_exec
  from foundation.case_audit_layer152_reconcile_exec_events x
  where x.event_id=p_layer156_event_id;

  if v_exec.event_id is null then
    return jsonb_build_object(
      'status','not-applicable',
      'reasonCode','case-audit-layer156-event-not-found',
      'mutationPerformed',false
    );
  end if;

  if v_exec.event_type<>'executed' then
    return jsonb_build_object(
      'status','not-applicable',
      'reasonCode','case-audit-layer156-source-not-executed',
      'mutationPerformed',false
    );
  end if;

  select x.* into v_existing
  from foundation.case_audit_layer156_exec_reconciliations x
  where x.layer156_event_id=v_exec.event_id;

  if v_existing.reconciliation_id is not null then
    return jsonb_build_object(
      'status','existing',
      'reconciliationId',v_existing.reconciliation_id,
      'reconciliationState',v_existing.reconciliation_state,
      'mutationPerformed',false
    );
  end if;

  select x.* into v_recon
  from foundation.case_audit_layer151_exec_reconciliations x
  where x.layer151_event_id=v_exec.target_layer151_event_id;

  begin
    v_gate_incident_id:=nullif(v_exec.decision_snapshot->>'incidentEventId','')::uuid;
  exception when invalid_text_representation then
    v_gate_incident_id:=null;
  end;

  if v_exec.coverage_incident_event_id is not null then
    select x.* into v_incident
    from foundation.case_audit_layer152_coverage_incident_events x
    where x.event_id=v_exec.coverage_incident_event_id
      and x.environment=v_exec.environment;
  end if;

  v_admission_hash:=encode(
    extensions.digest(convert_to(v_exec.decision_snapshot::text,'UTF8'),'sha256'),
    'hex'
  );

  v_coverage_fingerprint:=nullif(
    v_exec.decision_snapshot->>'coverageEvidenceFingerprint',''
  );

  if v_recon.reconciliation_id is null then
    v_state:='missing-layer152-receipt';
    v_reason:='case-audit-layer156-layer152-receipt-missing';

  elsif v_exec.action_result->>'reconciliationId'
        is distinct from v_recon.reconciliation_id::text then
    v_state:='execution-receipt-mismatch';
    v_reason:='case-audit-layer156-receipt-mismatch';

  elsif v_exec.decision_snapshot->>'foundationCaseAuditLayer152ReconciliationAdmissionValidation'
        is distinct from
        'shine-foundation/case-audit-layer152-reconciliation-admission-validation-v1'
        or coalesce((v_exec.decision_snapshot->>'admitted')::boolean,false)<>true
        or v_exec.decision_snapshot->>'causeClass'<>'layer152-reconciliation-omission' then
    v_state:='admission-validation-drift';
    v_reason:='case-audit-layer156-admission-validation-drift';

  elsif v_exec.decision_snapshot#>>'{decision,decision}'<>'admit'
        or v_exec.decision_snapshot#>>'{decision,requiredControl}'<>'layer-152-bounded-reconciler'
        or v_exec.decision_snapshot#>>'{decision,causeClass}'<>'layer152-reconciliation-omission' then
    v_state:='policy-drift';
    v_reason:='case-audit-layer156-policy-drift';

  elsif v_exec.decision_snapshot->>'incidentState' not in('watching','critical')
        or v_incident.event_type not in('detected','opened','changed') then
    v_state:='incident-state-drift';
    v_reason:='case-audit-layer156-incident-state-drift';

  elsif v_gate_incident_id is null
        or v_exec.coverage_incident_event_id is distinct from v_gate_incident_id
        or v_incident.event_id is null
        or v_incident.event_id is distinct from v_gate_incident_id then
    v_state:='incident-binding-drift';
    v_reason:='case-audit-layer156-incident-binding-drift';

  elsif coalesce((v_exec.decision_snapshot->>'incidentEvidenceCurrent')::boolean,false)<>true
        or v_coverage_fingerprint is null
        or v_exec.decision_snapshot->>'incidentEvidenceFingerprint'
             is distinct from v_incident.evidence_fingerprint
        or v_coverage_fingerprint is distinct from v_incident.evidence_fingerprint
        or v_exec.decision_snapshot->>'coverageState'
             is distinct from v_incident.source_state then
    v_state:='incident-evidence-stale';
    v_reason:='case-audit-layer156-incident-evidence-stale';

  else
    v_state:='reconciled';
    v_reason:='case-audit-layer156-complete';
  end if;

  v_reconciliation_id:=gen_random_uuid();

  v_proof:=jsonb_build_object(
    'foundationCaseAuditLayer156ExecutionReconciliationProof',
      'shine-foundation/case-audit-layer156-execution-reconciliation-proof-v1',
    'schemaVersion','1.0.0',
    'reconciliationId',v_reconciliation_id,
    'layer156EventId',v_exec.event_id,
    'environment',v_exec.environment,
    'targetLayer151EventId',v_exec.target_layer151_event_id,
    'coverageIncidentEventId',v_exec.coverage_incident_event_id,
    'admissionIncidentEventId',v_gate_incident_id,
    'layer152ReconciliationId',v_recon.reconciliation_id,
    'admissionValidationSha256',v_admission_hash,
    'coverageEvidenceFingerprint',v_coverage_fingerprint,
    'incidentEvidenceFingerprint',v_incident.evidence_fingerprint,
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

  insert into foundation.case_audit_layer156_exec_reconciliations(
    reconciliation_id,layer156_event_id,environment,target_layer151_event_id,
    coverage_incident_event_id,layer152_reconciliation_id,
    admission_validation_sha256,coverage_evidence_fingerprint,
    reconciliation_state,reason_code,reconciliation_proof,
    reconciliation_proof_sha256,reconciled_at
  )
  values(
    v_reconciliation_id,v_exec.event_id,v_exec.environment,
    v_exec.target_layer151_event_id,v_exec.coverage_incident_event_id,
    v_recon.reconciliation_id,v_admission_hash,v_coverage_fingerprint,
    v_state,v_reason,v_proof,v_hash,p_reconciled_at
  );

  return jsonb_build_object(
    'foundationCaseAuditLayer156ExecutionReconciliation',
      'shine-foundation/case-audit-layer156-execution-reconciliation-v1',
    'schemaVersion','1.0.0',
    'status','recorded',
    'reconciliationId',v_reconciliation_id,
    'layer156EventId',v_exec.event_id,
    'coverageIncidentEventId',v_exec.coverage_incident_event_id,
    'admissionIncidentEventId',v_gate_incident_id,
    'layer152ReconciliationId',v_recon.reconciliation_id,
    'admissionValidationSha256',v_admission_hash,
    'coverageEvidenceFingerprint',v_coverage_fingerprint,
    'reconciliationState',v_state,
    'reasonCode',v_reason,
    'reconciliationProofSha256',v_hash,
    'authorityExpansion',false,
    'upstreamRerunPerformed',false,
    'evidenceMutationPerformed',false,
    'mutationPerformed',false
  );
end $$;

revoke all on function foundation.run_case_audit_layer156_execution_reconciliation_v1(
  uuid,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.run_case_audit_layer156_execution_reconciliation_v1(
  uuid,timestamptz
) to service_role;
