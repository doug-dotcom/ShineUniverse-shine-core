-- Foundation Layer 41: scoped remediation executor.
-- Atomically consumes a valid Layer-40 execution admission and applies only one
-- hard-coded mutation shape. There is no arbitrary SQL execution path.

do $layer41_roles$
begin
  if not exists (
    select 1 from pg_roles where rolname='foundation_remediation_mutator'
  ) then
    create role foundation_remediation_mutator nologin noinherit;
  end if;
end;
$layer41_roles$;

alter role foundation_remediation_mutator nologin noinherit;
grant foundation_remediation_mutator to postgres;
grant usage on schema foundation to foundation_remediation_mutator;


create table foundation.remediation_execution_events (
  event_sequence bigint generated always as identity primary key,
  event_id uuid not null unique,
  execution_id uuid not null unique,
  admission_id uuid not null
    references foundation.remediation_execution_admissions(admission_id),
  approval_receipt_id uuid not null
    references foundation.remediation_approval_receipts(receipt_id),
  incident_event_id uuid not null
    references foundation.foundation_control_plane_incident_events(event_id),
  action_key text not null
    references foundation.remediation_execution_operations(action_key),
  event_type text not null
    check (event_type in ('executed','failed','denied')),
  reason_code text not null
    check (reason_code ~ '^[a-z0-9][a-z0-9._:-]*$'),
  proposal_sha256 text not null
    check (proposal_sha256 ~ '^[a-f0-9]{64}$'),
  proposal jsonb not null
    check (jsonb_typeof(proposal)='object'),
  before_snapshot jsonb,
  mutation_result jsonb,
  after_snapshot jsonb,
  error_detail text,
  occurred_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  check (before_snapshot is null or jsonb_typeof(before_snapshot)='object'),
  check (mutation_result is null or jsonb_typeof(mutation_result)='object'),
  check (after_snapshot is null or jsonb_typeof(after_snapshot)='object'),
  check (
    (event_type='executed' and mutation_result is not null and error_detail is null)
    or (event_type='failed' and error_detail is not null)
    or event_type='denied'
  )
);

alter table foundation.remediation_execution_events enable row level security;

create policy foundation_runtime_remediation_execution_events_select
on foundation.remediation_execution_events
for select
to foundation_runtime
using (true);

revoke all on foundation.remediation_execution_events
  from public,anon,authenticated,foundation_gateway,
       foundation_remediation_approver,foundation_remediation_executor,
       foundation_remediation_mutator,service_role;
grant select on foundation.remediation_execution_events
  to foundation_runtime,service_role;

create index remediation_execution_events_admission_idx
  on foundation.remediation_execution_events(
    admission_id,occurred_at desc,event_sequence desc
  );

create index remediation_execution_events_action_idx
  on foundation.remediation_execution_events(
    action_key,occurred_at desc,event_sequence desc
  );

create index remediation_execution_events_approval_receipt_idx
  on foundation.remediation_execution_events(approval_receipt_id);

create index remediation_execution_events_incident_idx
  on foundation.remediation_execution_events(incident_event_id);

create unique index remediation_execution_events_consuming_once_idx
  on foundation.remediation_execution_events(admission_id)
  where event_type in ('executed','failed');

