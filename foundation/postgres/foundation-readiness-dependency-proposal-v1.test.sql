begin;

-- Layer 47 proposal generation is exercised against a synthetic active incident.
-- Upstream Layers 43-46 separately prove the persisted incident chain.
drop view foundation.current_foundation_readiness_incident_state;
create view foundation.current_foundation_readiness_incident_state
with(security_invoker=true) as
select
  1::bigint as event_sequence,
  '47000000-0000-4000-8000-000000000001'::uuid as event_id,
  'production:readiness'::text as incident_key,
  'production'::text as environment,
  'opened'::text as event_type,
  'degraded'::text as readiness_state,
  'stable'::text as drift_state,
  'warning'::text as severity,
  '["dependency-degraded"]'::jsonb as reason_codes,
  '["protected-operations"]'::jsonb as degraded_scopes,
  '[]'::jsonb as guarded_scopes,
  '[]'::jsonb as blocked_scopes,
  null::uuid as readiness_drift_observation_id,
  repeat('2',32)::text as evidence_fingerprint,
  repeat('9',32)::text as condition_fingerprint,
  now()-interval '10 minutes' as detection_started_at,
  300::integer as persistence_threshold_seconds,
  600::integer as persistence_seconds,
  '{"current":{"privilegedOperationsMode":"degraded","workerOperationsMode":"degraded"}}'::jsonb as snapshot,
  now() as occurred_at,
  now() as recorded_at;

do $proposal$
declare v jsonb;s jsonb;
begin
 v:=foundation.propose_readiness_dependency_remediation_v1('production',now());
 if v->>'proposed'<>'true'
    or v->>'executionAuthorityGranted'<>'false'
    or v->>'approvalGranted'<>'false'
    or not((v->'proposal'->'prohibitedWork') ? 'mutate-foundation-canonical-truth')
    or not((v->'proposal'->'affectedScopes') ? 'protected-operations') then
  raise exception 'Bounded proposal invalid: %',v;
 end if;
 s:=foundation.get_readiness_dependency_proposal_status_v1((v->>'proposalId')::uuid);
 if s->>'state'<>'current' or s->>'usable'<>'true'
    or s->>'executionAuthorityGranted'<>'false'
    or s->>'approvalGranted'<>'false' then
  raise exception 'Fresh proposal must be current but non-authoritative: %',s;
 end if;
end;
$proposal$;

rollback;
