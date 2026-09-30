-- Foundation Layer 67: durable owner handoff for persistent promoted-release incidents.
-- Converts a current Layer-65 incident + Layer-66 response plan into immutable
-- Shine Core work ownership without granting approval or execution authority.

create or replace function foundation.foundation_promoted_release_owner_plan_fingerprint_v1(
  p_plan jsonb
)
returns text
language sql
immutable
security definer
set search_path = ''
as $layer67_plan_fingerprint$
  select encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'incidentState',p_plan->>'incidentState',
          'trustState',p_plan->>'trustState',
          'causeClass',p_plan->>'causeClass',
          'sourceDomain',p_plan->>'sourceDomain',
          'nextEvidenceAction',p_plan->>'nextEvidenceAction',
          'authorityExpansion',p_plan->'authorityExpansion',
          'automaticRepairAllowed',p_plan->'automaticRepairAllowed',
          'releaseTruthAuthority',p_plan->>'releaseTruthAuthority',
          'actions',coalesce(
            (
              select jsonb_agg(
                jsonb_build_object(
                  'actionKey',a.value->>'actionKey',
                  'actionClass',a.value->>'actionClass',
                  'decision',a.value->>'decision',
                  'requiredControl',a.value->>'requiredControl',
                  'mutatesAuthoritativeTruth',
                    a.value->'mutatesAuthoritativeTruth',
                  'mutatesIncidentHistory',
                    a.value->'mutatesIncidentHistory'
                )
                order by a.value->>'actionKey'
              )
              from jsonb_array_elements(
                coalesce(p_plan->'actions','[]'::jsonb)
              ) a(value)
            ),
            '[]'::jsonb
          )
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$layer67_plan_fingerprint$;

revoke all on function foundation.foundation_promoted_release_owner_plan_fingerprint_v1(jsonb)
  from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_defence_runtime,service_role;


