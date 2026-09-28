-- Foundation Layer 44: persistent readiness-degradation lifecycle.

create table foundation.foundation_readiness_incident_events (
  event_sequence bigint generated always as identity primary key,
  event_id uuid not null unique default gen_random_uuid(),
  incident_key text not null,
  environment text not null,
  event_type text not null check (event_type in ('detected','opened','changed','recovered')),
  readiness_state text not null check (readiness_state in ('ready','restricted','degraded','not-ready','unknown')),
  drift_state text not null check (drift_state in ('stable','operational-degradation','identity-drift','not-bindable')),
  severity text not null check (severity in ('info','warning','critical')),
  reason_codes jsonb not null check (jsonb_typeof(reason_codes)='array'),
  degraded_scopes jsonb not null check (jsonb_typeof(degraded_scopes)='array'),
  guarded_scopes jsonb not null check (jsonb_typeof(guarded_scopes)='array'),
  blocked_scopes jsonb not null check (jsonb_typeof(blocked_scopes)='array'),
  readiness_drift_observation_id uuid not null
    references foundation.foundation_readiness_drift_observations(observation_id),
  evidence_fingerprint text not null check (evidence_fingerprint ~ '^[a-f0-9]{32}$'),
  detection_started_at timestamptz not null,
  persistence_threshold_seconds integer not null check (persistence_threshold_seconds between 60 and 3600),
  persistence_seconds integer not null check (persistence_seconds>=0),
  snapshot jsonb not null check (jsonb_typeof(snapshot)='object'),
  occurred_at timestamptz not null,
  recorded_at timestamptz not null default now()
);

alter table foundation.foundation_readiness_incident_events enable row level security;
create policy foundation_runtime_readiness_incidents_select
on foundation.foundation_readiness_incident_events for select to foundation_runtime using(true);
revoke all on foundation.foundation_readiness_incident_events from public,anon,authenticated,foundation_gateway;
grant select on foundation.foundation_readiness_incident_events to foundation_runtime,service_role;

create index foundation_readiness_incidents_key_idx
 on foundation.foundation_readiness_incident_events(incident_key,occurred_at desc,event_sequence desc);
create index foundation_readiness_incidents_observation_idx
 on foundation.foundation_readiness_incident_events(readiness_drift_observation_id);

create trigger foundation_readiness_incidents_append_only
before update or delete on foundation.foundation_readiness_incident_events
for each row execute function foundation.reject_append_only_mutation();

create view foundation.current_foundation_readiness_incident_state
with(security_invoker=true) as
select distinct on(incident_key) *
from foundation.foundation_readiness_incident_events
order by incident_key,occurred_at desc,event_sequence desc;

revoke all on foundation.current_foundation_readiness_incident_state from public,anon,authenticated,foundation_gateway;
grant select on foundation.current_foundation_readiness_incident_state to foundation_runtime,service_role;

create or replace function foundation.transition_foundation_readiness_incident_v1(
 p_environment text,p_readiness_drift_observation_id uuid,p_observed_at timestamptz,
 p_persistence_threshold_seconds integer default 300
)
returns jsonb language plpgsql security definer set search_path='' as $transition$
declare
 o foundation.foundation_readiness_drift_observations%rowtype;
 prior foundation.foundation_readiness_incident_events%rowtype;
 unhealthy boolean; sev text; et text; started timestamptz; secs integer:=0; eid uuid;
