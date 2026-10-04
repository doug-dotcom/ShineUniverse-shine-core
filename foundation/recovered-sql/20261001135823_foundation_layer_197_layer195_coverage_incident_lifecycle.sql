
create table foundation.case_audit_layer195_coverage_incident_events(
 event_sequence bigint generated always as identity primary key,event_id uuid not null default gen_random_uuid() unique,incident_key text not null,
 environment text not null,event_type text not null check(event_type in('detected','opened','changed','recovered')),
 source_state text not null check(source_state in('idle','normal','pending','gap','invalid')),severity text not null check(severity in('info','critical')),
 reason_code text not null,evidence_fingerprint text not null check(evidence_fingerprint ~ '^[0-9a-f]{64}$'),detection_started_at timestamptz not null,
 persistence_threshold_seconds int not null check(persistence_threshold_seconds between 60 and 3600),persistence_seconds int not null check(persistence_seconds>=0),
 snapshot jsonb not null,occurred_at timestamptz not null,evidence_ref text not null,recorded_at timestamptz not null default now());
alter table foundation.case_audit_layer195_coverage_incident_events enable row level security;
create policy "service_role_only_layer195_incidents" on foundation.case_audit_layer195_coverage_incident_events for all to service_role using(true) with check(true);
revoke all on foundation.case_audit_layer195_coverage_incident_events from public,anon,authenticated;
grant select,insert on foundation.case_audit_layer195_coverage_incident_events to service_role;
create index case_audit_layer195_incident_key_time_idx on foundation.case_audit_layer195_coverage_incident_events(incident_key,occurred_at desc,event_sequence desc);

create or replace function foundation.get_case_audit_layer195_coverage_semantic_fingerprint_v1(p_coverage jsonb)
returns text language plpgsql immutable security definer set search_path=''
as $$
declare s jsonb;
begin
 if p_coverage is null or jsonb_typeof(p_coverage)<>'object'
 or p_coverage->>'foundationCaseAuditLayer195ReconciliationCoverage' is distinct from 'shine-foundation/case-audit-layer195-reconciliation-coverage-v1'
 or p_coverage->>'schemaVersion' is distinct from '1.0.0' then raise exception 'case-audit-layer195-semantic-fingerprint-input-invalid';end if;
 s:=jsonb_build_object('state',p_coverage->>'state','successfulLayer194ExecutionCount',coalesce((p_coverage->>'successfulLayer194ExecutionCount')::int,0),
 'layer195ReconciliationRequiredCount',coalesce((p_coverage->>'layer195ReconciliationRequiredCount')::int,0),'layer195ReconciliationReceiptCount',coalesce((p_coverage->>'layer195ReconciliationReceiptCount')::int,0),
 'reconciledCount',coalesce((p_coverage->>'reconciledCount')::int,0),'pendingCount',coalesce((p_coverage->>'pendingCount')::int,0),'overdueCount',coalesce((p_coverage->>'overdueCount')::int,0),
 'invalidLayer195ReconciliationCount',coalesce((p_coverage->>'invalidLayer195ReconciliationCount')::int,0),'missingLayer189ReceiptCount',coalesce((p_coverage->>'missingLayer189ReceiptCount')::int,0),
 'executionReceiptMismatchCount',coalesce((p_coverage->>'executionReceiptMismatchCount')::int,0),'admissionValidationDriftCount',coalesce((p_coverage->>'admissionValidationDriftCount')::int,0),
 'policyDriftCount',coalesce((p_coverage->>'policyDriftCount')::int,0),'incidentIntegrityDriftCount',coalesce((p_coverage->>'incidentIntegrityDriftCount')::int,0),
 'incidentStateDriftCount',coalesce((p_coverage->>'incidentStateDriftCount')::int,0),'incidentBindingDriftCount',coalesce((p_coverage->>'incidentBindingDriftCount')::int,0),
 'semanticCurrentnessDriftCount',coalesce((p_coverage->>'semanticCurrentnessDriftCount')::int,0),'problemCount',coalesce((p_coverage->>'problemCount')::int,0));
 return encode(extensions.digest(convert_to(s::text,'UTF8'),'sha256'),'hex');
end $$;

