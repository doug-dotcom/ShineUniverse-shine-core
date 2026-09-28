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
 created_at timestamptz not null default now()
);
alter table foundation.readiness_dependency_remediation_proposals enable row level security;
create policy foundation_runtime_readiness_dependency_proposals_select
on foundation.readiness_dependency_remediation_proposals for select to foundation_runtime using(true);
revoke all on foundation.readiness_dependency_remediation_proposals from public,anon,authenticated,foundation_gateway;
grant select on foundation.readiness_dependency_remediation_proposals to foundation_runtime,service_role;
create index readiness_dependency_proposals_incident_idx on foundation.readiness_dependency_remediation_proposals(readiness_incident_event_id);
create trigger readiness_dependency_proposals_append_only before update or delete on foundation.readiness_dependency_remediation_proposals
for each row execute function foundation.reject_append_only_mutation();

create or replace function foundation.propose_readiness_dependency_remediation_v1(
 p_environment text default 'production',p_created_at timestamptz default now()
)
returns jsonb language plpgsql security definer set search_path='' as $proposal$
declare i foundation.foundation_readiness_incident_events%rowtype;cfp text;p jsonb;h text;pid uuid;scopes jsonb;
begin
 select * into i from foundation.current_foundation_readiness_incident_state
 where incident_key=p_environment||':readiness';
 if i.event_id is null or i.event_type not in('opened','changed') then
  return jsonb_build_object('proposed',false,'reasonCode','active-readiness-incident-required');
 end if;
 cfp:=coalesce(i.condition_fingerprint,md5(jsonb_build_object(
  'readinessState',i.readiness_state,'reasonCodes',i.reason_codes,'degradedScopes',i.degraded_scopes,
  'guardedScopes',i.guarded_scopes,'blockedScopes',i.blocked_scopes,
  'privilegedOperationsMode',i.snapshot#>>'{current,privilegedOperationsMode}',
  'workerOperationsMode',i.snapshot#>>'{current,workerOperationsMode}')::text));
 scopes:=coalesce(i.degraded_scopes,'[]'::jsonb)||coalesce(i.guarded_scopes,'[]'::jsonb)||coalesce(i.blocked_scopes,'[]'::jsonb);
 p:=jsonb_build_object(
  'readinessDependencyRemediationProposal','shine-foundation/readiness-dependency-remediation-proposal-v1',
  'schemaVersion','1.0.0','environment',p_environment,'incidentEventId',i.event_id,
  'conditionFingerprint',cfp,'severity',i.severity,'reasonCodes',i.reason_codes,
  'affectedScopes',scopes,'requestedOutcome','restore-readiness-without-release-identity-mutation',
  'allowedWork',jsonb_build_array('investigate-dependency-evidence','repair-external-dependency-or-defence-posture','collect-fresh-readiness-evidence'),
  'prohibitedWork',jsonb_build_array('mutate-foundation-canonical-truth','rebind-foundation-release','bypass-safe-mode','automatic-unapproved-repair'),
  'executionAuthorityGranted',false,'approvalGranted',false,'createdAt',p_created_at
 );
 h:=encode(extensions.digest(convert_to(p::text,'UTF8'),'sha256'),'hex');
 select proposal_id into pid from foundation.readiness_dependency_remediation_proposals
 where readiness_incident_event_id=i.event_id and condition_fingerprint=cfp and proposal_sha256=h
 order by proposal_sequence desc limit 1;
 if pid is null then
  insert into foundation.readiness_dependency_remediation_proposals(
   environment,readiness_incident_event_id,condition_fingerprint,severity,reason_codes,
   affected_scopes,proposal,proposal_sha256,created_at
  ) values(p_environment,i.event_id,cfp,i.severity,i.reason_codes,scopes,p,h,p_created_at)
  returning proposal_id into pid;
 end if;
 return jsonb_build_object(
  'foundationReadinessDependencyRemediationProposalResponse','shine-foundation/readiness-dependency-remediation-proposal-response-v1',
  'schemaVersion','1.0.0','proposed',true,'proposalId',pid,'proposalSha256',h,
  'executionAuthorityGranted',false,'approvalGranted',false,'proposal',p
 );
end;
$proposal$;

revoke all on function foundation.propose_readiness_dependency_remediation_v1(text,timestamptz)
 from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.propose_readiness_dependency_remediation_v1(text,timestamptz) to service_role;

create or replace function foundation.get_readiness_dependency_proposal_status_v1(p_proposal_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $status$
declare p foundation.readiness_dependency_remediation_proposals%rowtype;i foundation.foundation_readiness_incident_events%rowtype;current_cfp text;
begin
 select * into p from foundation.readiness_dependency_remediation_proposals where proposal_id=p_proposal_id;
 if p.proposal_id is null then return jsonb_build_object('state','not-found','usable',false); end if;
 select * into i from foundation.current_foundation_readiness_incident_state where incident_key=p.environment||':readiness';
 current_cfp:=case when i.event_id is null then null else coalesce(i.condition_fingerprint,md5(jsonb_build_object(
  'readinessState',i.readiness_state,'reasonCodes',i.reason_codes,'degradedScopes',i.degraded_scopes,
  'guardedScopes',i.guarded_scopes,'blockedScopes',i.blocked_scopes,
  'privilegedOperationsMode',i.snapshot#>>'{current,privilegedOperationsMode}',
  'workerOperationsMode',i.snapshot#>>'{current,workerOperationsMode}')::text)) end;
 return jsonb_build_object(
  'state',case when i.event_type not in('opened','changed') then 'stale'
               when i.event_id<>p.readiness_incident_event_id then 'stale'
               when current_cfp<>p.condition_fingerprint then 'stale' else 'current' end,
  'usable',i.event_type in('opened','changed') and i.event_id=p.readiness_incident_event_id and current_cfp=p.condition_fingerprint,
  'proposalId',p.proposal_id,'incidentEventId',p.readiness_incident_event_id,
  'conditionFingerprint',p.condition_fingerprint,'executionAuthorityGranted',false,'approvalGranted',false
 );
end;
$status$;
revoke all on function foundation.get_readiness_dependency_proposal_status_v1(uuid) from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_readiness_dependency_proposal_status_v1(uuid) to foundation_runtime,service_role;
