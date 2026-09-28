-- Foundation Layer 46: semantic readiness retest cycles.
-- Raw evidence may refresh without changing the underlying degraded condition.

alter table foundation.foundation_readiness_drift_observations
  add column condition_fingerprint text
    check(condition_fingerprint is null or condition_fingerprint ~ '^[a-f0-9]{32}$');

update foundation.foundation_readiness_drift_observations
set condition_fingerprint=md5(jsonb_build_object(
 'readinessState',current_readiness_state,
 'reasonCodes',reason_codes,
 'degradedScopes',degraded_scopes,
 'guardedScopes',guarded_scopes,
 'blockedScopes',blocked_scopes,
 'privilegedOperationsMode',privileged_operations_mode,
 'workerOperationsMode',worker_operations_mode
)::text)
where condition_fingerprint is null;

alter table foundation.foundation_readiness_drift_observations
  alter column condition_fingerprint set not null;

alter table foundation.foundation_readiness_incident_events
  add column condition_fingerprint text
    check(condition_fingerprint is null or condition_fingerprint ~ '^[a-f0-9]{32}$');

update foundation.foundation_readiness_incident_events e
set condition_fingerprint=o.condition_fingerprint
from foundation.foundation_readiness_drift_observations o
where o.observation_id=e.readiness_drift_observation_id
  and e.condition_fingerprint is null;

alter table foundation.foundation_readiness_incident_events
  alter column condition_fingerprint set not null;

create table foundation.foundation_readiness_retest_cycles(
 cycle_sequence bigint generated always as identity primary key,
 cycle_id uuid not null unique default gen_random_uuid(),
 environment text not null,
 readiness_drift_observation_id uuid not null references foundation.foundation_readiness_drift_observations(observation_id),
 readiness_incident_event_id uuid references foundation.foundation_readiness_incident_events(event_id),
 raw_evidence_fingerprint text not null check(raw_evidence_fingerprint ~ '^[a-f0-9]{32}$'),
 condition_fingerprint text not null check(condition_fingerprint ~ '^[a-f0-9]{32}$'),
 readiness_state text not null,
 transition_type text not null,
 cycle jsonb not null check(jsonb_typeof(cycle)='object'),
 occurred_at timestamptz not null,
 recorded_at timestamptz not null default now()
);
alter table foundation.foundation_readiness_retest_cycles enable row level security;
create policy foundation_runtime_readiness_retest_select on foundation.foundation_readiness_retest_cycles for select to foundation_runtime using(true);
revoke all on foundation.foundation_readiness_retest_cycles from public,anon,authenticated,foundation_gateway;
grant select on foundation.foundation_readiness_retest_cycles to foundation_runtime,service_role;
create index foundation_readiness_retest_observation_idx on foundation.foundation_readiness_retest_cycles(readiness_drift_observation_id);
create index foundation_readiness_retest_incident_idx on foundation.foundation_readiness_retest_cycles(readiness_incident_event_id);
create trigger foundation_readiness_retest_append_only before update or delete on foundation.foundation_readiness_retest_cycles
for each row execute function foundation.reject_append_only_mutation();

