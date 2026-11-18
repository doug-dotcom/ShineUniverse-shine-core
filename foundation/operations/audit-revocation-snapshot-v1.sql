-- Operator-only, read-only snapshot. No payloads, tokens, users or clinical data.
begin transaction isolation level repeatable read read only;
with deployment as (
 select runtime_version,artifact_sha256 from foundation.current_service_deployment_observations
 where service_id='foundation.gateway' and environment='production'
), traces as (
 select coalesce(p.operation_audit_id,o.operation_audit_id) as id,
 coalesce(p.runtime_version,o.runtime_version) as version,
 coalesce(p.artifact_sha256,o.artifact_sha256) as artifact,
 p.occurred_at as started_at, o.occurred_at as finished_at,
 p.audit_event_id is not null as has_policy,
 o.audit_event_id is not null as has_outcome,
 o.audit_event_id is not null and (p.audit_event_id is null or o.previous_event_hash is distinct from p.event_hash or o.runtime_version is distinct from p.runtime_version or o.artifact_sha256 is distinct from p.artifact_sha256) as broken
 from (select * from foundation.gateway_operation_audit_events where environment='production' and phase='policy') p
 full join (select * from foundation.gateway_operation_audit_events where environment='production' and phase='outcome') o
 using(operation_audit_id)
), grouped as (
 select case when t.version=d.runtime_version and t.artifact=d.artifact_sha256 then 'current' else 'historical' end as scope,
 count(*) filter(where has_policy and has_outcome and not broken and finished_at>=now()-interval '24 hours') as fresh_complete,
 count(*) filter(where broken) as broken,
 count(*) filter(where has_policy and not has_outcome and started_at<now()-interval '5 minutes') as stale_open,
 count(*) filter(where has_policy and not has_outcome and started_at>=now()-interval '5 minutes') as pending,
 coalesce(jsonb_agg(jsonb_build_object('id',id,'runtimeVersion',version,'startedAt',started_at,'kind',case when broken then 'broken-chain' else 'missing-outcome' end))
 filter(where broken or (has_policy and not has_outcome and started_at<now()-interval '5 minutes')),'[]'::jsonb) as issues
 from traces t left join deployment d on true group by 1
), revocations as (
 select h.* from foundation.app_registry a
 cross join lateral foundation.get_app_revocation_health_v1(a.app_id) h
 where a.status='active' and a.app_id ~ '^shine\.[a-z0-9][a-z0-9-]*$'
)
select jsonb_build_object(
 'contract','shine-foundation/audit-revocation-operations-v1','observedAt',now(),
 'deployment',(select to_jsonb(d) from deployment d),
 'audit',coalesce((select jsonb_agg(to_jsonb(g)) from grouped g),'[]'::jsonb),
 'revocations',coalesce((select jsonb_agg(jsonb_build_object('appId',app_id,'pendingCount',pending_count,'freshness',freshness_state,'action',recommended_action,'staleAction',stale_action,'oldestPendingAt',oldest_pending_at)) from revocations),'[]'::jsonb)
) as snapshot;
commit;
