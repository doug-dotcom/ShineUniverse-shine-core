
create table foundation.case_audit_layer151_exec_reconciliations(
  reconciliation_sequence bigint generated always as identity primary key,
  reconciliation_id uuid not null unique default gen_random_uuid(),
  layer151_event_id uuid not null unique
    references foundation.case_audit_layer147_reconcile_exec_events(event_id),
  environment text not null check(environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  target_layer146_event_id uuid not null
    references foundation.case_audit_layer142_reconcile_exec_events(event_id),
  coverage_incident_event_id uuid
    references foundation.case_audit_layer147_coverage_incident_events(event_id),
  layer147_reconciliation_id uuid
    references foundation.case_audit_layer146_exec_reconciliations(reconciliation_id),
  reconciliation_state text not null check(
    reconciliation_state in(
      'reconciled',
      'missing-layer147-receipt',
      'execution-receipt-mismatch',
      'policy-drift',
      'incident-state-drift',
      'incident-binding-drift'
    )
  ),
  reason_code text not null check(reason_code ~ '^[a-z0-9][a-z0-9._:-]*$'),
  reconciliation_proof jsonb not null check(jsonb_typeof(reconciliation_proof)='object'),
  reconciliation_proof_sha256 text not null check(reconciliation_proof_sha256 ~ '^[a-f0-9]{64}$'),
  reconciled_at timestamptz not null,
  recorded_at timestamptz not null default now()
);

alter table foundation.case_audit_layer151_exec_reconciliations enable row level security;

create policy foundation_runtime_layer151_reconcile_select
on foundation.case_audit_layer151_exec_reconciliations
for select to foundation_runtime using(true);

create policy client_access_explicit_deny
on foundation.case_audit_layer151_exec_reconciliations
as restrictive for all to anon,authenticated
using(false) with check(false);

revoke all on foundation.case_audit_layer151_exec_reconciliations
from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
     shine_defence_runtime,service_role;

grant select on foundation.case_audit_layer151_exec_reconciliations
to foundation_runtime,service_role;

create index case_audit_layer151_reconcile_target_idx
on foundation.case_audit_layer151_exec_reconciliations(
  target_layer146_event_id,reconciled_at desc,reconciliation_sequence desc
);

create index case_audit_layer151_reconcile_incident_idx
on foundation.case_audit_layer151_exec_reconciliations(
  coverage_incident_event_id,reconciled_at desc,reconciliation_sequence desc
);

create index case_audit_layer151_reconcile_state_idx
on foundation.case_audit_layer151_exec_reconciliations(
  reconciliation_state,reconciled_at desc,reconciliation_sequence desc
);

create trigger case_audit_layer151_reconcile_append_only
before update or delete
on foundation.case_audit_layer151_exec_reconciliations
for each row execute function foundation.reject_append_only_mutation();

create or replace function foundation.run_case_audit_layer151_execution_reconciliation_v1(
  p_layer151_event_id uuid,
  p_reconciled_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_exec foundation.case_audit_layer147_reconcile_exec_events%rowtype;
  v_recon foundation.case_audit_layer146_exec_reconciliations%rowtype;
  v_incident foundation.case_audit_layer147_coverage_incident_events%rowtype;
  v_existing foundation.case_audit_layer151_exec_reconciliations%rowtype;
  v_reconciliation_id uuid;
  v_policy_incident_id uuid;
  v_state text;
  v_reason text;
  v_proof jsonb;
  v_hash text;
begin
  if p_layer151_event_id is null then
    raise exception 'case-audit-layer151-reconciliation-event-id-required';
  end if;

  if p_reconciled_at is null
     or p_reconciled_at<now()-interval '5 minutes'
     or p_reconciled_at>now()+interval '5 minutes' then
    raise exception 'case-audit-layer151-reconciliation-time-invalid';
  end if;

  select x.* into v_exec
  from foundation.case_audit_layer147_reconcile_exec_events x
  where x.event_id=p_layer151_event_id;

  if v_exec.event_id is null then
    return jsonb_build_object(
      'status','not-applicable',
      'reasonCode','case-audit-layer151-event-not-found',
      'mutationPerformed',false
    );
  end if;

  if v_exec.event_type<>'executed' then
    return jsonb_build_object(
      'status','not-applicable',
      'reasonCode','case-audit-layer151-source-not-executed',
      'mutationPerformed',false
    );
  end if;

  select x.* into v_existing
  from foundation.case_audit_layer151_exec_reconciliations x
  where x.layer151_event_id=v_exec.event_id;

  if v_existing.reconciliation_id is not null then
    return jsonb_build_object(
      'status','existing',
      'reconciliationId',v_existing.reconciliation_id,
      'reconciliationState',v_existing.reconciliation_state,
      'mutationPerformed',false
    );
  end if;

  select x.* into v_recon
  from foundation.case_audit_layer146_exec_reconciliations x
  where x.layer146_event_id=v_exec.target_layer146_event_id;

  select x.* into v_incident
  from foundation.case_audit_layer147_coverage_incident_events x
  where x.event_id=v_exec.coverage_incident_event_id
    and x.environment=v_exec.environment;

  begin
    v_policy_incident_id:=
      nullif(v_exec.decision_snapshot#>>'{cause,currentIncidentEventId}','')::uuid;
  exception when invalid_text_representation then
    v_policy_incident_id:=null;
  end;

  if v_recon.reconciliation_id is null then
    v_state:='missing-layer147-receipt';
    v_reason:='case-audit-layer151-layer147-receipt-missing';

  elsif v_exec.action_result->>'reconciliationId'
        is distinct from v_recon.reconciliation_id::text then
    v_state:='execution-receipt-mismatch';
    v_reason:='case-audit-layer151-receipt-mismatch';

  elsif v_exec.decision_snapshot->>'decision'<>'admit'
        or v_exec.decision_snapshot->>'requiredControl'<>'layer-147-bounded-reconciler'
        or v_exec.decision_snapshot->>'causeClass'<>'layer147-reconciliation-omission' then
    v_state:='policy-drift';
    v_reason:='case-audit-layer151-policy-drift';

  elsif v_exec.decision_snapshot->>'incidentState' not in('watching','critical') then
    v_state:='incident-state-drift';
    v_reason:='case-audit-layer151-incident-state-drift';

  elsif v_incident.event_id is null
        or v_policy_incident_id is null
        or v_exec.coverage_incident_event_id is distinct from v_policy_incident_id
        or v_incident.event_id is distinct from v_policy_incident_id
        or v_incident.event_type not in('detected','opened','changed')
        or v_incident.source_state not in('gap','invalid') then
    v_state:='incident-binding-drift';
    v_reason:='case-audit-layer151-incident-binding-drift';

  else
    v_state:='reconciled';
    v_reason:='case-audit-layer151-complete';
  end if;

  v_reconciliation_id:=gen_random_uuid();

  v_proof:=jsonb_build_object(
    'foundationCaseAuditLayer151ExecutionReconciliationProof',
      'shine-foundation/case-audit-layer151-execution-reconciliation-proof-v1',
    'schemaVersion','1.0.0',
    'reconciliationId',v_reconciliation_id,
    'layer151EventId',v_exec.event_id,
    'environment',v_exec.environment,
    'targetLayer146EventId',v_exec.target_layer146_event_id,
    'coverageIncidentEventId',v_exec.coverage_incident_event_id,
    'policyIncidentEventId',v_policy_incident_id,
    'layer147ReconciliationId',v_recon.reconciliation_id,
    'incidentState',v_exec.decision_snapshot->>'incidentState',
    'incidentEventType',v_incident.event_type,
    'incidentSourceState',v_incident.source_state,
    'incidentEvidenceFingerprint',v_incident.evidence_fingerprint,
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

  insert into foundation.case_audit_layer151_exec_reconciliations(
    reconciliation_id,layer151_event_id,environment,target_layer146_event_id,
    coverage_incident_event_id,layer147_reconciliation_id,
    reconciliation_state,reason_code,reconciliation_proof,
    reconciliation_proof_sha256,reconciled_at
  )
  values(
    v_reconciliation_id,v_exec.event_id,v_exec.environment,
    v_exec.target_layer146_event_id,v_exec.coverage_incident_event_id,
    v_recon.reconciliation_id,v_state,v_reason,v_proof,v_hash,p_reconciled_at
  );

  return jsonb_build_object(
    'foundationCaseAuditLayer151ExecutionReconciliation',
      'shine-foundation/case-audit-layer151-execution-reconciliation-v1',
    'schemaVersion','1.0.0',
    'status','recorded',
    'reconciliationId',v_reconciliation_id,
    'layer151EventId',v_exec.event_id,
    'coverageIncidentEventId',v_exec.coverage_incident_event_id,
    'policyIncidentEventId',v_policy_incident_id,
    'layer147ReconciliationId',v_recon.reconciliation_id,
    'incidentState',v_exec.decision_snapshot->>'incidentState',
    'reconciliationState',v_state,
    'reasonCode',v_reason,
    'reconciliationProofSha256',v_hash,
    'authorityExpansion',false,
    'upstreamRerunPerformed',false,
    'evidenceMutationPerformed',false,
    'mutationPerformed',false
  );
end $$;

revoke all on function foundation.run_case_audit_layer151_execution_reconciliation_v1(
  uuid,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.run_case_audit_layer151_execution_reconciliation_v1(
  uuid,timestamptz
) to service_role;
