begin;
drop view foundation.current_foundation_readiness_incident_state;
create view foundation.current_foundation_readiness_incident_state with(security_invoker=true) as
select
  1::bigint event_sequence,
  '47000000-0000-4000-8000-000000000001'::uuid event_id,
  'production:readiness'::text incident_key,
  'production'::text environment,
  'opened'::text event_type,
  'degraded'::text readiness_state,
  'stable'::text drift_state,
  'warning'::text severity,
  '["dependency-degraded"]'::jsonb reason_codes,
  '["protected-operations"]'::jsonb degraded_scopes,
  '[]'::jsonb guarded_scopes,
  '[]'::jsonb blocked_scopes,
  null::uuid readiness_drift_observation_id,
  repeat('2',32)::text evidence_fingerprint,
  now()-interval '10 minutes' detection_started_at,
  300::integer persistence_threshold_seconds,
  600::integer persistence_seconds,
  '{"current":{"privilegedOperationsMode":"degraded","workerOperationsMode":"degraded"}}'::jsonb snapshot,
  now() occurred_at,
  now() recorded_at,
  repeat('9',32)::text condition_fingerprint;

insert into foundation.foundation_readiness_incident_events(
 event_id,incident_key,environment,event_type,readiness_state,drift_state,severity,
 reason_codes,degraded_scopes,guarded_scopes,blocked_scopes,readiness_drift_observation_id,
 evidence_fingerprint,detection_started_at,persistence_threshold_seconds,persistence_seconds,
 snapshot,occurred_at,condition_fingerprint
) values(
 '47000000-0000-4000-8000-000000000001','production:readiness','production','opened',
 'degraded','stable','warning','["dependency-degraded"]','["protected-operations"]','[]','[]',
 null,repeat('2',32),now()-interval '10 minutes',300,600,
 '{"current":{"privilegedOperationsMode":"degraded","workerOperationsMode":"degraded"}}',now(),repeat('9',32)
);

do $p$
declare v jsonb;s jsonb;
begin
 v:=foundation.propose_readiness_dependency_remediation_v1('production',now());
 if v->>'proposed'<>'true' or v->>'executionAuthorityGranted'<>'false'
 or v->>'approvalGranted'<>'false'
 or not((v->'proposal'->'prohibitedWork') ? 'mutate-foundation-canonical-truth')
 or not((v->'proposal'->'affectedScopes') ? 'protected-operations')
 then raise exception 'proposal invalid: %',v; end if;
 s:=foundation.get_readiness_dependency_proposal_status_v1((v->>'proposalId')::uuid);
 if s->>'state'<>'current' or s->>'usable'<>'true'
 then raise exception 'proposal status invalid: %',s; end if;
end;$p$;
rollback;
