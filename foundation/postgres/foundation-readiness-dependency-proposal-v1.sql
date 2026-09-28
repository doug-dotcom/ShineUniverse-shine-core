-- Foundation Layer 47: bounded dependency-remediation proposals.

create table foundation.readiness_dependency_remediation_proposals(
 proposal_sequence bigint generated always as identity primary key,
 proposal_id uuid not null unique default gen_random_uuid(),
 environment text not null,
 readiness_incident_event_id uuid not null references foundation.foundation_readiness_incident_events(event_id),
 condition_fingerprint text not null check(condition_fingerprint ~ '^[a-f0-9]{32}$'),
 severity text not null,
 reason_codes jsonb not null check(jsonb_typeof(reason_codes)='array'),
 affected_scopes jsonb not null check(jsonb_typeof(affected_scopes)='array'),
 proposal jsonb not null check(jsonb_typeof(proposal)='object'),
 proposal_sha256 text not null check(proposal_sha256 ~ '^[a-f0-9]{64}$'),
 status text not null default 'proposed' check(status='proposed'),
 created_at timestamptz not null default now(),
 unique(readiness_incident_event_id,condition_fingerprint)
);
alter table foundation.readiness_dependency_remediation_proposals enable row level security;
create policy foundation_runtime_readiness_dependency_proposals_select
on foundation.readiness_dependency_remediation_proposals for select to foundation_runtime using(true);
revoke all on foundation.readiness_dependency_remediation_proposals
 from public,anon,authenticated,foundation_gateway,service_role;
grant select on foundation.readiness_dependency_remediation_proposals
 to foundation_runtime,service_role;
create index readiness_dependency_proposals_incident_idx on foundation.readiness_dependency_remediation_proposals(readiness_incident_event_id);
create trigger readiness_dependency_proposals_append_only before update or delete on foundation.readiness_dependency_remediation_proposals
for each row execute function foundation.reject_append_only_mutation();

create or replace function foundation.propose_readiness_dependency_remediation_v1(
 p_environment text default 'production',p_created_at timestamptz default now()
)
returns jsonb language plpgsql security definer set search_path='' as $proposal$
declare
 i foundation.foundation_readiness_incident_events%rowtype;
 existing foundation.readiness_dependency_remediation_proposals%rowtype;
 cfp text;
 p jsonb;
 h text;
 pid uuid;
 scopes jsonb;
 scope_plan jsonb;
 response_policy jsonb;
begin
 response_policy:=foundation.evaluate_readiness_incident_response_v1(
   'propose-dependency-remediation',p_environment
 );

 if response_policy->>'decision'<>'admit' then
  return jsonb_build_object(
   'foundationReadinessDependencyRemediationProposalResponse',
     'shine-foundation/readiness-dependency-remediation-proposal-response-v1',
   'schemaVersion','1.0.0','proposed',false,
   'reasonCode','readiness-remediation-proposal-not-admitted',
   'responseDecision',response_policy->>'decision',
   'executionAuthorityGranted',false,'approvalGranted',false
  );
 end if;

 select * into i
 from foundation.current_foundation_readiness_incident_state
 where incident_key=p_environment||':readiness';

 if i.event_id is null or i.event_type not in('opened','changed') then
  return jsonb_build_object(
   'foundationReadinessDependencyRemediationProposalResponse',
     'shine-foundation/readiness-dependency-remediation-proposal-response-v1',
   'schemaVersion','1.0.0','proposed',false,
   'reasonCode','active-readiness-incident-required',
   'executionAuthorityGranted',false,'approvalGranted',false
  );
 end if;

 cfp:=coalesce(
   i.condition_fingerprint,
   md5(jsonb_build_object(
    'readinessState',i.readiness_state,'reasonCodes',i.reason_codes,
    'degradedScopes',i.degraded_scopes,'guardedScopes',i.guarded_scopes,
    'blockedScopes',i.blocked_scopes,
    'privilegedOperationsMode',i.snapshot#>>'{current,privilegedOperationsMode}',
    'workerOperationsMode',i.snapshot#>>'{current,workerOperationsMode}'
   )::text)
 );

 select * into existing
 from foundation.readiness_dependency_remediation_proposals
 where readiness_incident_event_id=i.event_id
   and condition_fingerprint=cfp
 order by proposal_sequence desc
 limit 1;

 if existing.proposal_id is not null then
  return jsonb_build_object(
   'foundationReadinessDependencyRemediationProposalResponse',
     'shine-foundation/readiness-dependency-remediation-proposal-response-v1',
   'schemaVersion','1.0.0','proposed',true,'status','existing',
   'proposalId',existing.proposal_id,'proposalSha256',existing.proposal_sha256,
   'executionAuthorityGranted',false,'approvalGranted',false,
   'proposal',existing.proposal
  );
 end if;

 select coalesce(jsonb_agg(scope order by scope),'[]'::jsonb)
 into scopes
 from (
   select value as scope from jsonb_array_elements_text(coalesce(i.degraded_scopes,'[]'::jsonb)) t(value)
   union
   select value from jsonb_array_elements_text(coalesce(i.guarded_scopes,'[]'::jsonb)) t(value)
   union
   select value from jsonb_array_elements_text(coalesce(i.blocked_scopes,'[]'::jsonb)) t(value)
 ) x;

 select coalesce(
   jsonb_agg(
     jsonb_build_object(
       'scope',scope,
       'disposition',disposition,
       'work',jsonb_build_array(
         'collect-fresh-scope-evidence',
         'identify-degraded-upstream-dependency',
         'prepare-upstream-remediation',
         'rerun-foundation-readiness-verification'
       )
     )
     order by scope
   ),
   '[]'::jsonb
 )
 into scope_plan
 from (
   select scope,max(disposition) filter(where rank=max_rank) as disposition
   from (
     select scope,disposition,rank,max(rank) over(partition by scope) max_rank
     from (
       select value scope,'degraded'::text disposition,1 rank
       from jsonb_array_elements_text(coalesce(i.degraded_scopes,'[]'::jsonb)) t(value)
       union all
       select value,'guarded',2
       from jsonb_array_elements_text(coalesce(i.guarded_scopes,'[]'::jsonb)) t(value)
       union all
       select value,'blocked',3
       from jsonb_array_elements_text(coalesce(i.blocked_scopes,'[]'::jsonb)) t(value)
     ) r
   ) ranked
   group by scope,max_rank
 ) final;

 if jsonb_array_length(scopes)=0 then
  raise exception 'readiness-remediation-no-affected-scopes';
 end if;

 p:=jsonb_build_object(
  'readinessDependencyRemediationProposal',
    'shine-foundation/readiness-dependency-remediation-proposal-v1',
  'schemaVersion','1.0.0','environment',p_environment,
  'incidentEventId',i.event_id,'conditionFingerprint',cfp,
  'readinessState',i.readiness_state,'severity',i.severity,
  'reasonCodes',i.reason_codes,'affectedScopes',scopes,'scopePlan',scope_plan,
  'requestedOutcome','restore-readiness-without-release-identity-mutation',
  'allowedWork',jsonb_build_array(
    'investigate-dependency-evidence',
    'repair-external-dependency-or-defence-posture',
    'collect-fresh-readiness-evidence'
  ),
  'prohibitedWork',jsonb_build_array(
    'mutate-foundation-canonical-truth',
    'rebind-foundation-release',
    'bypass-safe-mode',
    'automatic-unapproved-repair'
  ),
  'completionCriteria',jsonb_build_array(
    'fresh-readiness-evidence-collected',
    'affected-scope-condition-cleared-or-improved',
    'semantic-readiness-retest-run',
    'readiness-incident-recovered-or-materially-updated'
  ),
  'executionAuthorityGranted',false,'approvalGranted',false,
  'createdAt',p_created_at
 );

 h:=encode(extensions.digest(convert_to(p::text,'UTF8'),'sha256'),'hex');

 insert into foundation.readiness_dependency_remediation_proposals(
  environment,readiness_incident_event_id,condition_fingerprint,severity,
  reason_codes,affected_scopes,proposal,proposal_sha256,created_at
 ) values(
  p_environment,i.event_id,cfp,i.severity,i.reason_codes,
  scopes,p,h,p_created_at
 )
 returning proposal_id into pid;

 return jsonb_build_object(
  'foundationReadinessDependencyRemediationProposalResponse',
    'shine-foundation/readiness-dependency-remediation-proposal-response-v1',
  'schemaVersion','1.0.0','proposed',true,'status','generated',
  'proposalId',pid,'proposalSha256',h,
  'executionAuthorityGranted',false,'approvalGranted',false,'proposal',p
 );