begin
 if p_persistence_threshold_seconds<60 or p_persistence_threshold_seconds>3600 then
  raise exception 'readiness-incident-threshold-invalid';
 end if;
 select * into o from foundation.foundation_readiness_drift_observations where observation_id=p_readiness_drift_observation_id;
 if o.observation_id is null or o.environment is distinct from p_environment then raise exception 'readiness-incident-observation-invalid'; end if;

 unhealthy:=o.current_readiness_state in ('restricted','degraded','not-ready','unknown');
 sev:=case when o.current_readiness_state in ('not-ready','unknown') or jsonb_array_length(o.blocked_scopes)>0 then 'critical' else 'warning' end;

 select * into prior from foundation.foundation_readiness_incident_events
 where incident_key=p_environment||':readiness'
 order by occurred_at desc,event_sequence desc limit 1;

 if unhealthy then
  if prior.event_id is null or prior.event_type='recovered' then
   et:='detected'; started:=p_observed_at;
  elsif prior.event_type='detected' then
   if prior.evidence_fingerprint is distinct from o.evidence_fingerprint then
    et:='detected'; started:=p_observed_at;
   else
    started:=prior.detection_started_at;
    secs:=greatest(0,floor(extract(epoch from(p_observed_at-started)))::integer);
    if secs>=p_persistence_threshold_seconds then et:='opened'; end if;
   end if;
  else
   started:=prior.detection_started_at;
   secs:=greatest(0,floor(extract(epoch from(p_observed_at-started)))::integer);
   if prior.evidence_fingerprint is distinct from o.evidence_fingerprint
      or prior.readiness_state is distinct from o.current_readiness_state then et:='changed'; end if;
  end if;
 else
  if prior.event_id is not null and prior.event_type in ('detected','opened','changed') then
   et:='recovered'; sev:='info'; started:=prior.detection_started_at;
   secs:=greatest(0,floor(extract(epoch from(p_observed_at-started)))::integer);
  else
   return jsonb_build_object('eventType','none','active',false,'watching',false);
  end if;
 end if;

 if et is null then
  return jsonb_build_object('eventType','none','active',prior.event_type in('opened','changed'),'watching',prior.event_type='detected');
 end if;

 insert into foundation.foundation_readiness_incident_events(
  incident_key,environment,event_type,readiness_state,drift_state,severity,
  reason_codes,degraded_scopes,guarded_scopes,blocked_scopes,
  readiness_drift_observation_id,evidence_fingerprint,detection_started_at,
  persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at
 ) values(
  p_environment||':readiness',p_environment,et,o.current_readiness_state,o.drift_state,sev,
  o.reason_codes,o.degraded_scopes,o.guarded_scopes,o.blocked_scopes,
  o.observation_id,o.evidence_fingerprint,started,p_persistence_threshold_seconds,
  secs,o.snapshot,p_observed_at
 ) returning event_id into eid;

 return jsonb_build_object('eventId',eid,'eventType',et,'readinessState',o.current_readiness_state,
  'severity',sev,'persistenceSeconds',secs,'active',et in('opened','changed'),'watching',et='detected');
end;
$transition$;

revoke all on function foundation.transition_foundation_readiness_incident_v1(text,uuid,timestamptz,integer)
 from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.transition_foundation_readiness_incident_v1(text,uuid,timestamptz,integer) to service_role;

create or replace function foundation.run_foundation_readiness_sentinel_v1(
 p_environment text default 'production',p_observed_at timestamptz default now(),p_persistence_threshold_seconds integer default 300
)
returns jsonb language plpgsql security definer set search_path='' as $sentinel$
declare r jsonb; oid uuid; t jsonb;
begin
 r:=foundation.record_foundation_readiness_drift_observation_v1(p_environment,p_observed_at);
 oid:=(r->>'observationId')::uuid;
 t:=foundation.transition_foundation_readiness_incident_v1(p_environment,oid,p_observed_at,p_persistence_threshold_seconds);
 return jsonb_build_object(
  'foundationReadinessSentinelResponse','shine-foundation/readiness-sentinel-response-v1',
  'schemaVersion','1.0.0','observationId',oid,'transition',t,'snapshot',r->'snapshot'
 );
end;
$sentinel$;

revoke all on function foundation.run_foundation_readiness_sentinel_v1(text,timestamptz,integer)
 from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.run_foundation_readiness_sentinel_v1(text,timestamptz,integer) to service_role;

create or replace function foundation.get_foundation_readiness_incident_summary_v1(p_environment text default 'production')
returns jsonb language sql stable security definer set search_path='' as $summary$
 select jsonb_build_object(
  'foundationReadinessIncidentSummaryResponse','shine-foundation/readiness-incident-summary-response-v1',
  'schemaVersion','1.0.0','environment',p_environment,
  'activeIncidentCount',count(*) filter(where event_type in('opened','changed')),
  'watchCount',count(*) filter(where event_type='detected'),
  'state',case when count(*) filter(where event_type in('opened','changed'))>0 then 'incident'
               when count(*) filter(where event_type='detected')>0 then 'watching' else 'normal' end,
  'current',coalesce(jsonb_agg(to_jsonb(s) order by incident_key) filter(where event_type in('detected','opened','changed')),'[]'::jsonb)
 )
 from foundation.current_foundation_readiness_incident_state s where environment=p_environment;
$summary$;

revoke all on function foundation.get_foundation_readiness_incident_summary_v1(text) from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_foundation_readiness_incident_summary_v1(text) to foundation_runtime,service_role;
