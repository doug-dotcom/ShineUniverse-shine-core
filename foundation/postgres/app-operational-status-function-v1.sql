-- Historical production backfill: final app operational status contract.
-- Mirrors migration 20260926235253.

drop view if exists foundation.app_operational_status;
revoke select on foundation.app_connection_status from foundation_runtime;

create or replace function foundation.get_app_operational_status_v1(
  p_app_id text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, foundation
as $function$
declare
  c foundation.app_connection_status%rowtype;
  h record;
  op_state text;
  op_health text;
begin
  if p_app_id is null
     or p_app_id !~ '^shine\.[a-z0-9][a-z0-9-]*$' then
    raise exception 'invalid-app-operational-status-request' using errcode='22023';
  end if;

  select * into c
  from foundation.app_connection_status
  where app_id=p_app_id;

  if not found then
    raise exception 'app-unregistered' using errcode='22023';
  end if;

  select * into h
  from foundation.get_app_revocation_health_v1(p_app_id);

  op_state :=
    case
      when c.registry_status <> 'active' then 'disabled'
      when coalesce(h.pending_count,0)=0 then c.connection_state
      when h.freshness_state='pending' then 'revocation-pending'
      when h.stale_action='observe' then 'revocation-stale-observed'
      when h.stale_action='degrade-connected' then 'revocation-stale-degrade-connected'
      when h.stale_action='deny-connected' then 'revocation-stale-deny-connected'
      else 'revocation-stale'
    end;

  op_health :=
    case
      when c.registry_status <> 'active' then 'disabled'
      when coalesce(h.pending_count,0)=0 then 'healthy'
      when h.freshness_state='pending' then 'attention'
      when h.stale_action='observe' then 'attention'
      else 'degraded'
    end;

  return jsonb_build_object(
    'appId', c.app_id,
    'appName', c.app_name,
    'registryStatus', c.registry_status,
    'standalonePrimaryPurposeAvailable', c.standalone_primary_purpose_available,
    'connection', jsonb_build_object(
      'state', c.connection_state,
      'activeCredentials', c.active_credentials,
      'activeIdentityProviders', c.active_identity_providers,
      'activeClaimIdentityProviders', c.active_claim_identity_providers,
      'activeGrants', c.active_grants,
      'observedAllows', c.observed_allows,
      'observedDenies', c.observed_denies,
      'lastObservedAt', c.last_observed_at,
      'lastDecision', c.last_decision,
      'lastReasonCode', c.last_reason_code,
      'successfulIdentityClaims', c.successful_identity_claims,
      'lastIdentityClaimAt', c.last_identity_claim_at,
      'successfulGrantConsents', c.successful_grant_consents,
      'lastGrantConsentAt', c.last_grant_consent_at
    ),
    'revocations', jsonb_build_object(
      'checkpointSequence', h.checkpoint_sequence,
      'latestSequence', h.latest_sequence,
      'pendingCount', h.pending_count,
      'oldestPendingAt', h.oldest_pending_at,
      'pendingAgeSeconds', h.pending_age_seconds,
      'maxPendingAgeSeconds', h.max_pending_age_seconds,
      'freshnessState', h.freshness_state,
      'staleAction', h.stale_action,
      'recommendedAction', h.recommended_action
    ),
    'operationalState', op_state,
    'operationalHealth', op_health
  );
end;
$function$;

revoke all on function foundation.get_app_operational_status_v1(text)
from public,anon,authenticated,service_role;

grant execute on function foundation.get_app_operational_status_v1(text)
to foundation_runtime;
