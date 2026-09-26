-- Shine Foundation identity claim v1
-- Layer 14: explicit two-proof linking of an unbound app session to canonical Shine ID.

create table if not exists foundation.app_claim_identity_providers (
  app_id text not null references foundation.app_registry(app_id),
  provider_id text not null references foundation.identity_providers(provider_id),
  status text not null default 'active'
    check (status in ('active','disabled')),
  linked_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (app_id, provider_id)
);

create index if not exists app_claim_identity_providers_provider_idx
  on foundation.app_claim_identity_providers (provider_id);

alter table foundation.app_claim_identity_providers enable row level security;

revoke all on foundation.app_claim_identity_providers from public, anon, authenticated;
grant select, insert, update on foundation.app_claim_identity_providers to service_role;
grant select on foundation.app_claim_identity_providers to foundation_runtime;

drop policy if exists foundation_runtime_app_claim_identity_providers_select
  on foundation.app_claim_identity_providers;
create policy foundation_runtime_app_claim_identity_providers_select
on foundation.app_claim_identity_providers
for select
to foundation_runtime
using (status='active');

create table if not exists foundation.identity_claim_events (
  claim_id uuid primary key,
  request_id uuid not null unique,
  app_id text not null references foundation.app_registry(app_id),
  source_provider_id text not null references foundation.identity_providers(provider_id),
  source_provider_subject text not null
    check (length(source_provider_subject) between 1 and 512),
  target_provider_id text not null references foundation.identity_providers(provider_id),
  target_provider_subject text not null
    check (length(target_provider_subject) between 1 and 512),
  target_shine_id uuid not null references foundation.shine_identities(shine_id),
  outcome text not null
    check (outcome in ('linked','already-linked','denied')),
  reason_code text not null,
  occurred_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists identity_claim_events_app_time_idx
  on foundation.identity_claim_events (app_id, occurred_at desc);

create index if not exists identity_claim_events_target_time_idx
  on foundation.identity_claim_events (target_shine_id, occurred_at desc);

alter table foundation.identity_claim_events enable row level security;

revoke all on foundation.identity_claim_events from public, anon, authenticated;
grant select on foundation.identity_claim_events to service_role;

drop trigger if exists identity_claim_events_append_only
  on foundation.identity_claim_events;
create trigger identity_claim_events_append_only
before update or delete on foundation.identity_claim_events
for each row execute function foundation.reject_append_only_mutation();

create or replace function foundation.complete_identity_claim_v1(
  p_claim_id uuid,
  p_request_id uuid,
  p_app_id text,
  p_source_provider_id text,
  p_source_provider_subject text,
  p_target_provider_id text,
  p_target_provider_subject text,
  p_target_shine_id uuid,
  p_occurred_at timestamptz
)
returns table(outcome text, reason_code text)
language plpgsql
security definer
set search_path = pg_catalog, foundation
as $$
declare
  existing_shine_id uuid;
  prior foundation.identity_claim_events%rowtype;
  result_outcome text;
  result_reason text;
begin
  select * into prior
  from foundation.identity_claim_events
  where request_id=p_request_id;

  if found then
    if prior.app_id<>p_app_id
      or prior.source_provider_id<>p_source_provider_id
      or prior.source_provider_subject<>p_source_provider_subject
      or prior.target_provider_id<>p_target_provider_id
      or prior.target_provider_subject<>p_target_provider_subject
      or prior.target_shine_id<>p_target_shine_id then
      raise exception 'identity-claim-replay-conflict' using errcode='23505';
    end if;
    return query select prior.outcome,prior.reason_code;
    return;
  end if;

  if p_occurred_at is null
    or p_occurred_at < now() - interval '5 minutes'
    or p_occurred_at > now() + interval '1 minute'
    or length(p_source_provider_subject) not between 1 and 512
    or length(p_target_provider_subject) not between 1 and 512
  then
    result_outcome:='denied';
    result_reason:='claim-context-invalid';
  elsif not exists (
    select 1 from foundation.app_registry
    where app_id=p_app_id and status='active'
  ) then
    result_outcome:='denied';
    result_reason:='app-unregistered';
  elsif not exists (
    select 1 from foundation.app_identity_providers
    where app_id=p_app_id
      and provider_id=p_source_provider_id
      and status='active'
  ) then
    result_outcome:='denied';
    result_reason:='source-provider-not-approved';
  elsif not exists (
    select 1 from foundation.app_claim_identity_providers
    where app_id=p_app_id
      and provider_id=p_target_provider_id
      and status='active'
  ) then
    result_outcome:='denied';
    result_reason:='target-provider-not-approved';
  elsif not exists (
    select 1
    from foundation.identity_bindings b
    join foundation.shine_identities i on i.shine_id=b.shine_id
    where b.provider=p_target_provider_id
      and b.provider_subject=p_target_provider_subject
      and b.shine_id=p_target_shine_id
      and b.verified_at is not null
      and i.account_state='active'
  ) then
    result_outcome:='denied';
    result_reason:='target-identity-unverified';
  else
    select shine_id into existing_shine_id
    from foundation.identity_bindings
    where provider=p_source_provider_id
      and provider_subject=p_source_provider_subject;

    if existing_shine_id is null then
      begin
        insert into foundation.identity_bindings(
          provider,provider_subject,shine_id,verified_at
        ) values (
          p_source_provider_id,
          p_source_provider_subject,
          p_target_shine_id,
          p_occurred_at
        );
        result_outcome:='linked';
        result_reason:='identity-claim-linked';
      exception when unique_violation then
        select shine_id into existing_shine_id
        from foundation.identity_bindings
        where provider=p_source_provider_id
          and provider_subject=p_source_provider_subject;

        if existing_shine_id=p_target_shine_id then
          result_outcome:='already-linked';
          result_reason:='identity-claim-already-linked';
        else
          result_outcome:='denied';
          result_reason:='source-already-bound';
        end if;
      end;
    elsif existing_shine_id=p_target_shine_id then
      result_outcome:='already-linked';
      result_reason:='identity-claim-already-linked';
    else
      result_outcome:='denied';
      result_reason:='source-already-bound';
    end if;
  end if;

  insert into foundation.identity_claim_events(
    claim_id,request_id,app_id,
    source_provider_id,source_provider_subject,
    target_provider_id,target_provider_subject,target_shine_id,
    outcome,reason_code,occurred_at
  ) values (
    p_claim_id,p_request_id,p_app_id,
    p_source_provider_id,p_source_provider_subject,
    p_target_provider_id,p_target_provider_subject,p_target_shine_id,
    result_outcome,result_reason,p_occurred_at
  );

  return query select result_outcome,result_reason;
end;
$$;

revoke all on function foundation.complete_identity_claim_v1(
  uuid,uuid,text,text,text,text,text,uuid,timestamptz
) from public, anon, authenticated;

grant execute on function foundation.complete_identity_claim_v1(
  uuid,uuid,text,text,text,text,text,uuid,timestamptz
) to foundation_runtime;

create or replace view foundation.app_connection_status
with (security_invoker = true)
as
with credential_counts as (
  select app_id,
    count(*) filter (where effective_status='active')::int as active_credentials
  from foundation.effective_app_credentials
  group by app_id
),
provider_counts as (
  select app_id,
    count(*) filter (where status='active')::int as active_identity_providers
  from foundation.app_identity_providers
  group by app_id
),
claim_provider_counts as (
  select app_id,
    count(*) filter (where status='active')::int as active_claim_identity_providers
  from foundation.app_claim_identity_providers
  group by app_id
),
claim_counts as (
  select app_id,
    count(*) filter (where outcome in ('linked','already-linked'))::int as successful_identity_claims,
    max(occurred_at) filter (where outcome in ('linked','already-linked')) as last_identity_claim_at
  from foundation.identity_claim_events
  group by app_id
),
grant_counts as (
  select app_id,
    count(*) filter (where effective_status='active')::int as active_grants
  from foundation.effective_access_grants
  group by app_id
),
audit_counts as (
  select app_id,
    count(*) filter (where decision='allow')::int as observed_allows,
    count(*) filter (where decision='deny')::int as observed_denies,
    max(occurred_at) as last_observed_at
  from foundation.access_audit_events
  group by app_id
),
last_audit as (
  select distinct on (app_id)
    app_id,
    decision as last_decision,
    reason_code as last_reason_code
  from foundation.access_audit_events
  order by app_id,occurred_at desc,created_at desc
)
select
  r.app_id,
  r.manifest->>'name' as app_name,
  r.status as registry_status,
  coalesce((r.manifest #>> '{foundation,standalonePrimaryPurposeAvailable}')::boolean,false)
    as standalone_primary_purpose_available,
  coalesce(c.active_credentials,0) as active_credentials,
  coalesce(p.active_identity_providers,0) as active_identity_providers,
  coalesce(g.active_grants,0) as active_grants,
  coalesce(a.observed_allows,0) as observed_allows,
  coalesce(a.observed_denies,0) as observed_denies,
  a.last_observed_at,
  l.last_decision,
  l.last_reason_code,
  case
    when r.status<>'active' then 'disabled'
    when coalesce(c.active_credentials,0)=0 then 'registered'
    when coalesce(p.active_identity_providers,0)=0 then 'credentialed'
    when coalesce(g.active_grants,0)=0 then 'identity-ready'
    when coalesce(a.observed_allows,0)=0 then 'grant-ready'
    else 'live-observed'
  end as connection_state,
  coalesce(cp.active_claim_identity_providers,0) as active_claim_identity_providers,
  coalesce(ic.successful_identity_claims,0) as successful_identity_claims,
  ic.last_identity_claim_at
from foundation.app_registry r
left join credential_counts c on c.app_id=r.app_id
left join provider_counts p on p.app_id=r.app_id
left join claim_provider_counts cp on cp.app_id=r.app_id
left join claim_counts ic on ic.app_id=r.app_id
left join grant_counts g on g.app_id=r.app_id
left join audit_counts a on a.app_id=r.app_id
left join last_audit l on l.app_id=r.app_id;

revoke all on foundation.app_connection_status from public, anon, authenticated;
grant select on foundation.app_connection_status to service_role;
