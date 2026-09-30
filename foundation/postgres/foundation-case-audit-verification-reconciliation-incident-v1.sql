-- Foundation Layer 84: incident lifecycle for Layer-83 reconciliation coverage.
-- Layer 83 is read-only coverage truth. Layer 84 turns persistent GAP/INVALID
-- coverage into append-only operational evidence without reconciling, verifying,
-- repairing, rewriting, or mutating any Layer-81/82 truth.

create or replace function foundation.case_audit_verify_reconcile_incident_fingerprint_v1(
  p_snapshot jsonb
)
returns text
language sql
immutable
security definer
set search_path = ''
as $layer84_fingerprint$
  select encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'state',p_snapshot->>'state',
          'reasonCode',p_snapshot->>'reasonCode',
          'successfulExecutorCount',p_snapshot->'successfulExecutorCount',
          'reconciliationRequiredCount',p_snapshot->'reconciliationRequiredCount',
          'reconciliationReceiptCount',p_snapshot->'reconciliationReceiptCount',
          'reconciledCount',p_snapshot->'reconciledCount',
          'pendingCount',p_snapshot->'pendingCount',
          'overdueCount',p_snapshot->'overdueCount',
          'invalidReconciliationCount',p_snapshot->'invalidReconciliationCount',
          'missingProofCount',p_snapshot->'missingProofCount',
          'receiptMismatchCount',p_snapshot->'receiptMismatchCount',
          'invalidProofCount',p_snapshot->'invalidProofCount',
          'evidenceDriftCount',p_snapshot->'evidenceDriftCount',
          'coverageDriftCount',p_snapshot->'coverageDriftCount',
          'problemCount',p_snapshot->'problemCount',
          'reconciliationCoveragePercent',p_snapshot->'reconciliationCoveragePercent',
          'healthyReconciliationPercent',p_snapshot->'healthyReconciliationPercent',
          'items',coalesce(
            (
              select jsonb_agg(
                jsonb_build_object(
                  'executorEventId',i.value->>'executorEventId',
                  'targetExecutionEventId',i.value->>'targetExecutionEventId',
                  'coverageState',i.value->>'coverageState',
                  'reasonCode',i.value->>'reasonCode',
                  'reconciliationId',i.value->>'reconciliationId',
                  'reconciliationState',i.value->>'reconciliationState',
                  'verificationId',i.value->>'verificationId',
                  'verificationState',i.value->>'verificationState',
                  'reconciliationProofIntegrityValid',
                    i.value->'reconciliationProofIntegrityValid'
                )
                order by i.value->>'executorEventId'
              )
              from jsonb_array_elements(
                coalesce(p_snapshot->'items','[]'::jsonb)
              ) i(value)
            ),
            '[]'::jsonb
          )
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$layer84_fingerprint$;

revoke all on function foundation.case_audit_verify_reconcile_incident_fingerprint_v1(jsonb)
  from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime,service_role;


create table foundation.case_audit_verify_reconcile_incident_events (
  event_sequence bigint generated always as identity primary key,
  event_id uuid not null unique default gen_random_uuid(),
  incident_key text not null
    check (incident_key ~ '^[a-z0-9][a-z0-9._:-]*$'),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  domain text not null
    check (domain='case_audit_verification_reconciliation_coverage'),
  event_type text not null
    check (event_type in ('detected','opened','changed','recovered')),
  source_state text not null
    check (source_state in ('idle','normal','pending','gap','invalid')),
  severity text not null
    check (severity in ('info','critical')),
  reason_code text not null
    check (char_length(reason_code) between 1 and 160),
  evidence_fingerprint text not null
    check (evidence_fingerprint ~ '^[a-f0-9]{64}$'),
  detection_started_at timestamptz not null,
  persistence_threshold_seconds integer not null
    check (persistence_threshold_seconds between 60 and 3600),
  persistence_seconds integer not null
    check (persistence_seconds>=0),
  snapshot jsonb not null
    check (jsonb_typeof(snapshot)='object'),
  occurred_at timestamptz not null,
  evidence_ref text not null unique,
  recorded_at timestamptz not null default now(),
  check (
    (
      event_type in ('detected','opened','changed')
      and source_state in ('gap','invalid')
      and severity='critical'
    )
    or
    (
      event_type='recovered'
      and source_state in ('idle','normal','pending')
      and severity='info'
    )
  )
);

alter table foundation.case_audit_verify_reconcile_incident_events
  enable row level security;