create or replace function foundation.record_foundation_readiness_drift_observation_v1(
 p_environment text default 'production',p_observed_at timestamptz default now()
)
returns jsonb language plpgsql security definer set search_path='' as $record$
declare s jsonb;b uuid;fp text;cfp text;oid uuid;
begin
 s:=foundation.get_foundation_readiness_drift_v1(p_environment,p_observed_at);
 if s#>>'{binding,bindingId}' is null then raise exception 'readiness-drift-binding-missing'; end if;
 b:=(s#>>'{binding,bindingId}')::uuid;
 fp:=md5(jsonb_build_object(
  'bindingId',b,'driftState',s->>'driftState','currentFingerprint',s#>>'{current,readinessFingerprint}',
  'reasons',s->'reasonCodes','degradedScopes',s->'degradedScopes',
  'guardedScopes',s->'guardedScopes','blockedScopes',s->'blockedScopes'
 )::text);
 cfp:=md5(jsonb_build_object(
  'readinessState',s#>>'{current,readinessState}','reasonCodes',s->'reasonCodes',
  'degradedScopes',s->'degradedScopes','guardedScopes',s->'guardedScopes','blockedScopes',s->'blockedScopes',
  'privilegedOperationsMode',s#>>'{current,privilegedOperationsMode}',
  'workerOperationsMode',s#>>'{current,workerOperationsMode}'
 )::text);

 select observation_id into oid from foundation.foundation_readiness_drift_observations
 where binding_id=b and evidence_fingerprint=fp order by observed_at desc,observation_sequence desc limit 1;

 if oid is null then
  insert into foundation.foundation_readiness_drift_observations(
   environment,binding_id,release_ref,readiness_state_at_bind,readiness_fingerprint_at_bind,
   current_readiness_state,current_readiness_fingerprint,drift_state,deployment_identity_stable,
   privileged_operations_mode,worker_operations_mode,reason_codes,degraded_scopes,guarded_scopes,
   blocked_scopes,snapshot,evidence_fingerprint,condition_fingerprint,observed_at
  ) values(
   p_environment,b,s#>>'{binding,releaseRef}',s#>>'{binding,readinessStateAtBind}',s#>>'{binding,readinessFingerprintAtBind}',
   s#>>'{current,readinessState}',s#>>'{current,readinessFingerprint}',s->>'driftState',(s->>'deploymentIdentityStable')::boolean,
   s#>>'{current,privilegedOperationsMode}',s#>>'{current,workerOperationsMode}',s->'reasonCodes',s->'degradedScopes',
   s->'guardedScopes',s->'blockedScopes',s,fp,cfp,p_observed_at
  ) returning observation_id into oid;
 end if;
 return jsonb_build_object('observationId',oid,'evidenceFingerprint',fp,'conditionFingerprint',cfp,'snapshot',s);
end;
$record$;

create or replace function foundation.run_foundation_readiness_retest_cycle_v1(
 p_environment text default 'production',p_observed_at timestamptz default now(),p_persistence_threshold_seconds integer default 300
)
returns jsonb language plpgsql security definer set search_path='' as $cycle$
declare r jsonb;o foundation.foundation_readiness_drift_observations%rowtype;
 prior foundation.foundation_readiness_incident_events%rowtype;
 et text;sev text;started timestamptz;secs integer:=0;eid uuid;cid uuid;doc jsonb;
begin
 r:=foundation.record_foundation_readiness_drift_observation_v1(p_environment,p_observed_at);
 select * into o from foundation.foundation_readiness_drift_observations where observation_id=(r->>'observationId')::uuid;
 select * into prior from foundation.foundation_readiness_incident_events
 where incident_key=p_environment||':readiness' order by occurred_at desc,event_sequence desc limit 1;

 if o.current_readiness_state in('restricted','degraded','not-ready','unknown') then
  sev:=case when o.current_readiness_state in('not-ready','unknown') or jsonb_array_length(o.blocked_scopes)>0 then 'critical' else 'warning' end;
  if prior.event_id is null or prior.event_type='recovered' then et:='detected';started:=p_observed_at;
  elsif prior.condition_fingerprint is distinct from o.condition_fingerprint then et:=case when prior.event_type='detected' then 'detected' else 'changed' end;started:=case when prior.event_type='detected' then p_observed_at else prior.detection_started_at end;
  else
   started:=prior.detection_started_at;secs:=greatest(0,floor(extract(epoch from(p_observed_at-started)))::integer);
   if prior.event_type='detected' and secs>=p_persistence_threshold_seconds then et:='opened'; end if;
  end if;
 else
  sev:='info';
  if prior.event_id is not null and prior.event_type in('detected','opened','changed') then et:='recovered';started:=prior.detection_started_at;secs:=greatest(0,floor(extract(epoch from(p_observed_at-started)))::integer); end if;
 end if;

 if et is not null then
  insert into foundation.foundation_readiness_incident_events(
   incident_key,environment,event_type,readiness_state,drift_state,severity,reason_codes,
   degraded_scopes,guarded_scopes,blocked_scopes,readiness_drift_observation_id,evidence_fingerprint,
   condition_fingerprint,detection_started_at,persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at
  ) values(
   p_environment||':readiness',p_environment,et,o.current_readiness_state,o.drift_state,sev,o.reason_codes,
   o.degraded_scopes,o.guarded_scopes,o.blocked_scopes,o.observation_id,o.evidence_fingerprint,
   o.condition_fingerprint,started,p_persistence_threshold_seconds,secs,o.snapshot,p_observed_at
  ) returning event_id into eid;
 else et:='none'; end if;

 doc:=jsonb_build_object(
  'foundationReadinessRetestCycle','shine-foundation/readiness-retest-cycle-v1','schemaVersion','1.0.0',
  'environment',p_environment,'observationId',o.observation_id,'rawEvidenceFingerprint',o.evidence_fingerprint,
  'conditionFingerprint',o.condition_fingerprint,'readinessState',o.current_readiness_state,
  'transitionType',et,'incidentEventId',eid,'persistenceSeconds',secs,'observedAt',p_observed_at
 );
 insert into foundation.foundation_readiness_retest_cycles(
  environment,readiness_drift_observation_id,readiness_incident_event_id,raw_evidence_fingerprint,
  condition_fingerprint,readiness_state,transition_type,cycle,occurred_at
 ) values(p_environment,o.observation_id,eid,o.evidence_fingerprint,o.condition_fingerprint,o.current_readiness_state,et,doc,p_observed_at)
 returning cycle_id into cid;

 return doc||jsonb_build_object('cycleId',cid);
end;
$cycle$;

revoke all on function foundation.run_foundation_readiness_retest_cycle_v1(text,timestamptz,integer)
 from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.run_foundation_readiness_retest_cycle_v1(text,timestamptz,integer) to service_role;
