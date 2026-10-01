begin;

create table public.grant_protocol (
  id bigint generated always as identity primary key,
  payload jsonb not null default '{}'::jsonb
);

create table public.grant_build_evidence (
  id bigint generated always as identity primary key,
  payload jsonb not null default '{}'::jsonb
);

alter table public.grant_protocol enable row level security;
alter table public.grant_build_evidence enable row level security;

insert into public.grant_protocol(payload) values ('{"kind":"protocol"}'::jsonb);
insert into public.grant_build_evidence(payload) values ('{"kind":"evidence"}'::jsonb);

\ir grant-rnd-client-deny-v1.sql

do $grant_rnd_policy_shape$
declare
  v_count integer;
begin
  select count(*) into v_count
  from pg_policy p
  join pg_class c on c.oid=p.polrelid
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public'
    and (
      (c.relname='grant_protocol' and p.polname='grant_protocol_client_deny')
      or
      (c.relname='grant_build_evidence' and p.polname='grant_build_evidence_client_deny')
    )
    and p.polpermissive=false
    and p.polcmd='*'
    and pg_get_expr(p.polqual,p.polrelid)='false'
    and pg_get_expr(p.polwithcheck,p.polrelid)='false';

  if v_count<>2 then
    raise exception 'grant/R&D restrictive client deny policy shape invalid: %',v_count;
  end if;
end;
$grant_rnd_policy_shape$;

-- Simulate a future accidental permissive client policy + grant. The
-- restrictive false boundary must still win.
create policy grant_protocol_test_allow
on public.grant_protocol
as permissive
for select
to anon, authenticated
using (true);

create policy grant_build_evidence_test_allow
on public.grant_build_evidence
as permissive
for select
to anon, authenticated
using (true);

grant select on public.grant_protocol to anon, authenticated;
grant select on public.grant_build_evidence to anon, authenticated;

set local role anon;
do $grant_rnd_anon$
begin
  if (select count(*) from public.grant_protocol)<>0
     or (select count(*) from public.grant_build_evidence)<>0 then
    raise exception 'anon escaped grant/R&D restrictive deny boundary';
  end if;
end;
$grant_rnd_anon$;
reset role;

set local role authenticated;
do $grant_rnd_authenticated$
begin
  if (select count(*) from public.grant_protocol)<>0
     or (select count(*) from public.grant_build_evidence)<>0 then
    raise exception 'authenticated escaped grant/R&D restrictive deny boundary';
  end if;
end;
$grant_rnd_authenticated$;
reset role;

rollback;
