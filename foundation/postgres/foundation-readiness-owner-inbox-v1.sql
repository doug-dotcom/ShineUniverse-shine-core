-- Foundation Layer 50: authenticated Defence owner inbox for pending remediation handoffs.
-- Exposes only current, integrity-verified, unresponded handoffs addressed to Defence.
-- The inbox is read-only and grants no approval or execution authority.

create index if not exists readiness_remediation_handoffs_owner_inbox_idx
on foundation.readiness_dependency_remediation_handoffs(
  owner_component,
  dependency_service_id,
  environment,
  handoff_sequence desc
);

create or replace function foundation.get_readiness_dependency_remediation_owner_inbox_v1(
  p_environment text default 'production',
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $layer50_inbox$
declare
  rec record;
  handoff_state jsonb;
  response_state jsonb;
  items jsonb := '[]'::jsonb;
  pending_count integer := 0;
  visible_count integer := 0;
begin
  if p_environment is null or btrim(p_environment)='' then
    raise exception 'readiness-owner-inbox-environment-required';
  end if;

  if p_limit is null or p_limit<1 or p_limit>100 then
    raise exception 'readiness-owner-inbox-limit-invalid';
  end if;

  for rec in
    select h.*
    from foundation.readiness_dependency_remediation_handoffs h
    where h.environment=p_environment
      and h.owner_component='universe'
      and h.dependency_service_id='foundation.defence'
    order by h.handoff_sequence desc
  loop
    handoff_state :=
      foundation.get_readiness_dependency_remediation_handoff_status_v1(rec.handoff_id);

    if handoff_state->>'state'<>'current'
       or coalesce(handoff_state->>'integrityVerified','false')<>'true' then
      continue;
    end if;

    response_state :=
      foundation.get_readiness_dependency_remediation_handoff_response_status_v1(rec.handoff_id);

    if response_state->>'state'<>'pending' then
      continue;
    end if;

    pending_count := pending_count + 1;

    if visible_count<p_limit then
      items := items || jsonb_build_array(
        jsonb_build_object(
          'handoffId',rec.handoff_id,
          'proposalId',rec.proposal_id,
          'readinessIncidentEventId',rec.readiness_incident_event_id,
          'environment',rec.environment,
          'ownerComponent',rec.owner_component,
          'dependencyServiceId',rec.dependency_service_id,
          'routedScopes',rec.routed_scopes,
          'handoff',rec.handoff,
          'handoffSha256',rec.handoff_sha256,
          'proposalSha256',rec.proposal_sha256,
          'conditionFingerprint',rec.condition_fingerprint,
          'routingFingerprint',rec.routing_fingerprint,
          'handoffState','current',
          'responseState','pending',
          'integrityVerified',true,
          'approvalGranted',false,
          'executionAuthorityGranted',false,
          'executesAction',false,
          'createdAt',rec.created_at
        )
      );
      visible_count := visible_count + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'foundationReadinessOwnerInbox',
      'shine-foundation/readiness-owner-inbox-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'ownerComponent','universe',
    'dependencyServiceId','foundation.defence',
    'responderRole','shine_defence_runtime',
    'responseFunction',
      'foundation.respond_readiness_dependency_remediation_handoff_v1',
    'pendingCount',pending_count,
    'visibleCount',visible_count,
    'hasMore',pending_count>visible_count,
    'items',items,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false
  );
end;
$layer50_inbox$;

revoke all on function foundation.get_readiness_dependency_remediation_owner_inbox_v1(text,integer)
  from public,anon,authenticated,foundation_runtime,foundation_gateway,service_role;
grant execute on function foundation.get_readiness_dependency_remediation_owner_inbox_v1(text,integer)
  to shine_defence_runtime;