create policy foundation_runtime_case_audit_verify_reconcile_incident_select
on foundation.case_audit_verify_reconcile_incident_events
for select
to foundation_runtime
using (true);

revoke all on foundation.case_audit_verify_reconcile_incident_events
  from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime,service_role;
grant select on foundation.case_audit_verify_reconcile_incident_events
  to foundation_runtime,service_role;

create index case_audit_verify_reconcile_incident_key_time_idx
  on foundation.case_audit_verify_reconcile_incident_events(
    incident_key,occurred_at desc,event_sequence desc
  );

create trigger case_audit_verify_reconcile_incident_append_only
before update or delete
on foundation.case_audit_verify_reconcile_incident_events
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_case_audit_verify_reconcile_incident_state
with (security_invoker=true)
as
select distinct on (incident_key)
  event_sequence,
  event_id,
  incident_key,
  environment,
  domain,
  event_type,
  source_state,
  severity,
  reason_code,
  evidence_fingerprint,
  detection_started_at,
  persistence_threshold_seconds,
  persistence_seconds,
  snapshot,
  occurred_at,
  evidence_ref,
  recorded_at
from foundation.case_audit_verify_reconcile_incident_events
order by incident_key,occurred_at desc,event_sequence desc;

revoke all on foundation.current_case_audit_verify_reconcile_incident_state
  from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant select on foundation.current_case_audit_verify_reconcile_incident_state
  to foundation_runtime,service_role;


create view foundation.current_case_audit_verify_reconcile_incidents
with (security_invoker=true)
as
select *
from foundation.current_case_audit_verify_reconcile_incident_state
where event_type in ('opened','changed');

revoke all on foundation.current_case_audit_verify_reconcile_incidents
  from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant select on foundation.current_case_audit_verify_reconcile_incidents
  to foundation_runtime,service_role;


create view foundation.current_case_audit_verify_watches
with (security_invoker=true)
as
select *
from foundation.current_case_audit_verify_reconcile_incident_state
where event_type='detected';

revoke all on foundation.current_case_audit_verify_watches
  from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant select on foundation.current_case_audit_verify_watches
  to foundation_runtime,service_role;


