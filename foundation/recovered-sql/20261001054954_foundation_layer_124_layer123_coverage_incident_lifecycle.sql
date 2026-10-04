
create table foundation.case_audit_layer122_coverage_incident_events(
 event_sequence bigint generated always as identity primary key,event_id uuid not null unique default gen_random_uuid(),
 incident_key text not null check(incident_key ~ '^[a-z0-9][a-z0-9._:-]*$'),environment text not null check(environment ~ '^[a-z0-9][a-z0-9._-]*$'),
 event_type text not null check(event_type in('detected','opened','changed','recovered')),source_state text not null check(source_state in('idle','normal','pending','gap','invalid')),
 severity text not null check(severity in('info','critical')),reason_code text not null,evidence_fingerprint text not null check(evidence_fingerprint ~ '^[a-f0-9]{64}$'),
 detection_started_at timestamptz not null,persistence_threshold_seconds int not null check(persistence_threshold_seconds between 60 and 3600),persistence_seconds int not null check(persistence_seconds>=0),
 snapshot jsonb not null check(jsonb_typeof(snapshot)='object'),occurred_at timestamptz not null,evidence_ref text not null unique,recorded_at timestamptz not null default now());
alter table foundation.case_audit_layer122_coverage_incident_events enable row level security;
create policy foundation_runtime_layer122_incident_select on foundation.case_audit_layer122_coverage_incident_events for select to foundation_runtime using(true);
create policy client_access_explicit_deny on foundation.case_audit_layer122_coverage_incident_events as restrictive for all to anon,authenticated using(false) with check(false);
revoke all on foundation.case_audit_layer122_coverage_incident_events from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime,service_role;
grant select on foundation.case_audit_layer122_coverage_incident_events to foundation_runtime,service_role;
create index case_audit_layer122_incident_key_time_idx on foundation.case_audit_layer122_coverage_incident_events(incident_key,occurred_at desc,event_sequence desc);
create trigger case_audit_layer122_incident_append_only before update or delete on foundation.case_audit_layer122_coverage_incident_events for each row execute function foundation.reject_append_only_mutation();

create or replace function foundation.transition_case_audit_layer122_coverage_incident_v1(p_environment text,p_snapshot jsonb,p_observed_at timestamptz,p_persistence_threshold_seconds int default 300)
returns jsonb language plpgsql security definer set search_path='' as $$
declare k text;s text;r text;fp text;prior foundation.case_audit_layer122_coverage_incident_events%rowtype;et text;ds timestamptz;ps int:=0;id uuid;sev text;
begin
 if p_snapshot->>'foundationCaseAuditLayer122ReconciliationCoverage' is distinct from 'shine-foundation/case-audit-layer122-reconciliation-coverage-v1' then raise exception 'case-audit-layer122-incident-snapshot-invalid';end if;
 s:=coalesce(p_snapshot->>'state','invalid');r:=coalesce(nullif(p_snapshot->>'reasonCode',''),'case-audit-layer122-state');
 fp:=encode(extensions.digest(convert_to(p_snapshot::text,'UTF8'),'sha256'),'hex');k:=p_environment||':case_audit_layer122_reconciliation_coverage';
 select * into prior from foundation.case_audit_layer122_coverage_incident_events where incident_key=k order by occurred_at desc,event_sequence desc limit 1;
 if s in('gap','invalid') then sev:='critical';
  if prior.event_id is null or prior.event_type='recovered' then et:='detected';ds:=p_observed_at;
  elsif prior.event_type='detected' then ds:=prior.detection_started_at;ps:=greatest(0,floor(extract(epoch from(p_observed_at-ds)))::int);if ps>=p_persistence_threshold_seconds then et:='opened';end if;
  elsif prior.event_type in('opened','changed') and(prior.source_state is distinct from s or prior.evidence_fingerprint is distinct from fp) then et:='changed';ds:=prior.detection_started_at;ps:=greatest(0,floor(extract(epoch from(p_observed_at-ds)))::int);end if;
 else sev:='info';if prior.event_id is not null and prior.event_type in('detected','opened','changed') then et:='recovered';ds:=prior.detection_started_at;ps:=greatest(0,floor(extract(epoch from(p_observed_at-ds)))::int);end if;end if;
 if et is not null then id:=gen_random_uuid();insert into foundation.case_audit_layer122_coverage_incident_events(event_id,incident_key,environment,event_type,source_state,severity,reason_code,evidence_fingerprint,detection_started_at,persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at,evidence_ref)values(id,k,p_environment,et,s,sev,r,fp,coalesce(ds,p_observed_at),p_persistence_threshold_seconds,ps,p_snapshot,p_observed_at,'foundation-layer122-coverage-incident:'||id);end if;
 return jsonb_build_object('foundationCaseAuditLayer122CoverageIncidentTransition','shine-foundation/case-audit-layer122-reconciliation-coverage-incident-transition-v1','schemaVersion','1.0.0','environment',p_environment,'sourceState',s,'severity',sev,'eventType',et,'eventId',id,'eventCreated',et is not null,'evidenceFingerprint',fp,'persistenceSeconds',ps,'automaticReconciliation',false,'automaticRepair',false,'upstreamRerunPerformed',false,'mutatesAuthoritativeTruth',false,'mutatesIncidentHistory',false);
end $$;
revoke all on function foundation.transition_case_audit_layer122_coverage_incident_v1(text,jsonb,timestamptz,integer) from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_core_control_plane,shine_defence_runtime,service_role;
