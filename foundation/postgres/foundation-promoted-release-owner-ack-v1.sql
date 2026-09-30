-- Foundation Layer 68: Shine Core acknowledgement of promoted-release owner handoffs.
-- Ownership acknowledgement is deliberately isolated from the Gateway execution
-- surface and grants no approval, release-truth mutation or remediation authority.

do $layer68_role$
begin
  if not exists(
    select 1 from pg_roles where rolname='shine_core_control_plane'
  ) then
    raise exception 'shine-core-control-plane-role-missing';
  end if;

  if exists(
    select 1
    from pg_roles
    where rolname='shine_core_control_plane'
      and (
        rolcanlogin
        or rolinherit
        or rolsuper
        or rolcreatedb
        or rolcreaterole
        or rolbypassrls
      )
  ) then
    raise exception 'shine-core-control-plane-role-posture-invalid';
  end if;

  if not pg_has_role(
    'postgres','shine_core_control_plane','MEMBER'
  ) then
    raise exception 'shine-core-control-plane-postgres-membership-missing';
  end if;

  if pg_has_role(
    'foundation_gateway','shine_core_control_plane','MEMBER'
  ) then
    raise exception 'shine-core-control-plane-gateway-membership-forbidden';
  end if;

  if pg_has_role(
    'foundation_runtime','shine_core_control_plane','MEMBER'
  ) then
    raise exception 'shine-core-control-plane-runtime-membership-forbidden';
  end if;
end;
$layer68_role$;

grant usage on schema foundation to shine_core_control_plane;

create table foundation.foundation_promoted_release_owner_handoff_responses (
  response_sequence bigint generated always as identity primary key,
  response_id uuid not null unique default gen_random_uuid(),
  handoff_id uuid not null unique
    references foundation.foundation_promoted_release_owner_handoffs(handoff_id),
  incident_event_id uuid not null
    references foundation.foundation_promoted_release_incident_events(event_id),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  owner_service_id text not null
    references foundation.service_registry(service_id),
  owner_component text not null,
  response_state text not null
    check (
      response_state in (
        'accepted',
        'rejected',
        'clarification-requested'
      )
    ),
  reason_code text not null
    check (reason_code ~ '^[a-z0-9][a-z0-9._:-]*$'),
  response_note text,
  handoff_sha256 text not null
    check (handoff_sha256 ~ '^[a-f0-9]{64}$'),
  response_plan_fingerprint text not null
    check (response_plan_fingerprint ~ '^[a-f0-9]{64}$'),
  response jsonb not null
    check (jsonb_typeof(response)='object'),
  response_sha256 text not null
    check (response_sha256 ~ '^[a-f0-9]{64}$'),
  responded_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  check (
    response_note is null
    or char_length(response_note)<=2000
  )
);

alter table foundation.foundation_promoted_release_owner_handoff_responses
  enable row level security;

create policy shine_core_control_plane_promoted_release_handoff_responses_select
on foundation.foundation_promoted_release_owner_handoff_responses
for select
to shine_core_control_plane
using (true);

revoke all on foundation.foundation_promoted_release_owner_handoff_responses
  from public,anon,authenticated,foundation_gateway,foundation_runtime,
       shine_defence_runtime,shine_core_control_plane,service_role;
grant select on foundation.foundation_promoted_release_owner_handoff_responses
  to service_role;

create index foundation_promoted_release_owner_responses_incident_idx
  on foundation.foundation_promoted_release_owner_handoff_responses(
    incident_event_id,responded_at desc,response_sequence desc
  );

create index foundation_promoted_release_owner_responses_service_idx
  on foundation.foundation_promoted_release_owner_handoff_responses(
    owner_service_id,environment,responded_at desc,response_sequence desc
  );

create trigger foundation_promoted_release_owner_responses_append_only
before update or delete
on foundation.foundation_promoted_release_owner_handoff_responses
for each row execute function foundation.reject_append_only_mutation();

