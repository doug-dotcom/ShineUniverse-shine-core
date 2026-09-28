-- Foundation Layer 42: post-remediation verification and controlled closure.
-- A successful Layer-41 mutation is not proof that remediation succeeded.

do $roles$
begin
  if not exists (select 1 from pg_roles where rolname='foundation_remediation_verifier') then
    create role foundation_remediation_verifier nologin noinherit;
  end if;
end;
$roles$;
alter role foundation_remediation_verifier nologin noinherit;
grant foundation_remediation_verifier to postgres;
grant usage on schema foundation to foundation_remediation_verifier;

create table foundation.remediation_verification_events (
  event_sequence bigint generated always as identity primary key,
  event_id uuid not null unique,
  verification_id uuid not null unique,
  execution_event_id uuid not null references foundation.remediation_execution_events(event_id),
  execution_id uuid not null references foundation.remediation_execution_events(execution_id),
  admission_id uuid not null references foundation.remediation_execution_admissions(admission_id),
  approval_receipt_id uuid not null references foundation.remediation_approval_receipts(receipt_id),
  incident_event_id uuid not null references foundation.foundation_control_plane_incident_events(event_id),
  incident_key text not null,
  action_key text not null references foundation.remediation_execution_operations(action_key),
  event_type text not null check (event_type in ('verified','unresolved','denied')),
  reason_code text not null,
  projection_observation_id uuid references foundation.foundation_release_projection_observations(observation_id),
  projection_state text check (projection_state is null or projection_state in ('aligned','degraded','unknown','fail')),
  projection_evidence_fingerprint text check (projection_evidence_fingerprint is null or projection_evidence_fingerprint ~ '^[a-f0-9]{32}$'),
  closure_transition_event_id uuid references foundation.foundation_control_plane_incident_events(event_id),
  verification jsonb not null check (jsonb_typeof(verification)='object'),
  verification_sha256 text not null check (verification_sha256 ~ '^[a-f0-9]{64}$'),
  occurred_at timestamptz not null,
  recorded_at timestamptz not null default now()
);

alter table foundation.remediation_verification_events enable row level security;
create policy foundation_runtime_remediation_verification_events_select
on foundation.remediation_verification_events for select to foundation_runtime using (true);
revoke all on foundation.remediation_verification_events
  from public,anon,authenticated,foundation_gateway,foundation_remediation_approver,
       foundation_remediation_executor,foundation_remediation_mutator,
       foundation_remediation_verifier,service_role;
grant select on foundation.remediation_verification_events to foundation_runtime,service_role;

create index remediation_verification_execution_idx on foundation.remediation_verification_events(execution_event_id);
create index remediation_verification_incident_idx on foundation.remediation_verification_events(incident_event_id);
create index remediation_verification_admission_idx on foundation.remediation_verification_events(admission_id);
create index remediation_verification_approval_idx on foundation.remediation_verification_events(approval_receipt_id);
create index remediation_verification_projection_idx on foundation.remediation_verification_events(projection_observation_id);
create index remediation_verification_closure_idx on foundation.remediation_verification_events(closure_transition_event_id);

create trigger remediation_verification_events_append_only
before update or delete on foundation.remediation_verification_events
for each row execute function foundation.reject_append_only_mutation();

