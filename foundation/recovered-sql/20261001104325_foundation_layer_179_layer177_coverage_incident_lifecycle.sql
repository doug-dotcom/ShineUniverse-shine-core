
create table foundation.case_audit_layer177_coverage_incident_events (
 event_sequence bigint generated always as identity primary key,
 event_id uuid not null default gen_random_uuid() unique,
 incident_key text not null,
 environment text not null,
 event_type text not null check (event_type in ('detected','opened','changed','recovered')),
 source_state text not null check (source_state in ('idle','normal','pending','gap','invalid')),
 severity text not null check (severity in ('info','critical')),
 reason_code text not null,
 evidence_fingerprint text not null check (evidence_fingerprint ~ '^[0-9a-f]{64}$'),
 detection_started_at timestamptz not null,
 persistence_threshold_seconds integer not null check (persistence_threshold_seconds between 60 and 3600),
 persistence_seconds integer not null check (persistence_seconds >= 0),
 snapshot jsonb not null,
 occurred_at timestamptz not null,
 evidence_ref text not null,
 recorded_at timestamptz not null default now()
);
alter table foundation.case_audit_layer177_coverage_incident_events enable row level security;
revoke all on foundation.case_audit_layer177_coverage_incident_events from public, anon, authenticated;
grant select,insert on foundation.case_audit_layer177_coverage_incident_events to service_role;
create index case_audit_layer177_incident_key_time_idx on foundation.case_audit_layer177_coverage_incident_events(incident_key,occurred_at desc,event_sequence desc);

create or replace function foundation.get_case_audit_layer177_coverage_semantic_fingerprint_v1(p_coverage jsonb)
returns text language plpgsql immutable security definer set search_path=''
as $$
declare v_semantic jsonb;
begin
 if p_coverage is null or jsonb_typeof(p_coverage)<>'object'
 or p_coverage->>'foundationCaseAuditLayer177ReconciliationCoverage'
    is distinct from 'shine-foundation/case-audit-layer177-reconciliation-coverage-v1'
 or p_coverage->>'schemaVersion' is distinct from '1.0.0' then
   raise exception 'case-audit-layer177-semantic-fingerprint-input-invalid';
 end if;
 v_semantic:=jsonb_build_object(
  'state',p_coverage->>'state',
  'successfulLayer176ExecutionCount',coalesce((p_coverage->>'successfulLayer176ExecutionCount')::int,0),
  'layer177ReconciliationRequiredCount',coalesce((p_coverage->>'layer177ReconciliationRequiredCount')::int,0),
  'layer177ReconciliationReceiptCount',coalesce((p_coverage->>'layer177ReconciliationReceiptCount')::int,0),
  'reconciledCount',coalesce((p_coverage->>'reconciledCount')::int,0),
  'pendingCount',coalesce((p_coverage->>'pendingCount')::int,0),
  'overdueCount',coalesce((p_coverage->>'overdueCount')::int,0),
  'invalidLayer177ReconciliationCount',coalesce((p_coverage->>'invalidLayer177ReconciliationCount')::int,0),
  'missingLayer172ReceiptCount',coalesce((p_coverage->>'missingLayer172ReceiptCount')::int,0),
  'executionReceiptMismatchCount',coalesce((p_coverage->>'executionReceiptMismatchCount')::int,0),
  'admissionValidationDriftCount',coalesce((p_coverage->>'admissionValidationDriftCount')::int,0),
  'policyDriftCount',coalesce((p_coverage->>'policyDriftCount')::int,0),
  'incidentIntegrityDriftCount',coalesce((p_coverage->>'incidentIntegrityDriftCount')::int,0),
  'incidentStateDriftCount',coalesce((p_coverage->>'incidentStateDriftCount')::int,0),
  'incidentBindingDriftCount',coalesce((p_coverage->>'incidentBindingDriftCount')::int,0),
  'semanticCurrentnessDriftCount',coalesce((p_coverage->>'semanticCurrentnessDriftCount')::int,0),
  'problemCount',coalesce((p_coverage->>'problemCount')::int,0)
 );
 return encode(extensions.digest(convert_to(v_semantic::text,'UTF8'),'sha256'),'hex');
end $$;

