-- Foundation Layer 47: dependency-remediation proposals for active readiness incidents.
-- Proposals are deterministic, append-only, incident/condition-bound, and non-executing.

create table foundation.readiness_dependency_remediation_proposals(
  proposal_sequence bigint generated always as identity primary key,
  proposal_id uuid not null unique default gen_random_uuid(),
  environment text not null,
  readiness_incident_event_id uuid not null
    references foundation.foundation_readiness_incident_events(event_id),
  incident_key text not null,
  condition_fingerprint text not null
    check(condition_fingerprint ~ '^[a-f0-9]{32}$'),
  readiness_state text not null,
  severity text not null,
  release_ref_at_proposal text,
  affected_scopes jsonb not null check(jsonb_typeof(affected_scopes)='array'),
  proposal jsonb not null check(jsonb_typeof(proposal)='object'),
  proposal_sha256 text not null check(proposal_sha256 ~ '^[a-f0-9]{64}$'),
  generated_by text not null default 'foundation.readiness-proposal-v1',
  created_at timestamptz not null default now(),
  unique(readiness_incident_event_id,condition_fingerprint)
);

alter table foundation.readiness_dependency_remediation_proposals enable row level security;

create policy foundation_runtime_readiness_remediation_proposals_select
on foundation.readiness_dependency_remediation_proposals
for select to foundation_runtime using(true);

revoke all on foundation.readiness_dependency_remediation_proposals
  from public,anon,authenticated,foundation_gateway,service_role;
grant select on foundation.readiness_dependency_remediation_proposals
  to foundation_runtime,service_role;

create index readiness_dependency_remediation_proposals_incident_idx
  on foundation.readiness_dependency_remediation_proposals(
    readiness_incident_event_id,created_at desc,proposal_sequence desc
  );

create trigger readiness_dependency_remediation_proposals_append_only
before update or delete on foundation.readiness_dependency_remediation_proposals
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.generate_readiness_dependency_remediation_proposal_v1(
  p_environment text default 'production'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $layer47_generate$
declare
  s jsonb;
  p jsonb;
  current_event foundation.foundation_readiness_incident_events%rowtype;
  current_binding foundation.foundation_release_identity_bindings%rowtype;
  scopes jsonb := '[]'::jsonb;
  proposal_doc jsonb;
  proposal_hash text;
  existing foundation.readiness_dependency_remediation_proposals%rowtype;
  new_id uuid;
begin
  s:=foundation.get_foundation_readiness_incident_summary_v1(p_environment);
  p:=foundation.get_readiness_incident_containment_plan_v1(p_environment);

  if s->>'state'<>'incident'
     or coalesce((p->>'containmentActive')::boolean,false)<>true then
    return jsonb_build_object(
      'foundationReadinessRemediationProposalResponse',
        'shine-foundation/readiness-remediation-proposal-response-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','readiness-incident-not-active',
      'executionAuthority',false,
      'executesAction',false
    );
  end if;

  select * into current_event
  from foundation.current_foundation_readiness_incident_state
  where incident_key=p_environment||':readiness';

  if current_event.event_id is null
     or current_event.event_type not in('opened','changed') then
    raise exception 'readiness-remediation-current-incident-invalid';
  end if;

  select * into current_binding
  from foundation.current_foundation_release_identity
  where service_id='foundation.gateway'
    and environment=p_environment;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'scope',x.scope,
        'disposition',x.disposition,
        'work',jsonb_build_array(
          'collect-fresh-scope-evidence',
          'identify-degraded-upstream-dependency',
          'prepare-upstream-remediation',
          'rerun-foundation-readiness-verification'
        )
      )
      order by x.scope
    ),
    '[]'::jsonb
  )
  into scopes
  from (
    select value as scope,'blocked'::text as disposition,3 as rank
    from jsonb_array_elements_text(current_event.blocked_scopes) as t(value)
    union all
    select value,'guarded',2
    from jsonb_array_elements_text(current_event.guarded_scopes) as t(value)
    union all
    select value,'degraded',1
    from jsonb_array_elements_text(current_event.degraded_scopes) as t(value)
  ) x
  where not exists (
    select 1
    from (
      select value as scope2,3 as rank2 from jsonb_array_elements_text(current_event.blocked_scopes) as t(value)
      union all
      select value,2 from jsonb_array_elements_text(current_event.guarded_scopes) as t(value)
      union all
      select value,1 from jsonb_array_elements_text(current_event.degraded_scopes) as t(value)
    ) y
    where y.scope2=x.scope and y.rank2>x.rank
  );

  if jsonb_array_length(scopes)=0 then
    raise exception 'readiness-remediation-no-affected-scopes';
  end if;

  proposal_doc:=jsonb_build_object(
    'readinessDependencyRemediationProposal',
      'shine-foundation/readiness-dependency-remediation-proposal-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'readinessIncidentEventId',current_event.event_id,
    'incidentKey',current_event.incident_key,
    'conditionFingerprint',current_event.condition_fingerprint,
    'readinessState',current_event.readiness_state,
    'severity',current_event.severity,
    'releaseRefAtProposal',current_binding.release_ref,
    'reasonCodes',current_event.reason_codes,
    'affectedScopes',scopes,
    'containment',jsonb_build_object(
      'active',true,
      'canonicalTruthMutationAllowed',false,
      'releaseRebindAllowed',false,
      'automaticDependencyRepair',false
    ),
    'completionCriteria',jsonb_build_array(
      'fresh-readiness-evidence-collected',
      'affected-scope-condition-cleared-or-improved',
      'readiness-retest-cycle-run',
      'readiness-incident-recovered-or-materially-updated'
    ),
    'executionAuthority',false,
    'executesAction',false
  );

  proposal_hash:=encode(
    extensions.digest(convert_to(proposal_doc::text,'UTF8'),'sha256'),
    'hex'
  );

  select * into existing
  from foundation.readiness_dependency_remediation_proposals
  where readiness_incident_event_id=current_event.event_id
    and condition_fingerprint=current_event.condition_fingerprint;

  if existing.proposal_id is not null then
    return jsonb_build_object(
      'foundationReadinessRemediationProposalResponse',
        'shine-foundation/readiness-remediation-proposal-response-v1',
      'schemaVersion','1.0.0',
      'status','existing',
      'proposalId',existing.proposal_id,
      'proposalSha256',existing.proposal_sha256,
      'proposal',existing.proposal,
      'executionAuthority',false,
      'executesAction',false
    );
  end if;

  insert into foundation.readiness_dependency_remediation_proposals(
    environment,readiness_incident_event_id,incident_key,condition_fingerprint,
    readiness_state,severity,release_ref_at_proposal,affected_scopes,
    proposal,proposal_sha256
  )
  values(
    p_environment,current_event.event_id,current_event.incident_key,
    current_event.condition_fingerprint,current_event.readiness_state,
    current_event.severity,current_binding.release_ref,scopes,
    proposal_doc,proposal_hash
  )
  returning proposal_id into new_id;

  return jsonb_build_object(
    'foundationReadinessRemediationProposalResponse',
      'shine-foundation/readiness-remediation-proposal-response-v1',
    'schemaVersion','1.0.0',
    'status','generated',
    'proposalId',new_id,
    'proposalSha256',proposal_hash,
    'proposal',proposal_doc,
    'executionAuthority',false,
    'executesAction',false
  );
