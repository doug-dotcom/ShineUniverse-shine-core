
create or replace function foundation.run_case_audit_layer176_execution_reconciliation_v1(
  p_layer176_event_id uuid,
  p_reconciled_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_exec foundation.case_audit_layer172_reconcile_exec_events%rowtype;
  v_recon foundation.case_audit_layer171_exec_reconciliations%rowtype;
  v_incident foundation.case_audit_layer172_coverage_incident_events%rowtype;
  v_existing foundation.case_audit_layer176_exec_reconciliations%rowtype;
  v_reconciliation_id uuid;
  v_gate_incident_id uuid;
  v_admission_hash text;
  v_coverage_semantic_fingerprint text;
  v_incident_semantic_fingerprint text;
  v_incident_integrity boolean := false;
  v_incident_current boolean := false;
  v_state text;
  v_reason text;
  v_proof jsonb;
  v_hash text;
begin
  if p_layer176_event_id is null then
    raise exception 'case-audit-layer176-reconciliation-event-id-required';
  end if;

  if p_reconciled_at is null
     or p_reconciled_at<now()-interval '5 minutes'
     or p_reconciled_at>now()+interval '5 minutes' then
    raise exception 'case-audit-layer176-reconciliation-time-invalid';
  end if;

  select x.* into v_exec
  from foundation.case_audit_layer172_reconcile_exec_events x
  where x.event_id=p_layer176_event_id;

  if v_exec.event_id is null then
    return jsonb_build_object(
      'status','not-applicable',
      'reasonCode','case-audit-layer176-event-not-found',
      'mutationPerformed',false
    );
  end if;

  if v_exec.event_type<>'executed' then
    return jsonb_build_object(
      'status','not-applicable',
      'reasonCode','case-audit-layer176-source-not-executed',
      'mutationPerformed',false
    );
  end if;

  select x.* into v_existing
  from foundation.case_audit_layer176_exec_reconciliations x
  where x.layer176_event_id=v_exec.event_id;

  if v_existing.reconciliation_id is not null then
    return jsonb_build_object(
      'status','existing',
      'reconciliationId',v_existing.reconciliation_id,
      'reconciliationState',v_existing.reconciliation_state,
      'mutationPerformed',false
    );
  end if;

  select x.* into v_recon
  from foundation.case_audit_layer171_exec_reconciliations x
  where x.layer171_event_id=v_exec.target_layer171_event_id;

  begin
    v_gate_incident_id:=nullif(v_exec.decision_snapshot->>'incidentEventId','')::uuid;
  exception when invalid_text_representation then
    v_gate_incident_id:=null;
  end;

  if v_exec.coverage_incident_event_id is not null then
    select x.* into v_incident
    from foundation.case_audit_layer172_coverage_incident_events x
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
      foundation.get_case_audit_layer172_coverage_semantic_fingerprint_v1(
        v_incident.snapshot
      );

    v_incident_integrity:=
      v_incident.evidence_fingerprint
        is not distinct from v_incident_semantic_fingerprint;

    v_incident_current:=
      v_incident_integrity
      and v_incident.event_type in('detected','opened','changed')
      and v_incident.source_state in('gap','invalid')
      and v_incident.source_state
            is not distinct from v_exec.decision_snapshot#>>'{decision,cause,coverageState}'
      and v_incident_semantic_fingerprint
            is not distinct from v_coverage_semantic_fingerprint;
  end if;

  if v_recon.reconciliation_id is null then
    v_state:='missing-layer172-receipt';
    v_reason:='case-audit-layer176-layer172-receipt-missing';

  elsif v_exec.action_result->>'reconciliationId'
        is distinct from v_recon.reconciliation_id::text then
    v_state:='execution-receipt-mismatch';
    v_reason:='case-audit-layer176-receipt-mismatch';

  elsif v_exec.decision_snapshot->>'foundationCaseAuditLayer172ReconciliationAdmissionValidation'
        is distinct from
        'shine-foundation/case-audit-layer172-reconciliation-admission-validation-v1'
        or coalesce((v_exec.decision_snapshot->>'admitted')::boolean,false)<>true
        or v_exec.decision_snapshot->>'causeClass'<>'layer172-reconciliation-omission' then
    v_state:='admission-validation-drift';
    v_reason:='case-audit-layer176-admission-validation-drift';

  elsif v_exec.decision_snapshot#>>'{decision,decision}'<>'admit'
        or v_exec.decision_snapshot#>>'{decision,requiredControl}'<>'layer-172-bounded-reconciler'
        or v_exec.decision_snapshot#>>'{decision,causeClass}'<>'layer172-reconciliation-omission' then
    v_state:='policy-drift';
    v_reason:='case-audit-layer176-policy-drift';

  elsif v_exec.decision_snapshot->>'incidentState' not in('watching','critical')
        or (
          v_incident.event_id is not null
          and v_incident.event_type not in('detected','opened','changed')
        ) then
    v_state:='incident-state-drift';
    v_reason:='case-audit-layer176-incident-state-drift';

  elsif v_gate_incident_id is null
        or v_exec.coverage_incident_event_id is distinct from v_gate_incident_id
        or v_incident.event_id is null
        or v_incident.event_id is distinct from v_gate_incident_id then
    v_state:='incident-binding-drift';
    v_reason:='case-audit-layer176-incident-binding-drift';

  elsif coalesce((v_exec.decision_snapshot->>'incidentEvidenceIntegrity')::boolean,false)<>true
        or coalesce((v_exec.decision_snapshot#>>'{decision,incidentEvidenceIntegrity}')::boolean,false)<>true
        or not v_incident_integrity then
    v_state:='incident-integrity-drift';
    v_reason:='case-audit-layer176-incident-integrity-drift';

  elsif coalesce((v_exec.decision_snapshot->>'incidentEvidenceCurrent')::boolean,false)<>true
        or coalesce((v_exec.decision_snapshot#>>'{decision,incidentEvidenceCurrent}')::boolean,false)<>true
        or not v_incident_current
        or v_coverage_semantic_fingerprint is null
        or v_exec.decision_snapshot->>'incidentSemanticFingerprint'
             is distinct from v_incident_semantic_fingerprint
        or v_exec.decision_snapshot#>>'{decision,currentIncidentSemanticFingerprint}'
             is distinct from v_incident_semantic_fingerprint
        or v_exec.decision_snapshot#>>'{decision,coverageSemanticFingerprint}'
             is distinct from v_coverage_semantic_fingerprint then
    v_state:='semantic-currentness-drift';
    v_reason:='case-audit-layer176-semantic-currentness-drift';

  else
    v_state:='reconciled';
    v_reason:='case-audit-layer176-complete';
  end if;

  v_reconciliation_id:=gen_random_uuid();

  v_proof:=jsonb_build_object(
    'foundationCaseAuditLayer176ExecutionReconciliationProof',
      'shine-foundation/case-audit-layer176-execution-reconciliation-proof-v1',
    'schemaVersion','1.0.0',
    'reconciliationId',v_reconciliation_id,
    'layer176EventId',v_exec.event_id,
    'environment',v_exec.environment,
    'targetLayer171EventId',v_exec.target_layer171_event_id,
    'coverageIncidentEventId',v_exec.coverage_incident_event_id,
    'admissionIncidentEventId',v_gate_incident_id,
    'layer172ReconciliationId',v_recon.reconciliation_id,
    'admissionValidationSha256',v_admission_hash,
    'incidentEvidenceIntegrity',v_incident_integrity,
    'incidentEvidenceCurrent',v_incident_current,
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

  insert into foundation.case_audit_layer176_exec_reconciliations(
    reconciliation_id,layer176_event_id,environment,target_layer171_event_id,
    coverage_incident_event_id,layer172_reconciliation_id,
    admission_validation_sha256,incident_evidence_integrity,
    incident_evidence_current,coverage_semantic_fingerprint,
    incident_semantic_fingerprint,reconciliation_state,reason_code,
    reconciliation_proof,reconciliation_proof_sha256,reconciled_at
  )
  values(
    v_reconciliation_id,v_exec.event_id,v_exec.environment,
    v_exec.target_layer171_event_id,v_exec.coverage_incident_event_id,
    v_recon.reconciliation_id,v_admission_hash,v_incident_integrity,
    v_incident_current,v_coverage_semantic_fingerprint,
    v_incident_semantic_fingerprint,v_state,v_reason,
    v_proof,v_hash,p_reconciled_at
  );

  return jsonb_build_object(
    'foundationCaseAuditLayer176ExecutionReconciliation',
      'shine-foundation/case-audit-layer176-execution-reconciliation-v1',
    'schemaVersion','1.0.0',
    'status','recorded',
    'reconciliationId',v_reconciliation_id,
    'layer176EventId',v_exec.event_id,
    'coverageIncidentEventId',v_exec.coverage_incident_event_id,
    'admissionIncidentEventId',v_gate_incident_id,
    'layer172ReconciliationId',v_recon.reconciliation_id,
    'admissionValidationSha256',v_admission_hash,
    'incidentEvidenceIntegrity',v_incident_integrity,
    'incidentEvidenceCurrent',v_incident_current,
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

revoke all on function foundation.run_case_audit_layer176_execution_reconciliation_v1(
  uuid,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.run_case_audit_layer176_execution_reconciliation_v1(
  uuid,timestamptz
) to service_role;
