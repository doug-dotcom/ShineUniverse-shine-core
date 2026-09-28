-- Foundation Layer 38: incident response policy.
-- Incidents may change response relevance, but never expand mutation authority.
-- This layer evaluates response options only; it does not execute repairs.

create table foundation.control_plane_incident_response_actions (
  action_key text primary key
    check (action_key ~ '^[a-z0-9][a-z0-9._:-]*$'),
  action_class text not null
    check (action_class in (
      'observe','evidence','proposal',
      'authoritative-mutation','history-mutation'
    )),
  mutates_authoritative_truth boolean not null default false,
  mutates_incident_history boolean not null default false,
  lifecycle text not null default 'active'
    check (lifecycle in ('active','disabled','retired')),
  description text not null,
  evidence_ref text not null,
  registered_at timestamptz not null default now(),
  check (not (mutates_authoritative_truth and mutates_incident_history)),
  check (
    (action_class='authoritative-mutation' and mutates_authoritative_truth and not mutates_incident_history)
    or
    (action_class='history-mutation' and mutates_incident_history and not mutates_authoritative_truth)
    or
    (action_class in ('observe','evidence','proposal')
      and not mutates_authoritative_truth
      and not mutates_incident_history)
  )
);

alter table foundation.control_plane_incident_response_actions enable row level security;

create policy foundation_runtime_incident_response_actions_select
on foundation.control_plane_incident_response_actions
for select
to foundation_runtime
using (true);

revoke all on foundation.control_plane_incident_response_actions
  from public,anon,authenticated,foundation_gateway;
grant select on foundation.control_plane_incident_response_actions
  to foundation_runtime,service_role;
grant insert on foundation.control_plane_incident_response_actions
  to service_role;


create table foundation.control_plane_incident_response_policies (
  response_policy_id uuid primary key default gen_random_uuid(),
  action_key text not null
    references foundation.control_plane_incident_response_actions(action_key),
  incident_state text not null
    check (incident_state in ('normal','watching','warning','critical')),
  policy_version text not null,
  decision text not null
    check (decision in ('admit','approval-required','deny','not-applicable')),
  required_control text not null
    check (required_control in (
      'read-only','evidence-only','operator-proposal',
      'external-approval','prohibited','none'
    )),
  enabled boolean not null default true,
  effective_at timestamptz not null default now(),
  evidence_ref text not null,
  evidence_note text,
  recorded_at timestamptz not null default now(),
  unique(action_key,incident_state,policy_version),
  check (
    (decision='admit' and required_control in ('read-only','evidence-only','operator-proposal'))
    or
    (decision='approval-required' and required_control='external-approval')
    or
    (decision='deny' and required_control='prohibited')
    or
    (decision='not-applicable' and required_control='none')
  )
);

alter table foundation.control_plane_incident_response_policies enable row level security;

create policy foundation_runtime_incident_response_policies_select
on foundation.control_plane_incident_response_policies
for select
to foundation_runtime
using (true);

revoke all on foundation.control_plane_incident_response_policies
  from public,anon,authenticated,foundation_gateway;
grant select on foundation.control_plane_incident_response_policies
  to foundation_runtime,service_role;
grant insert on foundation.control_plane_incident_response_policies
  to service_role;

create index control_plane_incident_response_policies_current_idx
  on foundation.control_plane_incident_response_policies(
    action_key,incident_state,effective_at desc,recorded_at desc
  );

create trigger control_plane_incident_response_policies_append_only
before update or delete on foundation.control_plane_incident_response_policies
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_control_plane_incident_response_policies
with (security_invoker=true)
as
select distinct on (action_key,incident_state)
  response_policy_id,
  action_key,
  incident_state,
  policy_version,
  decision,
  required_control,
  enabled,
  effective_at,
  evidence_ref,
  evidence_note,
  recorded_at
from foundation.control_plane_incident_response_policies
order by
  action_key,incident_state,
  effective_at desc,recorded_at desc,response_policy_id desc;

revoke all on foundation.current_control_plane_incident_response_policies
  from public,anon,authenticated,foundation_gateway;
grant select on foundation.current_control_plane_incident_response_policies
  to foundation_runtime,service_role;


