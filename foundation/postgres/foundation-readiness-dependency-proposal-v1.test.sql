begin;

-- No active incident => no proposal.
create or replace function foundation.get_readiness_dependency_proposal_status_v1(p_proposal_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $orig$
declare p foundation.readiness_dependency_remediation_proposals%rowtype;i foundation.foundation_readiness_incident_events%rowtype;current_cfp text;
begin
 select * into p from foundation.readiness_dependency_remediation_proposals where proposal_id=p_proposal_id;
 if p.proposal_id is null then return jsonb_build_object('state','not-found','usable',false); end if;
 select * into i from foundation.current_foundation_readiness_incident_state where incident_key=p.environment||':readiness';
 current_cfp:=i.condition_fingerprint;
 return jsonb_build_object('state',case when i.event_type not in('opened','changed') or i.event_id<>p.readiness_incident_event_id or current_cfp<>p.condition_fingerprint then 'stale' else 'current' end,
 'usable',i.event_type in('opened','changed') and i.event_id=p.readiness_incident_event_id and current_cfp=p.condition_fingerprint,
 'executionAuthorityGranted',false,'approvalGranted',false);
end;$orig$;

-- Use current Layer-44 lifecycle fixture pattern: one synthetic active event referencing an existing drift observation.
insert into foundation.foundation_readiness_incident_events(
 event_id,incident_key,environment,event_type,readiness_state,drift_state,severity,
 reason_codes,degraded_scopes,guarded_scopes,blocked_scopes,readiness_drift_observation_id,
 evidence_fingerprint,condition_fingerprint,detection_started_at,persistence_threshold_seconds,
 persistence_seconds,snapshot,occurred_at
)
select '47000000-0000-4000-8000-000000000001'::uuid,'production:readiness','production','opened',
 current_readiness_state,drift_state,'warning',reason_codes,degraded_scopes,guarded_scopes,
 blocked_scopes,observation_id,evidence_fingerprint,condition_fingerprint,
 now()-interval '10 minutes',300,600,snapshot,now()
from foundation.foundation_readiness_drift_observations
where condition_fingerprint is not null
order by observation_sequence desc limit 1;

do $proposal$
declare v jsonb;s jsonb;
begin
 v:=foundation.propose_readiness_dependency_remediation_v1('production',now());
 if v->>'proposed'<>'true' or v->>'executionAuthorityGranted'<>'false'
    or v->>'approvalGranted'<>'false'
    or not((v->'proposal'->'prohibitedWork') ? 'mutate-foundation-canonical-truth') then
  raise exception 'Bounded proposal invalid: %',v;
 end if;
 s:=foundation.get_readiness_dependency_proposal_status_v1((v->>'proposalId')::uuid);
 if s->>'state'<>'current' or s->>'usable'<>'true' then raise exception 'Fresh proposal must be current: %',s; end if;
end;
$proposal$;

rollback;