create table foundation.foundation_promoted_release_owner_handoffs (
  handoff_sequence bigint generated always as identity primary key,
  handoff_id uuid not null unique default gen_random_uuid(),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  incident_event_id uuid not null
    references foundation.foundation_promoted_release_incident_events(event_id),
  incident_evidence_fingerprint text not null
    check (incident_evidence_fingerprint ~ '^[a-f0-9]{64}$'),
  incident_state text not null
    check (incident_state in ('warning','critical')),
  cause_class text not null
    check (cause_class ~ '^[a-z0-9][a-z0-9._-]*$'),
  source_domain text not null
    check (source_domain ~ '^[a-z0-9][a-z0-9._-]*$'),
  response_plan_fingerprint text not null
    check (response_plan_fingerprint ~ '^[a-f0-9]{64}$'),
  owner_service_id text not null
    references foundation.service_registry(service_id),
  owner_component text not null,
  requested_actions jsonb not null
    check (jsonb_typeof(requested_actions)='array'),
  handoff jsonb not null
    check (jsonb_typeof(handoff)='object'),
  handoff_sha256 text not null
    check (handoff_sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default now(),
  unique(incident_event_id,response_plan_fingerprint,owner_service_id)
);

alter table foundation.foundation_promoted_release_owner_handoffs
  enable row level security;

create policy foundation_runtime_promoted_release_owner_handoffs_select
on foundation.foundation_promoted_release_owner_handoffs
for select
to foundation_runtime
using (true);

revoke all on foundation.foundation_promoted_release_owner_handoffs
  from public,anon,authenticated,foundation_gateway,shine_defence_runtime,service_role;
grant select on foundation.foundation_promoted_release_owner_handoffs
  to foundation_runtime,service_role;

create index foundation_promoted_release_owner_handoffs_env_time_idx
  on foundation.foundation_promoted_release_owner_handoffs(
    environment,created_at desc,handoff_sequence desc
  );

create index foundation_promoted_release_owner_handoffs_incident_idx
  on foundation.foundation_promoted_release_owner_handoffs(incident_event_id);

create trigger foundation_promoted_release_owner_handoffs_append_only
before update or delete on foundation.foundation_promoted_release_owner_handoffs
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.generate_foundation_promoted_release_owner_handoff_v1(
  p_environment text default 'production',
  p_created_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer67_generate$
declare
  v_incident jsonb;
  v_cause jsonb;
  v_plan jsonb;
  v_current_event jsonb;
  v_incident_event_id uuid;
  v_incident_row foundation.foundation_promoted_release_incident_events%rowtype;
  v_owner foundation.service_registry%rowtype;
  v_plan_fingerprint text;
  v_requested_actions jsonb := '[]'::jsonb;
  v_doc jsonb;
  v_doc_hash text;
  v_existing foundation.foundation_promoted_release_owner_handoffs%rowtype;
  v_handoff_id uuid;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_created_at is null then
    raise exception 'promoted-release-owner-handoff-input-invalid';
  end if;

  v_incident :=
    foundation.get_foundation_promoted_release_incident_summary_v1(
      p_environment,p_created_at,600
    );

  if coalesce(v_incident->>'state','normal') not in ('warning','critical')
     or coalesce((v_incident->>'activeIncidentCount')::integer,0)<1 then
    return jsonb_build_object(
      'foundationPromotedReleaseOwnerHandoffResponse',
        'shine-foundation/promoted-release-owner-handoff-response-v1',
      'schemaVersion','1.0.0',
      'environment',p_environment,
      'status','not-applicable',
      'reasonCode','promoted-release-incident-not-active',
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesAction',false
    );
  end if;

  v_current_event := v_incident->'currentEvent';

  begin
    v_incident_event_id :=
      nullif(v_current_event->>'eventId','')::uuid;
  exception when invalid_text_representation then
    raise exception 'promoted-release-owner-handoff-incident-id-invalid';
  end;

  if v_incident_event_id is null then
    raise exception 'promoted-release-owner-handoff-incident-id-missing';
  end if;

  select * into v_incident_row
  from foundation.foundation_promoted_release_incident_events
  where event_id=v_incident_event_id
    and environment=p_environment
    and event_type in ('opened','changed');

  if v_incident_row.event_id is null then
    raise exception 'promoted-release-owner-handoff-incident-event-invalid';
  end if;

  if v_current_event->>'evidenceFingerprint'
       is distinct from v_incident_row.evidence_fingerprint
     or v_current_event->>'sourceState'
       is distinct from v_incident_row.source_state then
    raise exception 'promoted-release-owner-handoff-incident-evidence-mismatch';
  end if;

  v_cause :=
    foundation.get_foundation_promoted_release_incident_cause_v1(
      p_environment,p_created_at,600
    );

  v_plan :=
    foundation.get_foundation_promoted_release_incident_response_plan_v1(
      p_environment,p_created_at,600
    );

  if v_cause->>'incidentState' is distinct from v_incident->>'state'
     or v_plan->>'incidentState' is distinct from v_incident->>'state'
     or coalesce(v_plan->>'causeClass','unknown')
        is distinct from coalesce(v_cause->>'causeClass','unknown')
     or coalesce(v_plan->>'authorityExpansion','true')<>'false'
     or coalesce(v_plan->>'automaticRepairAllowed','true')<>'false' then
    raise exception 'promoted-release-owner-handoff-response-plan-invalid';
  end if;

  select * into v_owner
  from foundation.service_registry
  where service_id='foundation.gateway'
    and lifecycle='active'
    and nullif(owner_component,'') is not null;

  if v_owner.service_id is null then
    raise exception 'promoted-release-owner-handoff-owner-route-missing';
  end if;

  v_plan_fingerprint :=
    foundation.foundation_promoted_release_owner_plan_fingerprint_v1(v_plan);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'actionKey',a.value->>'actionKey',
        'actionClass',a.value->>'actionClass',
        'decision',a.value->>'decision',
        'requiredControl',a.value->>'requiredControl',
        'mutatesAuthoritativeTruth',
          a.value->'mutatesAuthoritativeTruth',
        'mutatesIncidentHistory',
          a.value->'mutatesIncidentHistory'
      )
      order by
        case a.value->>'decision'
          when 'admit' then 1
          when 'approval-required' then 2
          else 3
        end,
        a.value->>'actionKey'
    ),
    '[]'::jsonb
  )
  into v_requested_actions
  from jsonb_array_elements(coalesce(v_plan->'actions','[]'::jsonb)) a(value)
  where a.value->>'decision' in ('admit','approval-required');

  select * into v_existing
  from foundation.foundation_promoted_release_owner_handoffs h
  where h.incident_event_id=v_incident_event_id
    and h.response_plan_fingerprint=v_plan_fingerprint
    and h.owner_service_id=v_owner.service_id
  order by handoff_sequence desc
  limit 1;

  if v_existing.handoff_id is not null then
    return jsonb_build_object(
      'foundationPromotedReleaseOwnerHandoffResponse',
        'shine-foundation/promoted-release-owner-handoff-response-v1',
      'schemaVersion','1.0.0',
      'environment',p_environment,
      'status','existing',
      'handoffId',v_existing.handoff_id,
      'incidentEventId',v_existing.incident_event_id,
      'ownerServiceId',v_existing.owner_service_id,
      'ownerComponent',v_existing.owner_component,
      'responsePlanFingerprint',v_existing.response_plan_fingerprint,
      'handoffSha256',v_existing.handoff_sha256,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesAction',false
    );
  end if;

  v_doc := jsonb_build_object(
    'foundationPromotedReleaseOwnerHandoff',
      'shine-foundation/promoted-release-owner-handoff-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'incidentEventId',v_incident_event_id,
    'incidentKey',v_incident_row.incident_key,
    'incidentState',v_incident->>'state',
    'incidentSeverity',v_incident_row.severity,
    'incidentSourceState',v_incident_row.source_state,
    'incidentReasonCode',v_incident_row.reason_code,
    'incidentEvidenceFingerprint',v_incident_row.evidence_fingerprint,
    'causeClass',v_cause->>'causeClass',
    'sourceDomain',v_cause->>'sourceDomain',
    'nextEvidenceAction',v_cause->>'nextEvidenceAction',
    'responsePlanFingerprint',v_plan_fingerprint,
    'releaseTruthAuthority',v_plan->>'releaseTruthAuthority',
    'ownerServiceId',v_owner.service_id,
    'ownerComponent',v_owner.owner_component,
    'requestedActions',v_requested_actions,
    'requestedWork',jsonb_build_array(
      'verify-current-incident-and-promotion-trust-evidence',
      'perform-only-actions-admitted-by-layer-66-response-plan',
      'obtain-existing-layer-38-approval-before-authoritative-release-truth-mutation',
      'return-fresh-evidence-for-independent-foundation-re-evaluation'
    ),
    'prohibitedWork',jsonb_build_array(
      'auto-repair-authoritative-truth',
      'bypass-layer-38-release-truth-authority',
      'suppress-promoted-release-incident-history',
      'delete-promoted-release-incident-history',
      'claim-runtime-readiness-from-promotion-trust'
    ),
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false,
    'createdAt',p_created_at
  );

  v_doc_hash := encode(
    extensions.digest(convert_to(v_doc::text,'UTF8'),'sha256'),
    'hex'
  );

  insert into foundation.foundation_promoted_release_owner_handoffs(
    environment,
    incident_event_id,
    incident_evidence_fingerprint,
    incident_state,
    cause_class,
    source_domain,
    response_plan_fingerprint,
    owner_service_id,
    owner_component,
    requested_actions,
    handoff,
    handoff_sha256,
    created_at
  )
  values (
    p_environment,
    v_incident_event_id,
    v_incident_row.evidence_fingerprint,
    v_incident->>'state',
    v_cause->>'causeClass',
    v_cause->>'sourceDomain',
    v_plan_fingerprint,
    v_owner.service_id,
    v_owner.owner_component,
    v_requested_actions,
    v_doc,
    v_doc_hash,
    p_created_at
  )
  returning handoff_id into v_handoff_id;

  return jsonb_build_object(
    'foundationPromotedReleaseOwnerHandoffResponse',
      'shine-foundation/promoted-release-owner-handoff-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'status','generated',
    'handoffId',v_handoff_id,
    'incidentEventId',v_incident_event_id,
    'incidentState',v_incident->>'state',
    'causeClass',v_cause->>'causeClass',
    'ownerServiceId',v_owner.service_id,
    'ownerComponent',v_owner.owner_component,
    'requestedActionCount',jsonb_array_length(v_requested_actions),
    'responsePlanFingerprint',v_plan_fingerprint,
    'handoffSha256',v_doc_hash,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false
  );