insert into foundation.control_plane_incident_response_actions(
  action_key,action_class,mutates_authoritative_truth,mutates_incident_history,
  lifecycle,description,evidence_ref
)
values
  (
    'inspect-projection-evidence','observe',false,false,'active',
    'Inspect the current registry, release-ledger, binding and reconciliation evidence.',
    'foundation:layer38:action:inspect-projection-evidence'
  ),
  (
    'collect-fresh-evidence','evidence',false,false,'active',
    'Collect fresh non-mutating evidence needed to diagnose the projection state.',
    'foundation:layer38:action:collect-fresh-evidence'
  ),
  (
    'request-release-reattestation','evidence',false,false,'active',
    'Request fresh deployment/publication attestation without changing authoritative projection truth.',
    'foundation:layer38:action:request-release-reattestation'
  ),
  (
    'propose-registry-repair','proposal',false,false,'active',
    'Prepare a proposed Universe registry correction for explicit review.',
    'foundation:layer38:action:propose-registry-repair'
  ),
  (
    'propose-release-ledger-repair','proposal',false,false,'active',
    'Prepare a proposed readiness-release ledger correction for explicit review.',
    'foundation:layer38:action:propose-release-ledger-repair'
  ),
  (
    'apply-registry-repair','authoritative-mutation',true,false,'active',
    'Apply an authoritative Universe registry correction.',
    'foundation:layer38:action:apply-registry-repair'
  ),
  (
    'apply-release-ledger-repair','authoritative-mutation',true,false,'active',
    'Apply an authoritative readiness-release ledger correction.',
    'foundation:layer38:action:apply-release-ledger-repair'
  ),
  (
    'rebind-release-identity','authoritative-mutation',true,false,'active',
    'Create a new immutable release binding after independently verified deployment evidence.',
    'foundation:layer38:action:rebind-release-identity'
  ),
  (
    'auto-repair-authoritative-truth','authoritative-mutation',true,false,'active',
    'Automatically rewrite authoritative registry/release/binding truth from incident state.',
    'foundation:layer38:action:auto-repair-authoritative-truth'
  ),
  (
    'suppress-control-plane-incident','history-mutation',false,true,'active',
    'Suppress an incident lifecycle record rather than recover through evidence.',
    'foundation:layer38:action:suppress-control-plane-incident'
  ),
  (
    'delete-control-plane-incident-history','history-mutation',false,true,'active',
    'Delete append-only control-plane incident history.',
    'foundation:layer38:action:delete-control-plane-incident-history'
  )
on conflict (action_key) do nothing;


insert into foundation.control_plane_incident_response_policies(
  action_key,incident_state,policy_version,decision,required_control,
  enabled,effective_at,evidence_ref,evidence_note
)
select
  a.action_key,
  s.incident_state,
  '1.0.0',
  case
    when a.action_class='observe' then 'admit'
    when a.action_key='collect-fresh-evidence' then 'admit'
    when a.action_key='request-release-reattestation'
      and s.incident_state in ('warning','critical') then 'admit'
    when a.action_class='proposal'
      and s.incident_state in ('warning','critical') then 'admit'
    when a.action_class='authoritative-mutation'
      and a.action_key<>'auto-repair-authoritative-truth'
      and s.incident_state in ('warning','critical') then 'approval-required'
    when a.action_key='auto-repair-authoritative-truth' then 'deny'
    when a.action_class='history-mutation' then 'deny'
    when a.action_class='authoritative-mutation' then 'deny'
    else 'not-applicable'
  end as decision,
  case
    when a.action_class='observe' then 'read-only'
    when a.action_key='collect-fresh-evidence' then 'evidence-only'
    when a.action_key='request-release-reattestation'
      and s.incident_state in ('warning','critical') then 'evidence-only'
    when a.action_class='proposal'
      and s.incident_state in ('warning','critical') then 'operator-proposal'
    when a.action_class='authoritative-mutation'
      and a.action_key<>'auto-repair-authoritative-truth'
      and s.incident_state in ('warning','critical') then 'external-approval'
    when a.action_key='auto-repair-authoritative-truth' then 'prohibited'
    when a.action_class='history-mutation' then 'prohibited'
    when a.action_class='authoritative-mutation' then 'prohibited'
    else 'none'
  end as required_control,
  true,
  now(),
  'foundation:layer38:policy:v1',
  'Layer 38 incident-response matrix. Incident severity changes relevance, never mutation authority.'