create trigger remediation_execution_events_append_only
before update or delete on foundation.remediation_execution_events
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.get_remediation_proposal_sha256_v1(
  p_proposal jsonb
)
returns text
language plpgsql
immutable
security definer
set search_path = ''
as $layer41_hash$
begin
  if p_proposal is null
     or jsonb_typeof(p_proposal)<>'object'
     or pg_column_size(p_proposal)>32768 then
    raise exception 'remediation-proposal-invalid';
  end if;

  return encode(
    extensions.digest(
      convert_to(p_proposal::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );
end;
$layer41_hash$;

revoke all on function foundation.get_remediation_proposal_sha256_v1(jsonb)
  from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_remediation_proposal_sha256_v1(jsonb)
  to foundation_runtime,service_role,
     foundation_remediation_approver,
     foundation_remediation_executor,
     foundation_remediation_mutator;


create or replace function foundation.execute_scoped_remediation_v1(
  p_event_id uuid,
  p_execution_id uuid,
  p_admission_id uuid,
  p_proposal jsonb,
  p_requested_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer41_execute$
declare
  v_admission foundation.remediation_execution_admissions%rowtype;
  v_receipt foundation.remediation_approval_receipts%rowtype;
  v_consumption foundation.remediation_approval_events%rowtype;
  v_operation foundation.remediation_execution_operations%rowtype;
  v_current_incident foundation.foundation_control_plane_incident_events%rowtype;
  v_binding foundation.foundation_release_identity_bindings%rowtype;

  v_projection jsonb;
  v_policy jsonb;
  v_identity_health jsonb;
  v_before jsonb;
  v_after jsonb;

  v_proposal_hash text;
  v_admission_hash text;
  v_expected_admission_hash text;
  v_receipt_hash text;
  v_reason text;

  v_proposal_operation jsonb;
  v_expected_registry jsonb;
  v_registry_layer integer;
  v_registry_layer_status text;
  v_registry_build_state text;
  v_registry_release_ref text;
  v_registry_evidence_note text;

  v_release_label text;
  v_source_commit_ref text;
  v_evidence_ref text;
  v_evidence_note text;

  v_rebind_layer integer;
  v_expected_binding_id uuid;
  v_expected_binding_release_ref text;
  v_rebind_result jsonb;

  v_mutation_result jsonb;
  v_error_detail text;
  v_row_count integer := 0;
begin
  if p_event_id is null
     or p_execution_id is null
     or p_admission_id is null
     or p_requested_at is null then
    raise exception 'scoped-remediation-required-fields-missing';
  end if;

  if p_requested_at<now()-interval '5 minutes'
     or p_requested_at>now()+interval '5 minutes' then
    raise exception 'scoped-remediation-requested-at-invalid';
  end if;

  if p_proposal is null
     or jsonb_typeof(p_proposal)<>'object'
     or pg_column_size(p_proposal)>32768 then
    raise exception 'scoped-remediation-proposal-invalid';
  end if;

  v_proposal_hash :=
    foundation.get_remediation_proposal_sha256_v1(p_proposal);

  select * into v_admission
  from foundation.remediation_execution_admissions
  where admission_id=p_admission_id
  for update;

  if v_admission.admission_id is null then
    return jsonb_build_object(
      'foundationScopedRemediationExecutionResponse',
        'shine-foundation/scoped-remediation-execution-response-v1',
      'schemaVersion','1.0.0',
      'executed',false,
      'admissionConsumed',false,
      'reasonCode','remediation-execution-admission-not-found'
    );
  end if;

  select * into v_operation
  from foundation.remediation_execution_operations
  where action_key=v_admission.action_key
    and lifecycle='active';

  select * into v_receipt
  from foundation.remediation_approval_receipts
  where receipt_id=v_admission.approval_receipt_id;

  select * into v_consumption
  from foundation.remediation_approval_events
  where event_id=v_admission.approval_consumption_event_id
    and receipt_id=v_admission.approval_receipt_id
    and event_type='consumed';

  select * into v_current_incident
  from foundation.current_foundation_control_plane_incident_state
  where incident_key=v_admission.incident_key;

  select * into v_binding
  from foundation.current_foundation_release_identity
  where service_id='foundation.gateway'
    and environment=v_admission.environment;

  v_projection :=
    foundation.get_foundation_release_projection_health_v1(
      v_admission.environment,p_requested_at
    );

  v_policy :=
    foundation.evaluate_control_plane_incident_response_v1(
      v_admission.action_key,v_admission.environment
    );

  v_expected_admission_hash := encode(
    extensions.digest(
      convert_to(v_admission.admission::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  if v_receipt.receipt_id is not null then
    v_receipt_hash := encode(
      extensions.digest(
        convert_to(v_receipt.receipt::text,'UTF8'),
        'sha256'
      ),
      'hex'
    );
  end if;

  v_reason := null;

  if exists (
    select 1
    from foundation.remediation_execution_events e
    where e.admission_id=v_admission.admission_id
      and e.event_type in ('executed','failed')
  ) then
    v_reason := 'remediation-execution-admission-already-consumed';
  elsif v_admission.admission_sha256 is distinct from v_expected_admission_hash then
    v_reason := 'remediation-execution-admission-integrity-failed';
  elsif p_requested_at<v_admission.admitted_at then
    v_reason := 'remediation-execution-admission-not-yet-valid';
  elsif v_admission.expires_at<=p_requested_at then
    v_reason := 'remediation-execution-admission-expired';
  elsif v_operation.action_key is null then
    v_reason := 'remediation-execution-operation-not-active';
  elsif v_operation.operation_contract is distinct from v_admission.operation_contract
     or v_operation.target_authority is distinct from v_admission.target_authority
     or v_operation.mutation_shape is distinct from v_admission.mutation_shape then
    v_reason := 'remediation-execution-operation-contract-mismatch';
  elsif v_receipt.receipt_id is null
     or v_receipt.receipt_sha256 is distinct from v_receipt_hash then
    v_reason := 'remediation-approval-integrity-failed';
  elsif v_consumption.event_id is null then
    v_reason := 'remediation-approval-consumption-missing';
  elsif v_receipt.action_key is distinct from v_admission.action_key
     or v_receipt.incident_event_id is distinct from v_admission.incident_event_id
     or v_receipt.evidence_fingerprint is distinct from v_admission.evidence_fingerprint
     or v_receipt.release_ref is distinct from v_admission.release_ref
     or v_receipt.proposal_sha256 is distinct from v_admission.proposal_sha256 then
    v_reason := 'remediation-approval-admission-scope-mismatch';
  elsif v_proposal_hash is distinct from v_admission.proposal_sha256 then
    v_reason := 'remediation-execution-proposal-hash-mismatch';
  elsif p_proposal->>'remediationProposal'
        is distinct from 'shine-foundation/remediation-proposal-v1'
     or p_proposal->>'schemaVersion' is distinct from '1.0.0'
     or p_proposal->>'environment' is distinct from v_admission.environment
     or p_proposal->>'actionKey' is distinct from v_admission.action_key
     or p_proposal->>'incidentEventId' is distinct from
        v_admission.incident_event_id::text
     or p_proposal->>'evidenceFingerprint' is distinct from
        v_admission.evidence_fingerprint
     or p_proposal->>'releaseRef' is distinct from v_admission.release_ref
     or jsonb_typeof(p_proposal->'operation') is distinct from 'object' then
    v_reason := 'remediation-execution-proposal-scope-mismatch';
  elsif exists (
    select 1
    from jsonb_object_keys(p_proposal) k
    where k not in (
      'remediationProposal','schemaVersion','environment','actionKey',
      'incidentEventId','evidenceFingerprint','releaseRef','operation'
    )
  ) then
    v_reason := 'remediation-execution-proposal-fields-invalid';
  elsif (
    v_admission.action_key='apply-registry-repair'
    and exists (
      select 1
      from jsonb_object_keys(p_proposal->'operation') k
      where k not in ('expectedRegistry','evidenceNote')
    )
  ) or (
    v_admission.action_key='apply-release-ledger-repair'
    and exists (
      select 1
      from jsonb_object_keys(p_proposal->'operation') k
      where k not in (
        'releaseLabel','sourceCommitRef','evidenceRef','evidenceNote'
      )
    )
  ) or (
    v_admission.action_key='rebind-release-identity'
    and exists (
      select 1
      from jsonb_object_keys(p_proposal->'operation') k
      where k not in (
        'foundationLayer','expectedBindingId',
        'expectedBindingReleaseRef','evidenceNote'
      )
    )
  ) then
    v_reason := 'remediation-execution-operation-fields-invalid';
  elsif v_current_incident.event_id is distinct from v_admission.incident_event_id
     or v_current_incident.event_type not in ('opened','changed') then
    v_reason := 'remediation-execution-incident-no-longer-current';
  elsif v_current_incident.evidence_fingerprint is distinct from
        v_admission.evidence_fingerprint then
    v_reason := 'remediation-execution-incident-evidence-mismatch';
  elsif coalesce(v_projection->>'state','unknown') not in ('fail','unknown') then
    v_reason := 'remediation-execution-projection-no-longer-incident';
  elsif lower(coalesce(v_projection->>'evidenceFingerprint',''))
        is distinct from v_admission.evidence_fingerprint then
    v_reason := 'remediation-execution-live-evidence-mismatch';
  elsif coalesce(
          v_projection#>>'{binding,releaseRef}',
          v_projection#>>'{registry,readinessReleaseRef}'
        ) is distinct from v_admission.release_ref then
    v_reason := 'remediation-execution-live-release-mismatch';
  elsif v_policy->>'decision'<>'approval-required'
     or v_policy->>'requiredControl'<>'external-approval'
     or v_policy->>'policyVersion' is distinct from v_admission.policy_version then
    v_reason := 'remediation-execution-policy-no-longer-valid';
  end if;

  v_before := jsonb_build_object(
    'projection',v_projection,
    'incident',case
      when v_current_incident.event_id is null then null
      else jsonb_build_object(
        'eventId',v_current_incident.event_id,
        'eventType',v_current_incident.event_type,
        'sourceState',v_current_incident.source_state,
        'severity',v_current_incident.severity,
        'evidenceFingerprint',v_current_incident.evidence_fingerprint
      )
    end,
    'binding',case
      when v_binding.binding_id is null then null
      else jsonb_build_object(
        'bindingId',v_binding.binding_id,
        'foundationLayer',v_binding.foundation_layer,
        'releaseRef',v_binding.release_ref,
        'sourceRef',v_binding.source_ref,
        'runtimeVersion',v_binding.runtime_version,
        'artifactSha256',v_binding.artifact_sha256
      )
    end
  );

  if v_reason is not null then
    insert into foundation.remediation_execution_events(
      event_id,execution_id,admission_id,approval_receipt_id,
      incident_event_id,action_key,event_type,reason_code,
      proposal_sha256,proposal,before_snapshot,occurred_at
    )
    values (
      p_event_id,p_execution_id,v_admission.admission_id,
      v_admission.approval_receipt_id,v_admission.incident_event_id,
      v_admission.action_key,'denied',v_reason,
      v_proposal_hash,p_proposal,v_before,p_requested_at
    );

    return jsonb_build_object(
      'foundationScopedRemediationExecutionResponse',
        'shine-foundation/scoped-remediation-execution-response-v1',
      'schemaVersion','1.0.0',
      'executed',false,
      'admissionConsumed',false,
      'executionId',p_execution_id,
      'admissionId',v_admission.admission_id,
      'actionKey',v_admission.action_key,
      'reasonCode',v_reason
    );
  end if;

  v_proposal_operation := p_proposal->'operation';

  begin
    if v_admission.action_key='apply-registry-repair' then
      v_expected_registry := v_proposal_operation->'expectedRegistry';

      if jsonb_typeof(v_expected_registry) is distinct from 'object'
         or not (v_expected_registry ? 'currentLayer')
         or not (v_expected_registry ? 'currentLayerStatus')
         or not (v_expected_registry ? 'buildState')
         or not (v_expected_registry ? 'readinessReleaseRef') then
        raise exception 'registry-repair-expected-state-invalid';
      end if;

      if v_binding.binding_id is null
         or v_binding.release_ref is distinct from v_admission.release_ref then
        raise exception 'registry-repair-binding-mismatch';
      end if;

      if not exists (
        select 1
        from universe.readiness_releases r
        where r.app_key='foundation'
          and r.release_ref=v_binding.release_ref
          and r.source_layer_ref=format('layer:%s',v_binding.foundation_layer)
      ) then
        raise exception 'registry-repair-target-release-missing';
      end if;

      select
        current_layer,current_layer_status,build_state,
        readiness_release_ref,evidence_note
      into
        v_registry_layer,v_registry_layer_status,v_registry_build_state,
        v_registry_release_ref,v_registry_evidence_note
      from universe.app_registry
      where app_key='foundation'
      for update;

      if v_registry_layer is distinct from
           (v_expected_registry->>'currentLayer')::integer
         or v_registry_layer_status is distinct from
           v_expected_registry->>'currentLayerStatus'
         or v_registry_build_state is distinct from
           v_expected_registry->>'buildState'
         or v_registry_release_ref is distinct from
           v_expected_registry->>'readinessReleaseRef' then
        raise exception 'registry-repair-before-state-mismatch';
      end if;

      v_evidence_note := nullif(v_proposal_operation->>'evidenceNote','');

      if v_evidence_note is not null
         and char_length(v_evidence_note)>2000 then
        raise exception 'registry-repair-evidence-note-too-large';
      end if;

      update universe.app_registry
      set current_layer=v_binding.foundation_layer,
          current_layer_status='verified',
          build_state='deployed',
          readiness_release_ref=v_binding.release_ref,
          evidence_note=coalesce(
            v_evidence_note,
            format(
              'Scoped remediation execution %s applied approved registry repair %s.',
              p_execution_id,v_proposal_hash
            )
          ),
          last_verified_at=p_requested_at,
          updated_at=p_requested_at
      where app_key='foundation'
        and current_layer is not distinct from v_registry_layer
        and current_layer_status is not distinct from v_registry_layer_status
        and build_state is not distinct from v_registry_build_state
        and readiness_release_ref is not distinct from v_registry_release_ref;

      get diagnostics v_row_count = row_count;

      if v_row_count<>1 then
        raise exception 'registry-repair-concurrent-state-change';
      end if;

      v_mutation_result := jsonb_build_object(
        'operation','scoped-registry-correction',
        'appKey','foundation',
        'previous',jsonb_build_object(
          'currentLayer',v_registry_layer,
          'currentLayerStatus',v_registry_layer_status,
          'buildState',v_registry_build_state,
          'readinessReleaseRef',v_registry_release_ref,
          'evidenceNote',v_registry_evidence_note
        ),
        'applied',jsonb_build_object(
          'currentLayer',v_binding.foundation_layer,
          'currentLayerStatus','verified',
          'buildState','deployed',
          'readinessReleaseRef',v_binding.release_ref
        )
      );

    elsif v_admission.action_key='apply-release-ledger-repair' then
      if v_binding.binding_id is null
         or v_binding.release_ref is distinct from v_admission.release_ref then
        raise exception 'release-ledger-repair-binding-mismatch';
      end if;

      if exists (
        select 1
        from universe.readiness_releases r
        where r.app_key='foundation'
          and r.release_ref=v_admission.release_ref
      ) then
        raise exception 'release-ledger-repair-target-already-exists';
      end if;

      v_release_label := nullif(v_proposal_operation->>'releaseLabel','');
      v_source_commit_ref := lower(
        coalesce(v_proposal_operation->>'sourceCommitRef','')
      );
      v_evidence_ref := nullif(v_proposal_operation->>'evidenceRef','');
      v_evidence_note := nullif(v_proposal_operation->>'evidenceNote','');

      if v_release_label is null
         or char_length(v_release_label)>200 then
        raise exception 'release-ledger-repair-label-invalid';
      end if;

      if v_source_commit_ref !~ '^[a-f0-9]{40}$' then
        raise exception 'release-ledger-repair-source-commit-invalid';
      end if;

      if v_evidence_ref is distinct from
         'https://github.com/doug-dotcom/ShineUniverse-shine-core/commit/'
         ||v_source_commit_ref then
        raise exception 'release-ledger-repair-evidence-ref-invalid';
      end if;

      if v_evidence_note is not null
         and char_length(v_evidence_note)>2000 then
        raise exception 'release-ledger-repair-evidence-note-too-large';
      end if;

      insert into universe.readiness_releases(
        app_key,release_ref,release_label,source_layer_ref,
        source_commit_ref,opened_at,evidence_ref,evidence_note
      )
      values (
        'foundation',v_admission.release_ref,v_release_label,
        format('layer:%s',v_binding.foundation_layer),
        v_source_commit_ref,p_requested_at,v_evidence_ref,
        v_evidence_note
      );

      v_mutation_result := jsonb_build_object(
        'operation','scoped-release-ledger-correction',
        'appKey','foundation',
        'releaseRef',v_admission.release_ref,
        'sourceLayerRef',format('layer:%s',v_binding.foundation_layer),
        'sourceCommitRef',v_source_commit_ref,
        'evidenceRef',v_evidence_ref
      );

    elsif v_admission.action_key='rebind-release-identity' then
      begin
        v_rebind_layer :=
          (v_proposal_operation->>'foundationLayer')::integer;
        v_expected_binding_id :=
          (v_proposal_operation->>'expectedBindingId')::uuid;
      exception when others then
        raise exception 'release-rebind-proposal-invalid';
      end;

      v_expected_binding_release_ref :=
        nullif(v_proposal_operation->>'expectedBindingReleaseRef','');
      v_evidence_note := nullif(v_proposal_operation->>'evidenceNote','');

      if v_rebind_layer is null
         or v_rebind_layer<=0
         or v_expected_binding_id is null
         or v_expected_binding_release_ref is null then
        raise exception 'release-rebind-proposal-invalid';
      end if;

      if v_binding.binding_id is distinct from v_expected_binding_id
         or v_binding.release_ref is distinct from
            v_expected_binding_release_ref
         or v_binding.release_ref is distinct from v_admission.release_ref then
        raise exception 'release-rebind-before-state-mismatch';
      end if;

      select current_layer,readiness_release_ref
      into v_registry_layer,v_registry_release_ref
      from universe.app_registry
      where app_key='foundation'
      for share;

      if v_registry_layer is distinct from v_rebind_layer
         or v_registry_release_ref is distinct from v_binding.release_ref then
        raise exception 'release-rebind-registry-scope-mismatch';
      end if;

      v_identity_health :=
        foundation.get_foundation_release_identity_health_v1(
          v_admission.environment
        );

      if v_identity_health->>'state'<>'fail'
         or not (
           coalesce(v_identity_health->'reasonCodes','[]'::jsonb)
           ? 'release-identity-deployment-mismatch'
         ) then
        raise exception 'release-rebind-deployment-mismatch-not-proven';
      end if;

      v_rebind_result :=
        foundation.bind_foundation_release_identity_v1(
          v_rebind_layer,
          'remediation-executor',
          jsonb_build_object(
            'executionId',p_execution_id,
            'admissionId',v_admission.admission_id,
            'approvalReceiptId',v_admission.approval_receipt_id,
            'proposalSha256',v_proposal_hash,
            'evidenceNote',v_evidence_note
          )
        );

      if v_rebind_result->>'status'<>'bound-new' then
        raise exception 'release-rebind-did-not-create-new-binding';
      end if;

      v_mutation_result := jsonb_build_object(
        'operation','append-only-release-rebind',
        'previousBindingId',v_binding.binding_id,
        'previousReleaseRef',v_binding.release_ref,
        'newBindingId',v_rebind_result->>'bindingId',
        'newReleaseRef',v_rebind_result->>'releaseRef',
        'runtimeVersion',v_rebind_result->>'runtimeVersion',
        'sourceRef',v_rebind_result->>'sourceRef',
        'artifactSha256',v_rebind_result->>'artifactSha256'
      );

    else
      raise exception 'scoped-remediation-action-not-implemented';
    end if;

  exception when others then
    v_error_detail := left(sqlerrm,2000);

    insert into foundation.remediation_execution_events(
      event_id,execution_id,admission_id,approval_receipt_id,
      incident_event_id,action_key,event_type,reason_code,
      proposal_sha256,proposal,before_snapshot,error_detail,occurred_at
    )
    values (
      p_event_id,p_execution_id,v_admission.admission_id,
      v_admission.approval_receipt_id,v_admission.incident_event_id,
      v_admission.action_key,'failed',
      'scoped-remediation-mutation-failed',
      v_proposal_hash,p_proposal,v_before,v_error_detail,p_requested_at
    );

    return jsonb_build_object(
      'foundationScopedRemediationExecutionResponse',
        'shine-foundation/scoped-remediation-execution-response-v1',
      'schemaVersion','1.0.0',
      'executed',false,
      'admissionConsumed',true,
      'executionId',p_execution_id,
      'admissionId',v_admission.admission_id,
      'actionKey',v_admission.action_key,
      'reasonCode','scoped-remediation-mutation-failed',
      'errorDetail',v_error_detail
    );
  end;

  v_after := jsonb_build_object(
    'projection',
      foundation.get_foundation_release_projection_health_v1(
        v_admission.environment,p_requested_at
      ),
    'releaseIdentity',
      foundation.get_foundation_release_identity_health_v1(
        v_admission.environment
      )
  );

  insert into foundation.remediation_execution_events(
    event_id,execution_id,admission_id,approval_receipt_id,
    incident_event_id,action_key,event_type,reason_code,
    proposal_sha256,proposal,before_snapshot,mutation_result,
    after_snapshot,occurred_at
  )
  values (
    p_event_id,p_execution_id,v_admission.admission_id,
    v_admission.approval_receipt_id,v_admission.incident_event_id,
    v_admission.action_key,'executed','scoped-remediation-executed',
    v_proposal_hash,p_proposal,v_before,v_mutation_result,
    v_after,p_requested_at
  );

  return jsonb_build_object(
    'foundationScopedRemediationExecutionResponse',
      'shine-foundation/scoped-remediation-execution-response-v1',
    'schemaVersion','1.0.0',
    'executed',true,
    'admissionConsumed',true,
    'executionId',p_execution_id,
    'admissionId',v_admission.admission_id,
    'actionKey',v_admission.action_key,
    'reasonCode','scoped-remediation-executed',
    'mutationResult',v_mutation_result,
    'after',v_after
  );
end;
$layer41_execute$;

revoke all on function foundation.execute_scoped_remediation_v1(
  uuid,uuid,uuid,jsonb,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       foundation_remediation_approver,foundation_remediation_executor,
       service_role;
grant execute on function foundation.execute_scoped_remediation_v1(
  uuid,uuid,uuid,jsonb,timestamptz
) to foundation_remediation_mutator;


create or replace function foundation.get_remediation_execution_admission_status_v1(
  p_admission_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer41_admission_status$
declare
  v_admission foundation.remediation_execution_admissions%rowtype;
  v_current foundation.foundation_control_plane_incident_events%rowtype;
  v_projection jsonb;
  v_policy jsonb;
  v_operation foundation.remediation_execution_operations%rowtype;
  v_execution foundation.remediation_execution_events%rowtype;
  v_expected_hash text;
  v_status text;
begin
  select * into v_admission
  from foundation.remediation_execution_admissions
  where admission_id=p_admission_id;

  if v_admission.admission_id is null then
    return jsonb_build_object(
      'foundationRemediationExecutionAdmissionStatusResponse',
        'shine-foundation/remediation-execution-admission-status-response-v1',
      'schemaVersion','1.0.0',
      'admissionId',p_admission_id,
      'status','missing',
      'mayAttemptExecution',false,
      'executesAction',false
    );
  end if;

  select * into v_execution
  from foundation.remediation_execution_events
  where admission_id=v_admission.admission_id
    and event_type in ('executed','failed')
  order by occurred_at desc,event_sequence desc
  limit 1;

  v_expected_hash := encode(
    extensions.digest(
      convert_to(v_admission.admission::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  select * into v_current
  from foundation.current_foundation_control_plane_incident_state
  where incident_key=v_admission.incident_key;

  v_projection :=
    foundation.get_foundation_release_projection_health_v1(
      v_admission.environment,now()
    );

  v_policy :=
    foundation.evaluate_control_plane_incident_response_v1(
      v_admission.action_key,v_admission.environment
    );

  select * into v_operation
  from foundation.remediation_execution_operations
  where action_key=v_admission.action_key;

  v_status := case
    when v_admission.admission_sha256 is distinct from v_expected_hash
      then 'invalid'
    when v_execution.event_id is not null
      then 'consumed'
    when v_admission.admitted_at>now()
      then 'not-yet-valid'
    when v_admission.expires_at<=now()
      then 'expired'
    when v_operation.action_key is null
      or v_operation.lifecycle<>'active'
      then 'stale'
    when v_current.event_id is distinct from v_admission.incident_event_id
      or v_current.event_type not in ('opened','changed')
      then 'stale'
    when v_current.evidence_fingerprint is distinct from
         v_admission.evidence_fingerprint
      then 'stale'
    when lower(coalesce(v_projection->>'evidenceFingerprint',''))
         is distinct from v_admission.evidence_fingerprint
      then 'stale'
    when coalesce(
           v_projection#>>'{binding,releaseRef}',
           v_projection#>>'{registry,readinessReleaseRef}'
         ) is distinct from v_admission.release_ref
      then 'stale'
    when v_policy->>'decision'<>'approval-required'
      or v_policy->>'requiredControl'<>'external-approval'
      or v_policy->>'policyVersion' is distinct from v_admission.policy_version
      then 'stale'
    else 'active'
  end;

  return jsonb_build_object(
    'foundationRemediationExecutionAdmissionStatusResponse',
      'shine-foundation/remediation-execution-admission-status-response-v1',
    'schemaVersion','1.0.0',
    'admissionId',v_admission.admission_id,
    'status',v_status,
    'approvalReceiptId',v_admission.approval_receipt_id,
    'approvalConsumptionEventId',v_admission.approval_consumption_event_id,
    'environment',v_admission.environment,
    'incidentEventId',v_admission.incident_event_id,
    'actionKey',v_admission.action_key,
    'operationContract',v_admission.operation_contract,
    'targetAuthority',v_admission.target_authority,
    'mutationShape',v_admission.mutation_shape,
    'policyVersion',v_admission.policy_version,
    'evidenceFingerprint',v_admission.evidence_fingerprint,
    'releaseRef',v_admission.release_ref,
    'proposalSha256',v_admission.proposal_sha256,
    'admittedAt',v_admission.admitted_at,
    'expiresAt',v_admission.expires_at,
    'integrityVerified',
      v_admission.admission_sha256 is not distinct from v_expected_hash,
    'consumingExecution',case
      when v_execution.event_id is null then null
      else jsonb_build_object(
        'executionId',v_execution.execution_id,
        'eventType',v_execution.event_type,
        'reasonCode',v_execution.reason_code,
        'occurredAt',v_execution.occurred_at
      )
    end,
    'singleUse',true,
    'mayAttemptExecution',v_status='active',
    'executesAction',false
  );
end;
$layer41_admission_status$;

revoke all on function foundation.get_remediation_execution_admission_status_v1(uuid)
  from public,anon,authenticated,foundation_gateway,
       foundation_remediation_approver,foundation_remediation_executor,
       foundation_remediation_mutator;
grant execute on function foundation.get_remediation_execution_admission_status_v1(uuid)
  to foundation_runtime,service_role;


create or replace function foundation.get_scoped_remediation_executor_control_health_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer41_health$
declare
  v_mutator_exists boolean := false;
  v_service_member boolean := false;
  v_approver_member boolean := false;
  v_admission_executor_member boolean := false;
  v_service_can_execute boolean := false;
  v_approver_can_execute boolean := false;
  v_admission_executor_can_execute boolean := false;
  v_mutator_can_execute boolean := false;
  v_mutator_registry_update boolean := false;
  v_mutator_release_insert boolean := false;
  v_mutator_event_insert boolean := false;
  v_operation_count integer := 0;
  v_auto_registered boolean := false;
  v_state text := 'pass';
begin
  select exists(
    select 1
    from pg_roles
    where rolname='foundation_remediation_mutator'
      and not rolcanlogin
  ) into v_mutator_exists;

  v_service_member := pg_has_role(
    'service_role','foundation_remediation_mutator','MEMBER'
  );

  v_approver_member := pg_has_role(
    'foundation_remediation_approver',
    'foundation_remediation_mutator',
    'MEMBER'
  );

  v_admission_executor_member := pg_has_role(
    'foundation_remediation_executor',
    'foundation_remediation_mutator',
    'MEMBER'
  );

  v_service_can_execute := has_function_privilege(
    'service_role',
    'foundation.execute_scoped_remediation_v1(uuid,uuid,uuid,jsonb,timestamptz)',
    'EXECUTE'
  );

  v_approver_can_execute := has_function_privilege(
    'foundation_remediation_approver',
    'foundation.execute_scoped_remediation_v1(uuid,uuid,uuid,jsonb,timestamptz)',
    'EXECUTE'
  );

  v_admission_executor_can_execute := has_function_privilege(
    'foundation_remediation_executor',
    'foundation.execute_scoped_remediation_v1(uuid,uuid,uuid,jsonb,timestamptz)',
    'EXECUTE'
  );

  v_mutator_can_execute := has_function_privilege(
    'foundation_remediation_mutator',
    'foundation.execute_scoped_remediation_v1(uuid,uuid,uuid,jsonb,timestamptz)',
    'EXECUTE'
  );

  v_mutator_registry_update := has_table_privilege(
    'foundation_remediation_mutator',
    'universe.app_registry','UPDATE'
  );

  v_mutator_release_insert := has_table_privilege(
    'foundation_remediation_mutator',
    'universe.readiness_releases','INSERT'
  );

  v_mutator_event_insert := has_table_privilege(
    'foundation_remediation_mutator',
    'foundation.remediation_execution_events','INSERT'
  );

  select count(*) into v_operation_count
  from foundation.remediation_execution_operations
  where lifecycle='active';

  select exists(
    select 1
    from foundation.remediation_execution_operations
    where action_key='auto-repair-authoritative-truth'
      and lifecycle='active'
  ) into v_auto_registered;

  if not v_mutator_exists
     or v_service_member
     or v_approver_member
     or v_admission_executor_member
     or v_service_can_execute
     or v_approver_can_execute
     or v_admission_executor_can_execute
     or not v_mutator_can_execute
     or v_mutator_registry_update
     or v_mutator_release_insert
     or v_mutator_event_insert
     or v_operation_count<>3
     or v_auto_registered then
    v_state := 'fail';
  end if;

  return jsonb_build_object(
    'foundationScopedRemediationExecutorControlHealthResponse',
      'shine-foundation/scoped-remediation-executor-control-health-response-v1',
    'schemaVersion','1.0.0',
    'state',v_state,
    'mutatorRoleExists',v_mutator_exists,
    'serviceRoleIsMutatorMember',v_service_member,
    'approverRoleIsMutatorMember',v_approver_member,
    'admissionExecutorRoleIsMutatorMember',v_admission_executor_member,
    'serviceRoleCanExecute',v_service_can_execute,
    'approverRoleCanExecute',v_approver_can_execute,
    'admissionExecutorRoleCanExecute',v_admission_executor_can_execute,
    'mutatorRoleCanExecute',v_mutator_can_execute,
    'mutatorRoleCanUpdateRegistryDirectly',v_mutator_registry_update,
    'mutatorRoleCanInsertReleaseLedgerDirectly',v_mutator_release_insert,
    'mutatorRoleCanInsertExecutionEventsDirectly',v_mutator_event_insert,
    'activeExecutionOperationCount',v_operation_count,
    'autoRepairRegistered',v_auto_registered,
    'arbitrarySqlExecution',false
  );
end;
$layer41_health$;

revoke all on function foundation.get_scoped_remediation_executor_control_health_v1()
  from public,anon,authenticated,foundation_gateway,
       foundation_remediation_approver,foundation_remediation_executor,
       foundation_remediation_mutator;
grant execute on function foundation.get_scoped_remediation_executor_control_health_v1()
  to foundation_runtime,service_role;
