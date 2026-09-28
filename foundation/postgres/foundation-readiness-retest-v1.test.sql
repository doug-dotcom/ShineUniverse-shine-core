begin;

-- Seed one prior watch and two drift observations with different raw evidence
-- but the same semantic degraded condition.
insert into foundation.foundation_readiness_drift_observations(
 observation_id,environment,binding_id,release_ref,readiness_state_at_bind,
 readiness_fingerprint_at_bind,current_readiness_state,current_readiness_fingerprint,
 drift_state,deployment_identity_stable,privileged_operations_mode,worker_operations_mode,
 reason_codes,degraded_scopes,guarded_scopes,blocked_scopes,snapshot,
 evidence_fingerprint,condition_fingerprint,observed_at
)
select
 '46000000-0000-4000-8000-000000000101'::uuid,'production',binding_id,release_ref,
 readiness_state_at_bind,readiness_fingerprint_at_bind,'degraded',repeat('2',32),
 'operational-degradation',true,'degraded','degraded',
 '["dependency-degraded"]'::jsonb,'["protected-operations"]'::jsonb,'[]'::jsonb,'[]'::jsonb,
 '{"test":"raw-a"}'::jsonb,repeat('2',32),repeat('9',32),now()
from foundation.current_foundation_release_identity
where service_id='foundation.gateway' and environment='production';

insert into foundation.foundation_readiness_drift_observations(
 observation_id,environment,binding_id,release_ref,readiness_state_at_bind,
 readiness_fingerprint_at_bind,current_readiness_state,current_readiness_fingerprint,
 drift_state,deployment_identity_stable,privileged_operations_mode,worker_operations_mode,
 reason_codes,degraded_scopes,guarded_scopes,blocked_scopes,snapshot,
 evidence_fingerprint,condition_fingerprint,observed_at
)
select
 '46000000-0000-4000-8000-000000000102'::uuid,environment,binding_id,release_ref,
 readiness_state_at_bind,readiness_fingerprint_at_bind,current_readiness_state,repeat('3',32),
 drift_state,deployment_identity_stable,privileged_operations_mode,worker_operations_mode,
 reason_codes,degraded_scopes,guarded_scopes,blocked_scopes,'{"test":"raw-b"}'::jsonb,
 repeat('3',32),condition_fingerprint,now()+interval '300 seconds'
from foundation.foundation_readiness_drift_observations
where observation_id='46000000-0000-4000-8000-000000000101'::uuid;

insert into foundation.foundation_readiness_incident_events(
 event_id,incident_key,environment,event_type,readiness_state,drift_state,severity,
 reason_codes,degraded_scopes,guarded_scopes,blocked_scopes,readiness_drift_observation_id,
 evidence_fingerprint,condition_fingerprint,detection_started_at,
 persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at
)
select
 '46000000-0000-4000-8000-000000000201'::uuid,'production:readiness','production',
 'detected','degraded','operational-degradation','warning',reason_codes,degraded_scopes,
 guarded_scopes,blocked_scopes,observation_id,evidence_fingerprint,condition_fingerprint,
 now(),300,0,snapshot,now()
from foundation.foundation_readiness_drift_observations
where observation_id='46000000-0000-4000-8000-000000000101'::uuid;

do $proof$
declare a foundation.foundation_readiness_drift_observations%rowtype;
        b foundation.foundation_readiness_drift_observations%rowtype;
begin
 select * into a from foundation.foundation_readiness_drift_observations
 where observation_id='46000000-0000-4000-8000-000000000101'::uuid;
 select * into b from foundation.foundation_readiness_drift_observations
 where observation_id='46000000-0000-4000-8000-000000000102'::uuid;
 if a.evidence_fingerprint=b.evidence_fingerprint
    or a.condition_fingerprint<>b.condition_fingerprint then
   raise exception 'Layer 46 must separate raw evidence from semantic condition';
 end if;
end;
$proof$;

rollback;