create or replace function foundation.transition_case_audit_layer195_coverage_incident_v1(
 p_environment text,p_snapshot jsonb,p_observed_at timestamptz,p_persistence_threshold_seconds int default 300)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare k text;st text;fp text;prior foundation.case_audit_layer195_coverage_incident_events%rowtype;et text;started timestamptz;secs int:=0;eid uuid;sev text;reason text;
begin
 if p_environment is null or p_environment !~ '^[a-z0-9][a-z0-9._-]*$' or p_observed_at is null or p_persistence_threshold_seconds not between 60 and 3600
 then raise exception 'case-audit-layer195-incident-input-invalid';end if;
 if p_snapshot is null or p_snapshot->>'foundationCaseAuditLayer195ReconciliationCoverage' is distinct from 'shine-foundation/case-audit-layer195-reconciliation-coverage-v1'
 or p_snapshot->>'environment' is distinct from p_environment then raise exception 'case-audit-layer195-incident-snapshot-invalid';end if;
 st:=coalesce(p_snapshot->>'state','invalid');fp:=foundation.get_case_audit_layer195_coverage_semantic_fingerprint_v1(p_snapshot);
 reason:=case st when 'invalid' then 'case-audit-layer195-receipt-invalid' when 'gap' then 'case-audit-layer195-coverage-gap' when 'pending' then 'case-audit-layer195-within-grace'
 when 'idle' then 'case-audit-layer195-no-executions' else 'case-audit-layer195-covered' end;k:=p_environment||':case_audit_layer195_reconciliation_coverage';
 select x.* into prior from foundation.case_audit_layer195_coverage_incident_events x where x.incident_key=k order by x.occurred_at desc,x.event_sequence desc limit 1;
 if st in('gap','invalid') then sev:='critical';
  if prior.event_id is null or prior.event_type='recovered' then et:='detected';started:=p_observed_at;
  elsif prior.event_type='detected' then started:=prior.detection_started_at;secs:=greatest(0,floor(extract(epoch from(p_observed_at-started)))::int);
   if prior.source_state is distinct from st or prior.evidence_fingerprint is distinct from fp then et:='detected';started:=p_observed_at;secs:=0;
   elsif secs>=p_persistence_threshold_seconds then et:='opened';end if;
  elsif prior.event_type in('opened','changed') then started:=prior.detection_started_at;secs:=greatest(0,floor(extract(epoch from(p_observed_at-started)))::int);
   if prior.source_state is distinct from st or prior.evidence_fingerprint is distinct from fp then et:='changed';end if;end if;
 else sev:='info';if prior.event_id is not null and prior.event_type in('detected','opened','changed') then et:='recovered';started:=prior.detection_started_at;
 secs:=greatest(0,floor(extract(epoch from(p_observed_at-started)))::int);end if;end if;
 if et is not null then eid:=gen_random_uuid();insert into foundation.case_audit_layer195_coverage_incident_events(event_id,incident_key,environment,event_type,source_state,severity,
 reason_code,evidence_fingerprint,detection_started_at,persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at,evidence_ref)
 values(eid,k,p_environment,et,st,sev,reason,fp,coalesce(started,p_observed_at),p_persistence_threshold_seconds,secs,p_snapshot,p_observed_at,'foundation-layer195-coverage-incident:'||eid);end if;
 return jsonb_build_object('foundationCaseAuditLayer195CoverageIncidentTransition','shine-foundation/case-audit-layer195-reconciliation-coverage-incident-transition-v1',
 'schemaVersion','1.0.0','environment',p_environment,'sourceState',st,'severity',sev,'eventType',et,'eventId',eid,'eventCreated',et is not null,
 'semanticEvidenceFingerprint',fp,'persistenceSeconds',secs,'automaticRepair',false,'mutatesAuthoritativeTruth',false);
end $$;
revoke execute on function foundation.get_case_audit_layer195_coverage_semantic_fingerprint_v1(jsonb) from public,anon,authenticated;
grant execute on function foundation.get_case_audit_layer195_coverage_semantic_fingerprint_v1(jsonb) to service_role;
revoke execute on function foundation.transition_case_audit_layer195_coverage_incident_v1(text,jsonb,timestamptz,int) from public,anon,authenticated;
grant execute on function foundation.transition_case_audit_layer195_coverage_incident_v1(text,jsonb,timestamptz,int) to service_role;