create or replace function foundation.transition_case_audit_verify_reconcile_incident_v1(
  p_environment text,
  p_snapshot jsonb,
  p_observed_at timestamptz,
  p_persistence_threshold_seconds integer default 300
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer84_transition$
declare
  v_incident_key text;
  v_state text;
  v_reason text;
  v_severity text;
  v_fingerprint text;
  v_prior foundation.case_audit_verify_reconcile_incident_events%rowtype;
  v_event_type text;
  v_detection_started_at timestamptz;
  v_persistence_seconds integer := 0;
  v_event_id uuid;
  v_active_count integer := 0;
  v_watch_count integer := 0;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_observed_at is null
     or p_persistence_threshold_seconds<60
     or p_persistence_threshold_seconds>3600 then
    raise exception 'case-audit-verify-reconcile-incident-input-invalid';
  end if;

  if p_snapshot is null
     or jsonb_typeof(p_snapshot)<>'object'
     or p_snapshot->>'foundationCaseAuditVerificationReconciliationCoverage'
          is distinct from
          'shine-foundation/case-audit-verification-reconciliation-coverage-v1'
     or p_snapshot->>'schemaVersion' is distinct from '1.0.0'
     or p_snapshot->>'environment' is distinct from p_environment then
    raise exception 'case-audit-verify-reconcile-incident-snapshot-invalid';
  end if;

  v_state := coalesce(p_snapshot->>'state','invalid');
  v_reason := coalesce(
    nullif(p_snapshot->>'reasonCode',''),
    'case-audit-safe-response-verification-state-invalid'
  );

  if v_state not in ('idle','normal','pending','gap','invalid') then
    raise exception 'case-audit-verify-reconcile-incident-state-invalid';
  end if;

  v_fingerprint :=
    foundation.case_audit_verify_reconcile_incident_fingerprint_v1(p_snapshot);

  v_incident_key := p_environment||':case_audit_verification_reconciliation_coverage';

  select * into v_prior
  from foundation.case_audit_verify_reconcile_incident_events
  where incident_key=v_incident_key
  order by occurred_at desc,event_sequence desc
  limit 1;

  v_event_type := null;

  if v_state in ('gap','invalid') then
    v_severity := 'critical';

    if v_prior.event_id is null or v_prior.event_type='recovered' then
      v_event_type := 'detected';
      v_detection_started_at := p_observed_at;
      v_persistence_seconds := 0;

    elsif v_prior.event_type='detected' then
      if v_prior.source_state is distinct from v_state
         or v_prior.evidence_fingerprint is distinct from v_fingerprint then
        v_event_type := 'detected';
        v_detection_started_at := p_observed_at;
        v_persistence_seconds := 0;
      else
        v_detection_started_at := v_prior.detection_started_at;
        v_persistence_seconds := greatest(
          0,
          floor(extract(epoch from (
            p_observed_at-v_detection_started_at
          )))::integer
        );

        if v_persistence_seconds>=p_persistence_threshold_seconds then
          v_event_type := 'opened';
        end if;
      end if;

    elsif v_prior.event_type in ('opened','changed') then
      v_detection_started_at := v_prior.detection_started_at;
      v_persistence_seconds := greatest(
        0,
        floor(extract(epoch from (
          p_observed_at-v_detection_started_at
        )))::integer
      );

      if v_prior.source_state is distinct from v_state
         or v_prior.evidence_fingerprint is distinct from v_fingerprint then
        v_event_type := 'changed';
      end if;
    end if;

  else
    v_severity := 'info';

    if v_prior.event_id is not null
       and v_prior.event_type in ('detected','opened','changed') then
      v_event_type := 'recovered';
      v_detection_started_at := v_prior.detection_started_at;
      v_persistence_seconds := greatest(
        0,
        floor(extract(epoch from (
          p_observed_at-v_detection_started_at
        )))::integer
      );
    end if;
  end if;

  if v_event_type is not null then
    v_event_id := gen_random_uuid();

    insert into foundation.case_audit_verify_reconcile_incident_events(
      event_id,
      incident_key,
      environment,
      domain,
      event_type,
      source_state,
      severity,
      reason_code,
      evidence_fingerprint,
      detection_started_at,
      persistence_threshold_seconds,
      persistence_seconds,
      snapshot,
      occurred_at,
      evidence_ref
    )
    values(
      v_event_id,
      v_incident_key,
      p_environment,
      'case_audit_verification_reconciliation_coverage',
      v_event_type,
      v_state,
      v_severity,
      v_reason,
      v_fingerprint,
      v_detection_started_at,
      p_persistence_threshold_seconds,
      v_persistence_seconds,
      p_snapshot,
      p_observed_at,
      'foundation-case-audit-verify-reconcile-incident:'||v_event_id::text
    );
  end if;

  select count(*) into v_active_count
  from foundation.current_case_audit_verify_reconcile_incidents
  where environment=p_environment;

  select count(*) into v_watch_count
  from foundation.current_case_audit_verify_watches
  where environment=p_environment;

  return jsonb_build_object(
    'foundationCaseAuditVerificationReconciliationIncidentTransition',
      'shine-foundation/case-audit-verification-reconciliation-incident-transition-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'incidentKey',v_incident_key,
    'sourceState',v_state,
    'severity',v_severity,
    'reasonCode',v_reason,
    'eventType',v_event_type,
    'eventId',v_event_id,
    'eventCreated',v_event_type is not null,
    'evidenceFingerprint',v_fingerprint,
    'persistenceThresholdSeconds',p_persistence_threshold_seconds,
    'persistenceSeconds',case
      when v_detection_started_at is null then 0
      else greatest(
        v_persistence_seconds,
        floor(extract(epoch from (
          p_observed_at-v_detection_started_at
        )))::integer
      )
    end,
    'activeIncidentCount',v_active_count,
    'watchCount',v_watch_count,
    'automaticReconciliation',false,
    'automaticRepair',false,
    'layer81RerunPerformed',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false
  );
end;
$layer84_transition$;

revoke all on function foundation.transition_case_audit_verify_reconcile_incident_v1(
  text,jsonb,timestamptz,integer
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime,service_role;


create or replace function foundation.run_case_audit_verify_reconcile_incident_sentinel_v1(
  p_environment text default 'production',
  p_observed_at timestamptz default now(),
  p_persistence_threshold_seconds integer default 300,
  p_reconciliation_grace_seconds integer default 300
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer84_sentinel$
declare
  v_snapshot jsonb;
  v_transition jsonb;
begin
  if p_observed_at is null
     or p_observed_at<now()-interval '5 minutes'
     or p_observed_at>now()+interval '5 minutes' then
    raise exception 'case-audit-verify-reconcile-sentinel-time-invalid';
  end if;

  v_snapshot :=
    foundation.get_case_audit_verify_reconcile_coverage_v1(
      p_environment,
      p_observed_at,
      p_reconciliation_grace_seconds,
      100
    );

  v_transition :=
    foundation.transition_case_audit_verify_reconcile_incident_v1(
      p_environment,
      v_snapshot,
      p_observed_at,
      p_persistence_threshold_seconds
    );

  return jsonb_build_object(
    'foundationCaseAuditVerificationReconciliationIncidentSentinel',
      'shine-foundation/case-audit-verification-reconciliation-incident-sentinel-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'observedAt',p_observed_at,
    'coverageState',v_snapshot->>'state',
    'coverageReasonCode',v_snapshot->>'reasonCode',
    'problemCount',v_snapshot->'problemCount',
    'reconciliationCoveragePercent',
      v_snapshot->'reconciliationCoveragePercent',
    'healthyReconciliationPercent',
      v_snapshot->'healthyReconciliationPercent',
    'incidentTransition',v_transition,
    'automaticReconciliation',false,
    'automaticRepair',false,
    'layer81RerunPerformed',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false
  );
end;
$layer84_sentinel$;

revoke all on function foundation.run_case_audit_verify_reconcile_incident_sentinel_v1(
  text,timestamptz,integer,integer
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.run_case_audit_verify_reconcile_incident_sentinel_v1(
  text,timestamptz,integer,integer
) to service_role;


create or replace function foundation.get_case_audit_verify_reconcile_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer84_summary$
declare
  v_coverage jsonb;
  v_current foundation.case_audit_verify_reconcile_incident_events%rowtype;
  v_active_count integer := 0;
  v_watch_count integer := 0;
  v_state text := 'normal';
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_as_of is null then
    raise exception 'case-audit-verify-reconcile-incident-summary-input-invalid';
  end if;

  v_coverage :=
    foundation.get_case_audit_verify_reconcile_coverage_v1(
      p_environment,p_as_of,p_reconciliation_grace_seconds,100
    );

  select * into v_current
  from foundation.current_case_audit_verify_reconcile_incident_state
  where incident_key=p_environment||':case_audit_verification_reconciliation_coverage';

  select count(*) into v_active_count
  from foundation.current_case_audit_verify_reconcile_incidents
  where environment=p_environment;

  select count(*) into v_watch_count
  from foundation.current_case_audit_verify_watches
  where environment=p_environment;

  v_state := case
    when v_active_count>0 then 'critical'
    when v_watch_count>0 then 'watching'
    else 'normal'
  end;

  return jsonb_build_object(
    'foundationCaseAuditVerificationReconciliationIncidentSummary',
      'shine-foundation/case-audit-verification-reconciliation-incident-summary-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state',v_state,
    'activeIncidentCount',v_active_count,
    'watchCount',v_watch_count,
    'coverageState',v_coverage->>'state',
    'coverageReasonCode',v_coverage->>'reasonCode',
    'successfulExecutorCount',v_coverage->'successfulExecutorCount',
    'reconciliationReceiptCount',v_coverage->'reconciliationReceiptCount',
    'problemCount',v_coverage->'problemCount',
    'reconciliationCoveragePercent',
      v_coverage->'reconciliationCoveragePercent',
    'healthyReconciliationPercent',
      v_coverage->'healthyReconciliationPercent',
    'currentEvent',case
      when v_current.event_id is null then null
      else jsonb_build_object(
        'eventId',v_current.event_id,
        'incidentKey',v_current.incident_key,
        'eventType',v_current.event_type,
        'sourceState',v_current.source_state,
        'severity',v_current.severity,
        'reasonCode',v_current.reason_code,
        'evidenceFingerprint',v_current.evidence_fingerprint,
        'detectionStartedAt',v_current.detection_started_at,
        'persistenceThresholdSeconds',
          v_current.persistence_threshold_seconds,
        'persistenceSeconds',v_current.persistence_seconds,
        'occurredAt',v_current.occurred_at,
        'evidenceRef',v_current.evidence_ref
      )
    end,
    'recommendedAction',case v_state
      when 'critical' then 'investigate-reconciliation-coverage-failure'
      when 'watching' then 'observe-until-persistence-threshold-or-recovery'
      else 'none'
    end,
    'automaticReconciliation',false,
    'automaticRepair',false,
    'layer81RerunPerformed',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false
  );
end;
$layer84_summary$;

revoke all on function foundation.get_case_audit_verify_reconcile_incident_summary_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_case_audit_verify_reconcile_incident_summary_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;
