-- Foundation Layer 43: post-bind readiness drift attribution.
-- Readiness drift is evidence, not a reason to rewrite immutable release identity.

create table foundation.foundation_readiness_drift_observations (
  observation_sequence bigint generated always as identity primary key,
  observation_id uuid not null unique default gen_random_uuid(),
  environment text not null,
  binding_id uuid not null references foundation.foundation_release_identity_bindings(binding_id),
  release_ref text not null,
  readiness_state_at_bind text not null,
  readiness_fingerprint_at_bind text not null,
  current_readiness_state text not null,
  current_readiness_fingerprint text not null,
  drift_state text not null check (drift_state in ('stable','operational-degradation','identity-drift','not-bindable')),
  deployment_identity_stable boolean not null,
  privileged_operations_mode text not null,
  worker_operations_mode text not null,
  reason_codes jsonb not null check (jsonb_typeof(reason_codes)='array'),
  degraded_scopes jsonb not null check (jsonb_typeof(degraded_scopes)='array'),
  guarded_scopes jsonb not null check (jsonb_typeof(guarded_scopes)='array'),
  blocked_scopes jsonb not null check (jsonb_typeof(blocked_scopes)='array'),
  snapshot jsonb not null check (jsonb_typeof(snapshot)='object'),
  evidence_fingerprint text not null check (evidence_fingerprint ~ '^[a-f0-9]{32}$'),
  observed_at timestamptz not null,
  recorded_at timestamptz not null default now()
);

alter table foundation.foundation_readiness_drift_observations enable row level security;
create policy foundation_runtime_readiness_drift_select
on foundation.foundation_readiness_drift_observations for select to foundation_runtime using (true);
revoke all on foundation.foundation_readiness_drift_observations from public,anon,authenticated,foundation_gateway;
grant select on foundation.foundation_readiness_drift_observations to foundation_runtime,service_role;

create index foundation_readiness_drift_binding_idx
  on foundation.foundation_readiness_drift_observations(binding_id,observed_at desc);
create index foundation_readiness_drift_environment_idx
  on foundation.foundation_readiness_drift_observations(environment,observed_at desc,observation_sequence desc);

create trigger foundation_readiness_drift_append_only
before update or delete on foundation.foundation_readiness_drift_observations
for each row execute function foundation.reject_append_only_mutation();

create or replace function foundation.get_foundation_readiness_drift_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb language plpgsql stable security definer set search_path='' as $drift$
declare
  b foundation.foundation_release_identity_bindings%rowtype;
  r jsonb; i jsonb; d jsonb;
  stable boolean; state text; reasons jsonb;
