begin;

do $$
declare
  v jsonb;
begin
  select foundation.get_defence_estate_summary_v1() into v;
  if v->>'state'<>'warning'
     or (v->>'requiredTargets')::integer<>20
     or (v->>'mappedApps')::integer<>18
     or (v->>'missingTargets')::integer<>20 then
    raise exception 'fresh federation registry should start fully mapped but unobserved: %',v;
  end if;
end;
$$;

insert into foundation.defence_estate_observations(
  target_id,runtime_state,health_state,observed_at,valid_until,
  evidence_kind,evidence_ref,metadata
)
select
  target_id,
  case when target_id='railway:dnd' then 'sleeping' else 'active' end,
  'unknown',
  now(),
  now()+interval '1 hour',
  'manual-verified',
  'test:federation:'||target_id,
  '{}'::jsonb
from foundation.defence_estate_targets
where lifecycle='active' and required_for_estate;

do $$
declare
  v jsonb;
begin
  select foundation.get_defence_estate_summary_v1() into v;
  if v->>'state'<>'pass'
     or (v->>'freshTargets')::integer<>20
     or (v->>'missingTargets')::integer<>0
     or (v->>'staleTargets')::integer<>0
     or (v->>'runtimeFailures')::integer<>0
     or (v->>'unexpectedRuntimeStates')::integer<>0 then
    raise exception 'fully observed expected estate should pass: %',v;
  end if;
end;
$$;

insert into foundation.defence_estate_observations(
  target_id,runtime_state,health_state,observed_at,valid_until,
  evidence_kind,evidence_ref,metadata
) values (
  'railway:fish','failed','unhealthy',now()+interval '1 second',now()+interval '1 hour',
  'manual-verified','test:federation:fish-failure','{}'::jsonb
);

do $$
declare
  v jsonb;
begin
  select foundation.get_defence_estate_summary_v1() into v;
  if v->>'state'<>'fail'
     or (v->>'runtimeFailures')::integer<>1
     or (v->>'degradedOrUnhealthy')::integer<>1 then
    raise exception 'failed estate target should fail federation summary: %',v;
  end if;
end;
$$;

do $$
begin
  begin
    perform foundation.record_defence_estate_observation_v1(
      'railway:fish','active','unknown',null,null,null,now(),now()+interval '1 hour',
      'manual-verified','test:sensitive-estate-key',
      jsonb_build_object('token','must-not-be-stored')
    );
    raise exception 'sensitive estate metadata unexpectedly accepted';
  exception
    when sqlstate '22023' then
      null;
  end;
end;
$$;

do $$
begin
  begin
    update foundation.defence_estate_observations
       set evidence_ref='mutation-should-fail'
     where target_id='railway:fish';
    raise exception 'estate observation history unexpectedly mutated';
  exception
    when sqlstate '55000' then
      null;
  end;
end;
$$;

do $$
begin
  if has_table_privilege('anon','foundation.defence_estate_targets','SELECT')
     or has_table_privilege('authenticated','foundation.defence_estate_observations','SELECT') then
    raise exception 'public roles must not read Defence estate data';
  end if;

  if has_function_privilege('anon','foundation.get_defence_estate_summary_v1()','EXECUTE')
     or has_function_privilege('authenticated','foundation.record_defence_estate_observation_v1(text,text,text,text,text,text,timestamptz,timestamptz,text,text,jsonb)','EXECUTE') then
    raise exception 'public roles must not execute Defence estate functions';
  end if;

  if not has_function_privilege('foundation_runtime','foundation.get_defence_estate_summary_v1()','EXECUTE')
     or not has_function_privilege('shine_defence_runtime','foundation.record_defence_estate_observation_v1(text,text,text,text,text,text,timestamptz,timestamptz,text,text,jsonb)','EXECUTE') then
    raise exception 'internal Defence roles missing required estate privileges';
  end if;
end;
$$;

rollback;