end;
$layer67_generate$;

revoke all on function foundation.generate_foundation_promoted_release_owner_handoff_v1(
  text,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_defence_runtime;
grant execute on function foundation.generate_foundation_promoted_release_owner_handoff_v1(
  text,timestamptz
) to service_role;


create or replace function foundation.get_foundation_promoted_release_owner_handoff_status_v1(
  p_handoff_id uuid,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer67_status$
declare
  v_handoff foundation.foundation_promoted_release_owner_handoffs%rowtype;
  v_incident jsonb;
  v_plan jsonb;
  v_current_event_id uuid;
  v_current_plan_fingerprint text;
  v_owner foundation.service_registry%rowtype;
  v_expected_hash text;
  v_state text;
begin
  select * into v_handoff
  from foundation.foundation_promoted_release_owner_handoffs
  where handoff_id=p_handoff_id;

  if v_handoff.handoff_id is null then
    return jsonb_build_object(
      'foundationPromotedReleaseOwnerHandoffStatus',
        'shine-foundation/promoted-release-owner-handoff-status-v1',
      'schemaVersion','1.0.0',
      'state','not-found',
      'usable',false,
      'handoffId',p_handoff_id,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesAction',false
    );
  end if;

  v_expected_hash := encode(
    extensions.digest(
      convert_to(v_handoff.handoff::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  v_incident :=
    foundation.get_foundation_promoted_release_incident_summary_v1(
      v_handoff.environment,p_as_of,600
    );

  begin
    v_current_event_id :=
      nullif(v_incident#>>'{currentEvent,eventId}','')::uuid;
  exception when invalid_text_representation then
    v_current_event_id := null;
  end;

  v_plan :=
    foundation.get_foundation_promoted_release_incident_response_plan_v1(
      v_handoff.environment,p_as_of,600
    );

  v_current_plan_fingerprint :=
    foundation.foundation_promoted_release_owner_plan_fingerprint_v1(v_plan);

  select * into v_owner
  from foundation.service_registry
  where service_id=v_handoff.owner_service_id;

  v_state := case
    when v_expected_hash is distinct from v_handoff.handoff_sha256 then 'invalid'
    when coalesce(v_incident->>'state','normal') not in ('warning','critical')
      then 'stale'
    when v_current_event_id is distinct from v_handoff.incident_event_id
      then 'stale'
    when v_current_plan_fingerprint is distinct from
         v_handoff.response_plan_fingerprint
      then 'stale'
    when v_owner.service_id is null
      or v_owner.lifecycle<>'active'
      or v_owner.owner_component is distinct from v_handoff.owner_component
      then 'stale'
    else 'current'
  end;

  return jsonb_build_object(
    'foundationPromotedReleaseOwnerHandoffStatus',
      'shine-foundation/promoted-release-owner-handoff-status-v1',
    'schemaVersion','1.0.0',
    'state',v_state,
    'usable',v_state='current',
    'handoffId',v_handoff.handoff_id,
    'environment',v_handoff.environment,
    'incidentEventId',v_handoff.incident_event_id,
    'incidentState',v_handoff.incident_state,
    'causeClass',v_handoff.cause_class,
    'sourceDomain',v_handoff.source_domain,
    'ownerServiceId',v_handoff.owner_service_id,
    'ownerComponent',v_handoff.owner_component,
    'responsePlanFingerprint',v_handoff.response_plan_fingerprint,
    'currentResponsePlanFingerprint',v_current_plan_fingerprint,
    'integrityVerified',v_expected_hash=v_handoff.handoff_sha256,
    'ownerRouteCurrent',
      v_owner.service_id is not null
      and v_owner.lifecycle='active'
      and v_owner.owner_component is not distinct from v_handoff.owner_component,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false
  );
end;
$layer67_status$;

revoke all on function foundation.get_foundation_promoted_release_owner_handoff_status_v1(
  uuid,timestamptz
) from public,anon,authenticated,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.get_foundation_promoted_release_owner_handoff_status_v1(
  uuid,timestamptz
) to foundation_runtime,service_role;


create or replace function foundation.get_foundation_promoted_release_owner_handoff_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer67_summary$
declare
  v_rec record;
  v_status jsonb;
  v_items jsonb := '[]'::jsonb;
  v_current_count integer := 0;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_as_of is null then
    raise exception 'promoted-release-owner-handoff-summary-input-invalid';
  end if;

  for v_rec in
    select *
    from foundation.foundation_promoted_release_owner_handoffs
    where environment=p_environment
    order by handoff_sequence desc
  loop
    v_status :=
      foundation.get_foundation_promoted_release_owner_handoff_status_v1(
        v_rec.handoff_id,p_as_of
      );

    if v_status->>'state'<>'current' then
      continue;
    end if;

    v_current_count := v_current_count+1;
    v_items := v_items || jsonb_build_array(
      jsonb_build_object(
        'handoffId',v_rec.handoff_id,
        'incidentEventId',v_rec.incident_event_id,
        'incidentState',v_rec.incident_state,
        'causeClass',v_rec.cause_class,
        'sourceDomain',v_rec.source_domain,
        'ownerServiceId',v_rec.owner_service_id,
        'ownerComponent',v_rec.owner_component,
        'requestedActions',v_rec.requested_actions,
        'handoff',v_rec.handoff,
        'handoffSha256',v_rec.handoff_sha256,
        'responsePlanFingerprint',v_rec.response_plan_fingerprint,
        'createdAt',v_rec.created_at,
        'approvalGranted',false,
        'executionAuthorityGranted',false,
        'executesAction',false
      )
    );
  end loop;

  return jsonb_build_object(
    'foundationPromotedReleaseOwnerHandoffSummary',
      'shine-foundation/promoted-release-owner-handoff-summary-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'ownerServiceId','foundation.gateway',
    'ownerComponent','shine-core',
    'currentHandoffCount',v_current_count,
    'items',v_items,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false
  );
end;
$layer67_summary$;

revoke all on function foundation.get_foundation_promoted_release_owner_handoff_summary_v1(
  text,timestamptz
) from public,anon,authenticated,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.get_foundation_promoted_release_owner_handoff_summary_v1(
  text,timestamptz
) to foundation_runtime,service_role;