create or replace function foundation.respond_foundation_promoted_release_owner_handoff_v1(
  p_handoff_id uuid,
  p_response_state text,
  p_reason_code text,
  p_response_note text default null,
  p_responded_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer68_respond$
declare
  v_handoff foundation.foundation_promoted_release_owner_handoffs%rowtype;
  v_status jsonb;
  v_existing foundation.foundation_promoted_release_owner_handoff_responses%rowtype;
  v_doc jsonb;
  v_doc_hash text;
  v_response_id uuid;
begin
  if p_handoff_id is null then
    raise exception 'promoted-release-owner-response-handoff-required';
  end if;

  if p_response_state not in (
    'accepted','rejected','clarification-requested'
  ) then
    raise exception 'promoted-release-owner-response-state-invalid';
  end if;

  if p_reason_code is null
     or p_reason_code !~ '^[a-z0-9][a-z0-9._:-]*$' then
    raise exception 'promoted-release-owner-response-reason-invalid';
  end if;

  if p_response_note is not null
     and char_length(p_response_note)>2000 then
    raise exception 'promoted-release-owner-response-note-too-large';
  end if;

  if p_responded_at is null
     or p_responded_at<now()-interval '5 minutes'
     or p_responded_at>now()+interval '5 minutes' then
    raise exception 'promoted-release-owner-response-time-invalid';
  end if;

  select * into v_handoff
  from foundation.foundation_promoted_release_owner_handoffs
  where handoff_id=p_handoff_id;

  if v_handoff.handoff_id is null then
    return jsonb_build_object(
      'foundationPromotedReleaseOwnerHandoffResponse',
        'shine-foundation/promoted-release-owner-handoff-ack-response-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','promoted-release-owner-handoff-not-found',
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesAction',false
    );
  end if;

  if v_handoff.owner_service_id<>'foundation.gateway'
     or v_handoff.owner_component<>'shine-core' then
    raise exception 'promoted-release-owner-response-not-addressed-to-shine-core';
  end if;

  v_status :=
    foundation.get_foundation_promoted_release_owner_handoff_status_v1(
      v_handoff.handoff_id,p_responded_at
    );

  if v_status->>'state'<>'current'
     or coalesce(v_status->>'integrityVerified','false')<>'true'
     or coalesce(v_status->>'ownerRouteCurrent','false')<>'true' then
    return jsonb_build_object(
      'foundationPromotedReleaseOwnerHandoffResponse',
        'shine-foundation/promoted-release-owner-handoff-ack-response-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','promoted-release-owner-handoff-not-current',
      'handoffState',v_status->>'state',
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesAction',false
    );
  end if;

  select * into v_existing
  from foundation.foundation_promoted_release_owner_handoff_responses
  where handoff_id=v_handoff.handoff_id;

  if v_existing.response_id is not null then
    return jsonb_build_object(
      'foundationPromotedReleaseOwnerHandoffResponse',
        'shine-foundation/promoted-release-owner-handoff-ack-response-v1',
      'schemaVersion','1.0.0',
      'status','existing',
      'responseId',v_existing.response_id,
      'handoffId',v_existing.handoff_id,
      'responseState',v_existing.response_state,
      'responseSha256',v_existing.response_sha256,
      'acknowledgesWorkOwnership',
        v_existing.response_state='accepted',
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesAction',false
    );
  end if;

  v_doc := jsonb_build_object(
    'foundationPromotedReleaseOwnerHandoffAcknowledgement',
      'shine-foundation/promoted-release-owner-handoff-ack-v1',
    'schemaVersion','1.0.0',
    'handoffId',v_handoff.handoff_id,
    'incidentEventId',v_handoff.incident_event_id,
    'environment',v_handoff.environment,
    'ownerServiceId',v_handoff.owner_service_id,
    'ownerComponent',v_handoff.owner_component,
    'responseState',p_response_state,
    'reasonCode',p_reason_code,
    'responseNote',p_response_note,
    'handoffSha256',v_handoff.handoff_sha256,
    'responsePlanFingerprint',v_handoff.response_plan_fingerprint,
    'acknowledgesWorkOwnership',p_response_state='accepted',
    'workOwnershipOnly',p_response_state='accepted',
    'layer38ApprovalGranted',false,
    'releaseTruthMutationAuthorityGranted',false,
    'releaseRebindAuthorityGranted',false,
    'incidentHistoryMutationAuthorityGranted',false,
    'runtimeMutationAuthorityGranted',false,
    'incidentClosurePerformed',false,
    'promotionTrustChanged',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false,
    'respondedAt',p_responded_at
  );

  v_doc_hash := encode(
    extensions.digest(
      convert_to(v_doc::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  insert into foundation.foundation_promoted_release_owner_handoff_responses(
    handoff_id,
    incident_event_id,
    environment,
    owner_service_id,
    owner_component,
    response_state,
    reason_code,
    response_note,
    handoff_sha256,
    response_plan_fingerprint,
    response,
    response_sha256,
    responded_at
  )
  values (
    v_handoff.handoff_id,
    v_handoff.incident_event_id,
    v_handoff.environment,
    v_handoff.owner_service_id,
    v_handoff.owner_component,
    p_response_state,
    p_reason_code,
    p_response_note,
    v_handoff.handoff_sha256,
    v_handoff.response_plan_fingerprint,
    v_doc,
    v_doc_hash,
    p_responded_at
  )
  returning response_id into v_response_id;

  return jsonb_build_object(
    'foundationPromotedReleaseOwnerHandoffResponse',
      'shine-foundation/promoted-release-owner-handoff-ack-response-v1',
    'schemaVersion','1.0.0',
    'status','recorded',
    'responseId',v_response_id,
    'handoffId',v_handoff.handoff_id,
    'responseState',p_response_state,
    'responseSha256',v_doc_hash,
    'acknowledgesWorkOwnership',p_response_state='accepted',
    'workOwnershipOnly',p_response_state='accepted',
    'layer38ApprovalGranted',false,
    'releaseTruthMutationAuthorityGranted',false,
    'releaseRebindAuthorityGranted',false,
    'incidentHistoryMutationAuthorityGranted',false,
    'runtimeMutationAuthorityGranted',false,
    'incidentClosurePerformed',false,
    'promotionTrustChanged',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false
  );
end;
$layer68_respond$;

revoke all on function foundation.respond_foundation_promoted_release_owner_handoff_v1(
  uuid,text,text,text,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_defence_runtime,service_role;
grant execute on function foundation.respond_foundation_promoted_release_owner_handoff_v1(
  uuid,text,text,text,timestamptz
) to shine_core_control_plane;

create or replace function foundation.get_foundation_promoted_release_owner_handoff_response_status_v1(
  p_handoff_id uuid,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer68_status$
declare
  v_handoff_status jsonb;
  v_response foundation.foundation_promoted_release_owner_handoff_responses%rowtype;
  v_expected_hash text;
  v_state text;
begin
  v_handoff_status :=
    foundation.get_foundation_promoted_release_owner_handoff_status_v1(
      p_handoff_id,p_as_of
    );

  select * into v_response
  from foundation.foundation_promoted_release_owner_handoff_responses
  where handoff_id=p_handoff_id;

  if v_response.response_id is null then
    return jsonb_build_object(
      'foundationPromotedReleaseOwnerHandoffResponseStatus',
        'shine-foundation/promoted-release-owner-handoff-ack-status-v1',
      'schemaVersion','1.0.0',
      'state',case
        when v_handoff_status->>'state'='current' then 'pending'
        else 'stale'
      end,
      'handoffId',p_handoff_id,
      'handoffState',v_handoff_status->>'state',
      'integrityVerified',false,
      'acknowledgesWorkOwnership',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesAction',false
    );
  end if;

  v_expected_hash := encode(
    extensions.digest(
      convert_to(v_response.response::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  v_state := case
    when v_expected_hash is distinct from v_response.response_sha256
      then 'invalid'
    when v_handoff_status->>'state'<>'current'
      then 'stale'
    else v_response.response_state
  end;

  return jsonb_build_object(
    'foundationPromotedReleaseOwnerHandoffResponseStatus',
      'shine-foundation/promoted-release-owner-handoff-ack-status-v1',
    'schemaVersion','1.0.0',
    'state',v_state,
    'handoffId',v_response.handoff_id,
    'responseId',v_response.response_id,
    'responseState',v_response.response_state,
    'reasonCode',v_response.reason_code,
    'responseNote',v_response.response_note,
    'handoffState',v_handoff_status->>'state',
    'integrityVerified',v_expected_hash=v_response.response_sha256,
    'acknowledgesWorkOwnership',
      v_response.response_state='accepted',
    'workOwnershipOnly',
      v_response.response_state='accepted',
    'layer38ApprovalGranted',false,
    'releaseTruthMutationAuthorityGranted',false,
    'releaseRebindAuthorityGranted',false,
    'incidentHistoryMutationAuthorityGranted',false,
    'runtimeMutationAuthorityGranted',false,
    'incidentClosurePerformed',false,
    'promotionTrustChanged',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false,
    'respondedAt',v_response.responded_at
  );
end;
$layer68_status$;

revoke all on function foundation.get_foundation_promoted_release_owner_handoff_response_status_v1(
  uuid,timestamptz
) from public,anon,authenticated,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.get_foundation_promoted_release_owner_handoff_response_status_v1(
  uuid,timestamptz
) to foundation_runtime,service_role,shine_core_control_plane;

create or replace function foundation.get_foundation_promoted_release_owner_inbox_v1(
  p_environment text default 'production',
  p_limit integer default 25,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer68_inbox$
declare
  v_rec record;
  v_handoff_status jsonb;
  v_response_status jsonb;
  v_items jsonb := '[]'::jsonb;
  v_pending_count integer := 0;
  v_visible_count integer := 0;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$' then
    raise exception 'promoted-release-owner-inbox-environment-invalid';
  end if;

  if p_limit is null or p_limit<1 or p_limit>100 then
    raise exception 'promoted-release-owner-inbox-limit-invalid';
  end if;

  if p_as_of is null then
    raise exception 'promoted-release-owner-inbox-time-invalid';
  end if;

  for v_rec in
    select *
    from foundation.foundation_promoted_release_owner_handoffs
    where environment=p_environment
      and owner_service_id='foundation.gateway'
      and owner_component='shine-core'
    order by handoff_sequence desc
  loop
    v_handoff_status :=
      foundation.get_foundation_promoted_release_owner_handoff_status_v1(
        v_rec.handoff_id,p_as_of
      );

    if v_handoff_status->>'state'<>'current'
       or coalesce(v_handoff_status->>'integrityVerified','false')<>'true'
       or coalesce(v_handoff_status->>'ownerRouteCurrent','false')<>'true' then
      continue;
    end if;

    v_response_status :=
      foundation.get_foundation_promoted_release_owner_handoff_response_status_v1(
        v_rec.handoff_id,p_as_of
      );

    if v_response_status->>'state'<>'pending' then
      continue;
    end if;

    v_pending_count := v_pending_count+1;

    if v_visible_count<p_limit then
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
          'handoffState','current',
          'responseState','pending',
          'integrityVerified',true,
          'approvalGranted',false,
          'executionAuthorityGranted',false,
          'executesAction',false,
          'createdAt',v_rec.created_at
        )
      );
      v_visible_count := v_visible_count+1;
    end if;
  end loop;

  return jsonb_build_object(
    'foundationPromotedReleaseOwnerInbox',
      'shine-foundation/promoted-release-owner-inbox-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'ownerServiceId','foundation.gateway',
    'ownerComponent','shine-core',
    'responderRole','shine_core_control_plane',
    'responseFunction',
      'foundation.respond_foundation_promoted_release_owner_handoff_v1',
    'pendingCount',v_pending_count,
    'visibleCount',v_visible_count,
    'hasMore',v_pending_count>v_visible_count,
    'items',v_items,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false
  );
end;
$layer68_inbox$;

revoke all on function foundation.get_foundation_promoted_release_owner_inbox_v1(
  text,integer,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_defence_runtime,service_role;
grant execute on function foundation.get_foundation_promoted_release_owner_inbox_v1(
  text,integer,timestamptz
) to shine_core_control_plane;