end;
$proposal$;

revoke all on function foundation.propose_readiness_dependency_remediation_v1(text,timestamptz)
 from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.propose_readiness_dependency_remediation_v1(text,timestamptz)
 to service_role;

create or replace function foundation.get_readiness_dependency_proposal_status_v1(
 p_proposal_id uuid
)
returns jsonb language plpgsql stable security definer set search_path='' as $status$
declare
 p foundation.readiness_dependency_remediation_proposals%rowtype;
 i foundation.foundation_readiness_incident_events%rowtype;
 current_cfp text;
 expected_hash text;
 state text;
begin
 select * into p
 from foundation.readiness_dependency_remediation_proposals
 where proposal_id=p_proposal_id;

 if p.proposal_id is null then
  return jsonb_build_object('state','not-found','usable',false);
 end if;

 expected_hash:=encode(
  extensions.digest(convert_to(p.proposal::text,'UTF8'),'sha256'),
  'hex'
 );

 select * into i
 from foundation.current_foundation_readiness_incident_state
 where incident_key=p.environment||':readiness';

 current_cfp:=case
  when i.event_id is null then null
  else coalesce(
   i.condition_fingerprint,
   md5(jsonb_build_object(
    'readinessState',i.readiness_state,'reasonCodes',i.reason_codes,
    'degradedScopes',i.degraded_scopes,'guardedScopes',i.guarded_scopes,
    'blockedScopes',i.blocked_scopes,
    'privilegedOperationsMode',i.snapshot#>>'{current,privilegedOperationsMode}',
    'workerOperationsMode',i.snapshot#>>'{current,workerOperationsMode}'
   )::text)
  )
 end;

 state:=case
  when expected_hash is distinct from p.proposal_sha256 then 'invalid'
  when i.event_type not in('opened','changed') then 'stale'
  when i.event_id is distinct from p.readiness_incident_event_id then 'stale'
  when current_cfp is distinct from p.condition_fingerprint then 'stale'
  else 'current'
 end;

 return jsonb_build_object(
  'state',state,'usable',state='current',
  'proposalId',p.proposal_id,'incidentEventId',p.readiness_incident_event_id,
  'conditionFingerprint',p.condition_fingerprint,
  'proposalSha256',p.proposal_sha256,
  'integrityVerified',expected_hash=p.proposal_sha256,
  'executionAuthorityGranted',false,'approvalGranted',false
 );
end;
$status$;

revoke all on function foundation.get_readiness_dependency_proposal_status_v1(uuid)
 from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_readiness_dependency_proposal_status_v1(uuid)
 to foundation_runtime,service_role;