end;
$layer47_generate$;

revoke all on function foundation.generate_readiness_dependency_remediation_proposal_v1(text)
  from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.generate_readiness_dependency_remediation_proposal_v1(text)
  to service_role;


create or replace function foundation.get_readiness_dependency_remediation_proposal_status_v1(
  p_proposal_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $layer47_status$
declare
  q foundation.readiness_dependency_remediation_proposals%rowtype;
  c foundation.foundation_readiness_incident_events%rowtype;
  h text;
  status text;
begin
  select * into q
  from foundation.readiness_dependency_remediation_proposals
  where proposal_id=p_proposal_id;

  if q.proposal_id is null then
    return jsonb_build_object('status','missing','proposalId',p_proposal_id);
  end if;

  h:=encode(
    extensions.digest(convert_to(q.proposal::text,'UTF8'),'sha256'),
    'hex'
  );

  select * into c
  from foundation.current_foundation_readiness_incident_state
  where incident_key=q.incident_key;

  status:=case
    when h is distinct from q.proposal_sha256 then 'invalid'
    when c.event_id is null or c.event_type not in('opened','changed') then 'stale'
    when c.event_id is distinct from q.readiness_incident_event_id then 'stale'
    when c.condition_fingerprint is distinct from q.condition_fingerprint then 'stale'
    else 'active'
  end;

  return jsonb_build_object(
    'foundationReadinessRemediationProposalStatus',
      'shine-foundation/readiness-remediation-proposal-status-v1',
    'schemaVersion','1.0.0',
    'proposalId',q.proposal_id,
    'status',status,
    'readinessIncidentEventId',q.readiness_incident_event_id,
    'conditionFingerprint',q.condition_fingerprint,
    'proposalSha256',q.proposal_sha256,
    'integrityVerified',h=q.proposal_sha256,
    'currentIncidentEventId',c.event_id,
    'currentConditionFingerprint',c.condition_fingerprint,
    'executionAuthority',false,
    'executesAction',false
  );
end;
$layer47_status$;

revoke all on function foundation.get_readiness_dependency_remediation_proposal_status_v1(uuid)
  from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_readiness_dependency_remediation_proposal_status_v1(uuid)
  to foundation_runtime,service_role;