create or replace function foundation.verify_scoped_remediation_v1(
  p_event_id uuid,p_verification_id uuid,p_execution_event_id uuid,p_observed_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $verify$
declare
  x foundation.remediation_execution_events%rowtype;
  i foundation.foundation_control_plane_incident_events%rowtype;
  c foundation.foundation_control_plane_incident_events%rowtype;
  o jsonb;
  s jsonb;
  t jsonb;
  oid uuid;
  tid uuid;
  st text;
  fp text;
  et text;
  rc text;
  v jsonb;
  h text;
begin
  if p_event_id is null or p_verification_id is null or p_execution_event_id is null or p_observed_at is null then
    raise exception 'remediation-verification-required-fields-missing';
  end if;
  if p_observed_at<now()-interval '5 minutes' or p_observed_at>now()+interval '5 minutes' then
    raise exception 'remediation-verification-observed-at-invalid';
  end if;

  select * into x from foundation.remediation_execution_events where event_id=p_execution_event_id;
  if x.event_id is null then
    return jsonb_build_object('verified',false,'incidentClosurePermitted',false,'reasonCode','remediation-execution-event-not-found');
  end if;

  if exists(select 1 from foundation.remediation_verification_events where execution_event_id=x.event_id and event_type in ('verified','unresolved')) then
    return jsonb_build_object('verified',false,'incidentClosurePermitted',false,'reasonCode','remediation-execution-already-verified');
  end if;

  select * into i from foundation.foundation_control_plane_incident_events where event_id=x.incident_event_id;
  if i.event_id is null then raise exception 'remediation-verification-incident-missing'; end if;

  select * into c from foundation.current_foundation_control_plane_incident_state where incident_key=i.incident_key;

  if x.event_type<>'executed' then
    et:='denied'; rc:='remediation-execution-not-successful';
  elsif c.event_type in ('opened','changed') and c.event_id is distinct from x.incident_event_id then
    et:='denied'; rc:='remediation-verification-incident-changed-after-execution';
  else
    o:=foundation.record_foundation_release_projection_observation_v1(i.environment,p_observed_at);
    oid:=(o->>'observationId')::uuid;
    s:=o->'snapshot';
    st:=s->>'state';
    fp:=lower(coalesce(s->>'evidenceFingerprint',''));

    if st in ('aligned','degraded') then
      t:=foundation.transition_foundation_control_plane_incident_v1(
        i.environment,s,oid,p_observed_at,i.persistence_threshold_seconds
      );
      if t->>'eventType' is distinct from 'recovered' and c.event_type<>'recovered' then
        raise exception 'remediation-verification-recovery-transition-missing';
      end if;
      if t->>'eventId' is not null then tid:=(t->>'eventId')::uuid;
      elsif c.event_type='recovered' then tid:=c.event_id;
      end if;
      et:='verified'; rc:='remediation-invariant-restored';
    else
      et:='unresolved'; rc:='remediation-invariant-not-restored';
    end if;
  end if;

  v:=jsonb_build_object(
    'remediationVerification','shine-foundation/remediation-verification-v1',
    'schemaVersion','1.0.0','verificationId',p_verification_id,
    'executionEventId',x.event_id,'executionId',x.execution_id,
    'admissionId',x.admission_id,'approvalReceiptId',x.approval_receipt_id,
    'incidentEventId',x.incident_event_id,'actionKey',x.action_key,
    'verificationState',et,'reasonCode',rc,
    'projectionObservationId',oid,'projectionState',st,
    'projectionEvidenceFingerprint',fp,'closureTransitionEventId',tid,
    'incidentClosurePermitted',et='verified','observedAt',p_observed_at
  );
  h:=encode(extensions.digest(convert_to(v::text,'UTF8'),'sha256'),'hex');

  insert into foundation.remediation_verification_events(
    event_id,verification_id,execution_event_id,execution_id,admission_id,
    approval_receipt_id,incident_event_id,incident_key,action_key,event_type,
    reason_code,projection_observation_id,projection_state,
    projection_evidence_fingerprint,closure_transition_event_id,
    verification,verification_sha256,occurred_at
  ) values (
    p_event_id,p_verification_id,x.event_id,x.execution_id,x.admission_id,
    x.approval_receipt_id,x.incident_event_id,i.incident_key,x.action_key,et,
    rc,oid,st,fp,tid,v,h,p_observed_at
  );

  return jsonb_build_object(
    'foundationRemediationVerificationResponse','shine-foundation/remediation-verification-response-v1',
    'schemaVersion','1.0.0','verified',et='verified',
    'incidentClosurePermitted',et='verified','verificationId',p_verification_id,
    'executionEventId',x.event_id,'eventType',et,'reasonCode',rc,
    'projectionObservationId',oid,'projectionState',st,
    'closureTransitionEventId',tid,'verificationSha256',h
  );
end;
$verify$;

revoke all on function foundation.verify_scoped_remediation_v1(uuid,uuid,uuid,timestamptz)
  from public,anon,authenticated,foundation_runtime,foundation_gateway,
       foundation_remediation_approver,foundation_remediation_executor,
       foundation_remediation_mutator,service_role;
grant execute on function foundation.verify_scoped_remediation_v1(uuid,uuid,uuid,timestamptz)
  to foundation_remediation_verifier;

create or replace function foundation.get_remediation_verification_control_health_v1()
returns jsonb language plpgsql stable security definer set search_path='' as $health$
declare
  e boolean; sm boolean; am boolean; em boolean; mm boolean;
  sc boolean; ac boolean; ec boolean; mc boolean; vc boolean; di boolean;
  state text:='pass';
begin
  select exists(select 1 from pg_roles where rolname='foundation_remediation_verifier' and not rolcanlogin) into e;
  sm:=pg_has_role('service_role','foundation_remediation_verifier','MEMBER');
  am:=pg_has_role('foundation_remediation_approver','foundation_remediation_verifier','MEMBER');
  em:=pg_has_role('foundation_remediation_executor','foundation_remediation_verifier','MEMBER');
  mm:=pg_has_role('foundation_remediation_mutator','foundation_remediation_verifier','MEMBER');
  sc:=has_function_privilege('service_role','foundation.verify_scoped_remediation_v1(uuid,uuid,uuid,timestamptz)','EXECUTE');
  ac:=has_function_privilege('foundation_remediation_approver','foundation.verify_scoped_remediation_v1(uuid,uuid,uuid,timestamptz)','EXECUTE');
  ec:=has_function_privilege('foundation_remediation_executor','foundation.verify_scoped_remediation_v1(uuid,uuid,uuid,timestamptz)','EXECUTE');
  mc:=has_function_privilege('foundation_remediation_mutator','foundation.verify_scoped_remediation_v1(uuid,uuid,uuid,timestamptz)','EXECUTE');
  vc:=has_function_privilege('foundation_remediation_verifier','foundation.verify_scoped_remediation_v1(uuid,uuid,uuid,timestamptz)','EXECUTE');
  di:=has_table_privilege('foundation_remediation_verifier','foundation.remediation_verification_events','INSERT');
  if not e or sm or am or em or mm or sc or ac or ec or mc or not vc or di then state:='fail'; end if;
  return jsonb_build_object(
    'foundationRemediationVerificationControlHealthResponse','shine-foundation/remediation-verification-control-health-response-v1',
    'schemaVersion','1.0.0','state',state,'verifierRoleExists',e,
    'serviceRoleIsVerifierMember',sm,'approverRoleIsVerifierMember',am,
    'admissionExecutorRoleIsVerifierMember',em,'mutatorRoleIsVerifierMember',mm,
    'serviceRoleCanVerify',sc,'approverRoleCanVerify',ac,
    'admissionExecutorRoleCanVerify',ec,'mutatorRoleCanVerify',mc,
    'verifierRoleCanVerify',vc,'verifierCanInsertVerificationEventsDirectly',di,
    'closureRequiresIndependentProjectionObservation',true,
    'executionSuccessAloneClosesIncident',false
  );
end;
$health$;

revoke all on function foundation.get_remediation_verification_control_health_v1()
  from public,anon,authenticated,foundation_gateway,foundation_remediation_approver,
       foundation_remediation_executor,foundation_remediation_mutator,
       foundation_remediation_verifier;
grant execute on function foundation.get_remediation_verification_control_health_v1()
  to foundation_runtime,service_role;