create or replace function foundation.transition_case_audit_layer177_coverage_incident_v1(
 p_environment text,p_snapshot jsonb,p_observed_at timestamptz,p_persistence_threshold_seconds integer default 300
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare
 v_key text; v_state text; v_reason text; v_fingerprint text;
 v_prior foundation.case_audit_layer177_coverage_incident_events%rowtype;
 v_event_type text; v_started_at timestamptz; v_persistence_seconds integer:=0;
 v_event_id uuid; v_severity text;
begin
 if p_environment is null or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
 or p_observed_at is null or p_persistence_threshold_seconds not between 60 and 3600 then
  raise exception 'case-audit-layer177-incident-input-invalid';
 end if;
 if p_snapshot is null or jsonb_typeof(p_snapshot)<>'object'
 or p_snapshot->>'foundationCaseAuditLayer177ReconciliationCoverage'
    is distinct from 'shine-foundation/case-audit-layer177-reconciliation-coverage-v1'
 or p_snapshot->>'schemaVersion' is distinct from '1.0.0'
 or p_snapshot->>'environment' is distinct from p_environment then
  raise exception 'case-audit-layer177-incident-snapshot-invalid';
 end if;
 v_state:=coalesce(p_snapshot->>'state','invalid');
 if v_state not in('idle','normal','pending','gap','invalid') then raise exception 'case-audit-layer177-incident-state-invalid'; end if;
 v_reason:=case when v_state='invalid' then 'case-audit-layer177-receipt-invalid'
                when v_state='gap' then 'case-audit-layer177-coverage-gap'
                when v_state='pending' then 'case-audit-layer177-within-grace'
                when v_state='idle' then 'case-audit-layer177-no-executions'
                else 'case-audit-layer177-covered' end;
 v_fingerprint:=foundation.get_case_audit_layer177_coverage_semantic_fingerprint_v1(p_snapshot);
 v_key:=p_environment||':case_audit_layer177_reconciliation_coverage';
 select x.* into v_prior from foundation.case_audit_layer177_coverage_incident_events x
 where x.incident_key=v_key order by x.occurred_at desc,x.event_sequence desc limit 1;

 if v_state in('gap','invalid') then
  v_severity:='critical';
  if v_prior.event_id is null or v_prior.event_type='recovered' then v_event_type:='detected'; v_started_at:=p_observed_at;
  elsif v_prior.event_type='detected' then
   if v_prior.source_state is distinct from v_state or v_prior.evidence_fingerprint is distinct from v_fingerprint then
    v_event_type:='detected'; v_started_at:=p_observed_at;
   else
    v_started_at:=v_prior.detection_started_at;
    v_persistence_seconds:=greatest(0,floor(extract(epoch from(p_observed_at-v_started_at)))::int);
    if v_persistence_seconds>=p_persistence_threshold_seconds then v_event_type:='opened'; end if;
   end if;
  elsif v_prior.event_type in('opened','changed') then
   v_started_at:=v_prior.detection_started_at;
   v_persistence_seconds:=greatest(0,floor(extract(epoch from(p_observed_at-v_started_at)))::int);
   if v_prior.source_state is distinct from v_state or v_prior.evidence_fingerprint is distinct from v_fingerprint then v_event_type:='changed'; end if;
  end if;
 else
  v_severity:='info';
  if v_prior.event_id is not null and v_prior.event_type in('detected','opened','changed') then
   v_event_type:='recovered'; v_started_at:=v_prior.detection_started_at;
   v_persistence_seconds:=greatest(0,floor(extract(epoch from(p_observed_at-v_started_at)))::int);
  end if;
 end if;

 if v_event_type is not null then
  v_event_id:=gen_random_uuid();
  insert into foundation.case_audit_layer177_coverage_incident_events(
   event_id,incident_key,environment,event_type,source_state,severity,reason_code,evidence_fingerprint,
   detection_started_at,persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at,evidence_ref)
  values(v_event_id,v_key,p_environment,v_event_type,v_state,v_severity,v_reason,v_fingerprint,
   coalesce(v_started_at,p_observed_at),p_persistence_threshold_seconds,v_persistence_seconds,p_snapshot,p_observed_at,
   'foundation-layer177-coverage-incident:'||v_event_id);
 end if;
 return jsonb_build_object(
  'foundationCaseAuditLayer177CoverageIncidentTransition','shine-foundation/case-audit-layer177-reconciliation-coverage-incident-transition-v1',
  'schemaVersion','1.0.0','environment',p_environment,'sourceState',v_state,'severity',v_severity,
  'eventType',v_event_type,'eventId',v_event_id,'eventCreated',v_event_type is not null,
  'semanticEvidenceFingerprint',v_fingerprint,'persistenceThresholdSeconds',p_persistence_threshold_seconds,
  'persistenceSeconds',v_persistence_seconds,'automaticRepair',false,'mutatesAuthoritativeTruth',false);
end $$;

revoke execute on function foundation.get_case_audit_layer177_coverage_semantic_fingerprint_v1(jsonb) from public,anon,authenticated;
grant execute on function foundation.get_case_audit_layer177_coverage_semantic_fingerprint_v1(jsonb) to service_role;
revoke execute on function foundation.transition_case_audit_layer177_coverage_incident_v1(text,jsonb,timestamptz,integer) from public,anon,authenticated;
grant execute on function foundation.transition_case_audit_layer177_coverage_incident_v1(text,jsonb,timestamptz,integer) to service_role;
