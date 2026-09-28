begin;

do $$
declare
  v jsonb;
begin
  select foundation.run_defence_sentinel_v1('production',now()) into v;
  if v->>'overallState'<>'pass'
     or (v->>'activeIncidentCount')::integer<>0
     or (v->>'incidentEventsCreated')::integer<>0 then
    raise exception 'clean Sentinel run should be quiet: %',v;
  end if;
end;
$$;

create table foundation.test_defence_sentinel_rls_gap(id integer);

do $$
declare
  v jsonb;
begin
  select foundation.run_defence_sentinel_v1('production',now()+interval '1 second') into v;
  if v->>'overallState'<>'fail'
     or (v->>'activeIncidentCount')::integer<>1
     or (v->>'incidentEventsCreated')::integer<>1 then
    raise exception 'RLS gap should open one incident: %',v;
  end if;

  if not exists (
    select 1
    from foundation.current_defence_incidents
    where environment='production'
      and domain='rls'
      and event_type='opened'
      and state='fail'
  ) then
    raise exception 'RLS incident was not opened';
  end if;
end;
$$;

do $$
declare
  before_events integer;
  after_events integer;
  v jsonb;
begin
  select count(*) into before_events
  from foundation.defence_incident_events
  where incident_key='production:rls';

  select foundation.run_defence_sentinel_v1('production',now()+interval '2 seconds') into v;

  select count(*) into after_events
  from foundation.defence_incident_events
  where incident_key='production:rls';

  if after_events<>before_events
     or (v->>'incidentEventsCreated')::integer<>0 then
    raise exception 'unchanged failure must not create incident noise: %',v;
  end if;
end;
$$;

alter table foundation.test_defence_sentinel_rls_gap enable row level security;
create policy test_defence_sentinel_rls_gap_deny
on foundation.test_defence_sentinel_rls_gap
as restrictive
for all
to anon,authenticated
using (false)
with check (false);

do $$
declare
  v jsonb;
  s jsonb;
begin
  select foundation.run_defence_sentinel_v1('production',now()+interval '3 seconds') into v;
  if v->>'overallState'<>'pass'
     or (v->>'activeIncidentCount')::integer<>0
     or (v->>'incidentEventsCreated')::integer<>1 then
    raise exception 'fixed RLS gap should create one recovery: %',v;
  end if;

  if not exists (
    select 1
    from foundation.current_defence_incident_state
    where incident_key='production:rls'
      and event_type='recovered'
      and state='pass'
  ) then
    raise exception 'RLS incident recovery missing';
  end if;

  select foundation.get_defence_sentinel_summary_v1('production') into s;
  if s->>'state'<>'pass'
     or (s->>'activeIncidentCount')::integer<>0
     or (s->>'stale')::boolean then
    raise exception 'Sentinel summary should be fresh/pass after recovery: %',s;
  end if;
end;
$$;

do $$
begin
  if has_table_privilege('anon','foundation.defence_incident_events','SELECT')
     or has_table_privilege('authenticated','foundation.current_defence_incidents','SELECT') then
    raise exception 'public roles must not read Sentinel incident data';
  end if;

  if has_function_privilege('anon','foundation.run_defence_sentinel_v1(text,timestamptz)','EXECUTE')
     or has_function_privilege('authenticated','foundation.get_defence_sentinel_summary_v1(text)','EXECUTE') then
    raise exception 'public roles must not execute Sentinel functions';
  end if;

  if not has_function_privilege('shine_defence_runtime','foundation.run_defence_sentinel_v1(text,timestamptz)','EXECUTE') then
    raise exception 'shine_defence_runtime must run Sentinel';
  end if;

  if not has_function_privilege('foundation_runtime','foundation.get_defence_sentinel_summary_v1(text)','EXECUTE') then
    raise exception 'foundation_runtime must read bounded Sentinel summary';
  end if;
end;
$$;

do $$
begin
  begin
    update foundation.defence_incident_events
       set evidence_ref='mutation-should-fail'
     where incident_key='production:rls';
    raise exception 'Sentinel incident history unexpectedly mutated';
  exception
    when sqlstate '55000' then
      null;
  end;
end;
$$;

rollback;
