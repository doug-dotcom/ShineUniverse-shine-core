begin;

drop view foundation.current_foundation_readiness_incident_state;

create view foundation.current_foundation_readiness_incident_state
with(security_invoker=true) as
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
  '["context-operations","protected-operations"]'::jsonb degraded_scopes,
  '["identity-operations"]'::jsonb guarded_scopes,
  '["protected-operations"]'::jsonb blocked_scopes,
  null::uuid readiness_drift_observation_id,
  repeat('2',32)::text evidence_fingerprint,
  now()-interval '10 minutes' detection_started_at,
  300::integer persistence_threshold_seconds,
  600::integer persistence_seconds,
  '{"current":{"privilegedOperationsMode":"degraded","workerOperationsMode":"degraded"}}'::jsonb snapshot,
  now() occurred_at,
  now() recorded_at,
  repeat('9',32)::text condition_fingerprint;

do $p$
declare
  v jsonb;
  v2 jsonb;
  s jsonb;
  pid uuid;
  h text;
begin
  v:=foundation.propose_readiness_dependency_remediation_v1(
    'production',now()
  );

  if v->>'proposed'<>'true'
     or v->>'status'<>'generated'
     or v->>'executionAuthorityGranted'<>'false'
     or v->>'approvalGranted'<>'false'
     or not ((v->'proposal'->'prohibitedWork') ? 'mutate-foundation-canonical-truth')
     or not ((v->'proposal'->'affectedScopes') ? 'protected-operations')
     or jsonb_array_length(v->'proposal'->'affectedScopes')<>3
     or v->'proposal'->>'executionAuthorityGranted'<>'false'
     or v->'proposal'->>'approvalGranted'<>'false' then
    raise exception 'proposal invalid: %',v;
  end if;

  if not exists (
    select 1
    from jsonb_array_elements(v->'proposal'->'scopePlan') x
    where x->>'scope'='protected-operations'
      and x->>'disposition'='blocked'
  ) then
    raise exception 'blocked disposition must outrank duplicate degraded scope: %',
      v->'proposal'->'scopePlan';
  end if;

  pid:=(v->>'proposalId')::uuid;

  v2:=foundation.propose_readiness_dependency_remediation_v1(
    'production',now()+interval '1 minute'
  );

  if v2->>'status'<>'existing'
     or v2->>'proposalId'<>pid::text
     or v2->>'proposalSha256'<>v->>'proposalSha256' then
    raise exception 'same incident condition must reuse original proposal: % %',v,v2;
  end if;

  s:=foundation.get_readiness_dependency_proposal_status_v1(pid);

  if s->>'state'<>'current'
     or s->>'usable'<>'true'
     or s->>'integrityVerified'<>'true'
     or s->>'executionAuthorityGranted'<>'false'
     or s->>'approvalGranted'<>'false' then
    raise exception 'proposal status invalid: %',s;
  end if;

  select encode(
    extensions.digest(convert_to(proposal::text,'UTF8'),'sha256'),'hex'
  ) into h
  from foundation.readiness_dependency_remediation_proposals
  where proposal_id=pid;

  if h<>v->>'proposalSha256' then
    raise exception 'stored proposal integrity hash mismatch';
  end if;
end;
$p$;

-- A materially changed active condition makes the old proposal stale.
drop view foundation.current_foundation_readiness_incident_state;

create view foundation.current_foundation_readiness_incident_state
with(security_invoker=true) as
select
  2::bigint event_sequence,
  '47000000-0000-4000-8000-000000000002'::uuid event_id,
  'production:readiness'::text incident_key,
  'production'::text environment,
  'changed'::text event_type,
  'not-ready'::text readiness_state,
  'not-bindable'::text drift_state,
  'critical'::text severity,
  '["dependency-blocked"]'::jsonb reason_codes,
  '[]'::jsonb degraded_scopes,
  '[]'::jsonb guarded_scopes,
  '["protected-operations"]'::jsonb blocked_scopes,
  null::uuid readiness_drift_observation_id,
  repeat('3',32)::text evidence_fingerprint,
  now()-interval '10 minutes' detection_started_at,
  300::integer persistence_threshold_seconds,
  601::integer persistence_seconds,
  '{"current":{"privilegedOperationsMode":"blocked","workerOperationsMode":"blocked"}}'::jsonb snapshot,
  now()+interval '1 second' occurred_at,
  now()+interval '1 second' recorded_at,
  repeat('8',32)::text condition_fingerprint;

do $stale$
declare
  pid uuid;
  s jsonb;
begin
  select proposal_id into pid
  from foundation.readiness_dependency_remediation_proposals
  order by proposal_sequence desc limit 1;

  s:=foundation.get_readiness_dependency_proposal_status_v1(pid);

  if s->>'state'<>'stale'
     or s->>'usable'<>'false' then
    raise exception 'old proposal must stale after condition change: %',s;
  end if;
end;
$stale$;

do $security$
begin
  if has_function_privilege(
    'foundation_runtime',
    'foundation.propose_readiness_dependency_remediation_v1(text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'runtime must not generate readiness remediation proposals';
  end if;

  if not has_function_privilege(
    'service_role',
    'foundation.propose_readiness_dependency_remediation_v1(text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'service_role must generate readiness remediation proposals';
  end if;

  if has_table_privilege(
    'service_role',
    'foundation.readiness_dependency_remediation_proposals',
    'INSERT'
  ) then
    raise exception 'service_role must not bypass proposal generator';
  end if;
end;
$security$;

rollback;