begin
  select * into b from foundation.current_foundation_release_identity
  where service_id='foundation.gateway' and environment=p_environment;

  if b.binding_id is null then
    return jsonb_build_object(
      'foundationReadinessDriftResponse','shine-foundation/readiness-drift-response-v1',
      'schemaVersion','1.0.0','environment',p_environment,'driftState','not-bindable',
      'deploymentIdentityStable',false,'reasonCodes',jsonb_build_array('release-binding-missing')
    );
  end if;

  r:=foundation.evaluate_foundation_readiness_v1(p_environment,p_as_of);
  i:=foundation.get_foundation_release_identity_health_v1(p_environment);
  d:=foundation.get_service_deployment_truth_v1('foundation.gateway',p_environment);

  stable:=coalesce(d->>'truthState','unknown')='aligned'
    and i->>'matchesCurrentDeployment'='true'
    and i->>'matchesCurrentPublication'='true';

  reasons:=coalesce(r->'reasonCodes','[]'::jsonb);

  state:=case
    when not stable then 'identity-drift'
    when coalesce(r->>'readinessState','unknown') in ('not-ready','unknown') then 'not-bindable'
    when r->>'evidenceFingerprint' is not distinct from b.readiness_fingerprint_at_bind then 'stable'
    else 'operational-degradation'
  end;

  return jsonb_build_object(
    'foundationReadinessDriftResponse','shine-foundation/readiness-drift-response-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'binding',jsonb_build_object(
      'bindingId',b.binding_id,'releaseRef',b.release_ref,
      'readinessStateAtBind',b.readiness_state_at_bind,
      'readinessFingerprintAtBind',b.readiness_fingerprint_at_bind
    ),
    'current',jsonb_build_object(
      'readinessState',r->>'readinessState',
      'readinessFingerprint',r->>'evidenceFingerprint',
      'safeMode',r->>'safeMode',
      'privilegedOperationsMode',r->>'privilegedOperationsMode',
      'workerOperationsMode',r->>'workerOperationsMode'
    ),
    'driftState',state,'deploymentIdentityStable',stable,
    'reasonCodes',reasons,
    'degradedScopes',coalesce(r#>'{checks,dependencyRollup,degradedScopes}','[]'::jsonb),
    'guardedScopes',coalesce(r#>'{checks,dependencyRollup,guardedScopes}','[]'::jsonb),
    'blockedScopes',coalesce(r#>'{checks,dependencyRollup,blockedScopes}','[]'::jsonb),
    'requiresReleaseRebind',not stable,
    'requiresMonitoring',state='operational-degradation',
    'privilegedOperationsRestricted',
      coalesce(r->>'privilegedOperationsMode','unknown')<>'normal',
    'readiness',r
  );
end;
$drift$;

revoke all on function foundation.get_foundation_readiness_drift_v1(text,timestamptz)
  from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_foundation_readiness_drift_v1(text,timestamptz)
  to foundation_runtime,service_role;

create or replace function foundation.record_foundation_readiness_drift_observation_v1(
  p_environment text default 'production',
  p_observed_at timestamptz default now()
)
returns jsonb language plpgsql security definer set search_path='' as $record$
declare
  s jsonb; b uuid; fp text; oid uuid;
begin
  s:=foundation.get_foundation_readiness_drift_v1(p_environment,p_observed_at);
  if s#>>'{binding,bindingId}' is null then raise exception 'readiness-drift-binding-missing'; end if;
  b:=(s#>>'{binding,bindingId}')::uuid;
  fp:=md5(jsonb_build_object(
    'bindingId',b,'driftState',s->>'driftState',
    'currentFingerprint',s#>>'{current,readinessFingerprint}',
    'reasons',s->'reasonCodes','degradedScopes',s->'degradedScopes',
    'guardedScopes',s->'guardedScopes','blockedScopes',s->'blockedScopes'
  )::text);

  select observation_id into oid
  from foundation.foundation_readiness_drift_observations
  where binding_id=b and evidence_fingerprint=fp
  order by observed_at desc,observation_sequence desc limit 1;

  if oid is null then
    insert into foundation.foundation_readiness_drift_observations(
      environment,binding_id,release_ref,readiness_state_at_bind,
      readiness_fingerprint_at_bind,current_readiness_state,
      current_readiness_fingerprint,drift_state,deployment_identity_stable,
      privileged_operations_mode,worker_operations_mode,reason_codes,
      degraded_scopes,guarded_scopes,blocked_scopes,snapshot,evidence_fingerprint,
      observed_at
    ) values (
      p_environment,b,s#>>'{binding,releaseRef}',s#>>'{binding,readinessStateAtBind}',
      s#>>'{binding,readinessFingerprintAtBind}',s#>>'{current,readinessState}',
      s#>>'{current,readinessFingerprint}',s->>'driftState',
      (s->>'deploymentIdentityStable')::boolean,
      s#>>'{current,privilegedOperationsMode}',s#>>'{current,workerOperationsMode}',
      s->'reasonCodes',s->'degradedScopes',s->'guardedScopes',s->'blockedScopes',
      s,fp,p_observed_at
    ) returning observation_id into oid;
  end if;

  return jsonb_build_object(
    'foundationReadinessDriftObservationResponse','shine-foundation/readiness-drift-observation-response-v1',
    'schemaVersion','1.0.0','observationId',oid,'evidenceFingerprint',fp,'snapshot',s
  );
end;
$record$;

revoke all on function foundation.record_foundation_readiness_drift_observation_v1(text,timestamptz)
  from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.record_foundation_readiness_drift_observation_v1(text,timestamptz)
  to service_role;