from foundation.control_plane_incident_response_actions a
cross join (
  values ('normal'),('watching'),('warning'),('critical')
) s(incident_state)
where a.lifecycle='active'
on conflict (action_key,incident_state,policy_version) do nothing;


create or replace function foundation.evaluate_control_plane_incident_response_v1(
  p_action_key text,
  p_environment text default 'production'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer38_evaluate$
declare
  v_action foundation.control_plane_incident_response_actions%rowtype;
  v_policy foundation.control_plane_incident_response_policies%rowtype;
  v_summary jsonb;
  v_incident_state text;
  v_decision text := 'deny';
  v_reason text := 'response-policy-unavailable';
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$' then
    raise exception 'incident-response-environment-invalid';
  end if;

  if p_action_key is null
     or p_action_key !~ '^[a-z0-9][a-z0-9._:-]*$' then
    raise exception 'incident-response-action-invalid';
  end if;

  v_summary :=
    foundation.get_foundation_control_plane_incident_summary_v1(
      p_environment
    );
  v_incident_state := coalesce(v_summary->>'state','warning');

  select * into v_action
  from foundation.control_plane_incident_response_actions
  where action_key=p_action_key
    and lifecycle='active';

  if v_action.action_key is null then
    return jsonb_build_object(
      'foundationIncidentResponseDecisionResponse',
      'shine-foundation/incident-response-decision-response-v1',
      'schemaVersion','1.0.0',
      'environment',p_environment,
      'incidentState',v_incident_state,
      'actionKey',p_action_key,
      'decision','deny',
      'requiredControl','prohibited',
      'reasonCode','response-action-not-registered',
      'authorityExpansion',false,
      'incidentSummary',v_summary
    );
  end if;

  select * into v_policy
  from foundation.current_control_plane_incident_response_policies
  where action_key=p_action_key
    and incident_state=v_incident_state
    and enabled;

  if v_policy.response_policy_id is null then
    return jsonb_build_object(
      'foundationIncidentResponseDecisionResponse',
      'shine-foundation/incident-response-decision-response-v1',
      'schemaVersion','1.0.0',
      'environment',p_environment,
      'incidentState',v_incident_state,
      'actionKey',p_action_key,
      'actionClass',v_action.action_class,
      'mutatesAuthoritativeTruth',v_action.mutates_authoritative_truth,
      'mutatesIncidentHistory',v_action.mutates_incident_history,
      'decision','deny',
      'requiredControl','prohibited',
      'reasonCode','response-policy-missing',
      'authorityExpansion',false,
      'incidentSummary',v_summary
    );
  end if;

  v_decision := v_policy.decision;
  v_reason := case v_decision
    when 'admit' then 'response-policy-admit'
    when 'approval-required' then 'response-policy-external-approval-required'
    when 'deny' then 'response-policy-deny'
    else 'response-not-applicable'
  end;

  return jsonb_build_object(
    'foundationIncidentResponseDecisionResponse',
    'shine-foundation/incident-response-decision-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'incidentState',v_incident_state,
    'actionKey',p_action_key,
    'actionClass',v_action.action_class,
    'mutatesAuthoritativeTruth',v_action.mutates_authoritative_truth,
    'mutatesIncidentHistory',v_action.mutates_incident_history,
    'decision',v_decision,
    'requiredControl',v_policy.required_control,
    'reasonCode',v_reason,
    'authorityExpansion',false,
    'policyVersion',v_policy.policy_version,
    'policyEvidenceRef',v_policy.evidence_ref,
    'incidentSummary',v_summary
  );
end;
$layer38_evaluate$;

revoke all on function foundation.evaluate_control_plane_incident_response_v1(
  text,text
) from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.evaluate_control_plane_incident_response_v1(
  text,text
) to foundation_runtime,service_role;


create or replace function foundation.get_control_plane_incident_response_policy_health_v1(
  p_environment text default 'production'
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, foundation
as $layer38_health$
declare
  v_action_count integer := 0;
  v_expected_policy_count integer := 0;
  v_current_policy_count integer := 0;
  v_missing_policy_count integer := 0;
  v_authority_expansion_count integer := 0;
  v_history_mutation_not_denied integer := 0;
  v_auto_repair_not_denied integer := 0;
  v_state text := 'pass';
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$' then
    raise exception 'incident-response-environment-invalid';
  end if;

  select count(*) into v_action_count
  from foundation.control_plane_incident_response_actions
  where lifecycle='active';

  v_expected_policy_count := v_action_count*4;

  select count(*) into v_current_policy_count
  from foundation.current_control_plane_incident_response_policies p
  join foundation.control_plane_incident_response_actions a
    on a.action_key=p.action_key
  where a.lifecycle='active'
    and p.enabled;

  v_missing_policy_count :=
    greatest(v_expected_policy_count-v_current_policy_count,0);

  select count(*) into v_authority_expansion_count
  from foundation.current_control_plane_incident_response_policies p
  join foundation.control_plane_incident_response_actions a
    on a.action_key=p.action_key
  where a.lifecycle='active'
    and p.enabled
    and a.mutates_authoritative_truth
    and p.decision='admit';

  select count(*) into v_history_mutation_not_denied
  from foundation.current_control_plane_incident_response_policies p
  join foundation.control_plane_incident_response_actions a
    on a.action_key=p.action_key
  where a.lifecycle='active'
    and p.enabled
    and a.mutates_incident_history
    and p.decision<>'deny';

  select count(*) into v_auto_repair_not_denied
  from foundation.current_control_plane_incident_response_policies
  where action_key='auto-repair-authoritative-truth'
    and enabled
    and decision<>'deny';

  if v_action_count=0
     or v_missing_policy_count>0
     or v_authority_expansion_count>0
     or v_history_mutation_not_denied>0
     or v_auto_repair_not_denied>0 then
    v_state := 'fail';
  end if;

  return jsonb_build_object(
    'foundationIncidentResponsePolicyHealthResponse',
    'shine-foundation/incident-response-policy-health-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'state',v_state,
    'activeActionCount',v_action_count,
    'expectedPolicyCount',v_expected_policy_count,
    'currentPolicyCount',v_current_policy_count,
    'missingPolicyCount',v_missing_policy_count,
    'authorityExpansionCount',v_authority_expansion_count,
    'historyMutationNotDeniedCount',v_history_mutation_not_denied,
    'autoRepairNotDeniedCount',v_auto_repair_not_denied
  );
end;
$layer38_health$;

revoke all on function foundation.get_control_plane_incident_response_policy_health_v1(text)
  from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_control_plane_incident_response_policy_health_v1(text)
  to foundation_runtime,service_role;


create or replace function foundation.get_control_plane_incident_response_plan_v1(
  p_environment text default 'production'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer38_plan$
declare
  v_summary jsonb;
  v_incident_state text;
  v_actions jsonb := '[]'::jsonb;
begin
  v_summary :=
    foundation.get_foundation_control_plane_incident_summary_v1(
      p_environment
    );
  v_incident_state := coalesce(v_summary->>'state','warning');

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'actionKey',a.action_key,
        'actionClass',a.action_class,
        'decision',p.decision,
        'requiredControl',p.required_control,
        'mutatesAuthoritativeTruth',a.mutates_authoritative_truth,
        'mutatesIncidentHistory',a.mutates_incident_history,
        'description',a.description
      )
      order by
        case p.decision
          when 'admit' then 1
          when 'approval-required' then 2
          when 'not-applicable' then 3
          else 4
        end,
        a.action_key
    ),
    '[]'::jsonb
  )
  into v_actions
  from foundation.control_plane_incident_response_actions a
  join foundation.current_control_plane_incident_response_policies p
    on p.action_key=a.action_key
   and p.incident_state=v_incident_state
   and p.enabled
  where a.lifecycle='active';

  return jsonb_build_object(
    'foundationIncidentResponsePlanResponse',
    'shine-foundation/incident-response-plan-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'incidentState',v_incident_state,
    'authorityExpansion',false,
    'automaticRepairAllowed',false,
    'incidentSummary',v_summary,
    'actions',v_actions
  );
end;
$layer38_plan$;

revoke all on function foundation.get_control_plane_incident_response_plan_v1(text)
  from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_control_plane_incident_response_plan_v1(text)
  to foundation_runtime,service_role;
