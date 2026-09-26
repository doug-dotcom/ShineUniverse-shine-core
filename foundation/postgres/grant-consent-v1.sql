-- Shine Foundation explicit Vault grant consent v1
-- Layer 15: an authenticated, already-bound Shine identity may explicitly grant one
-- manifest-declared app scope over one Vault resource/category. No implicit grants.

create table if not exists foundation.grant_consent_events (
  consent_id uuid primary key,
  request_id uuid not null unique,
  owner_shine_id uuid not null,
  app_id text not null,
  scope text not null,
  purpose text not null,
  resource_id uuid,
  resource_category text not null,
  outcome text not null check (outcome in ('granted','already-granted','denied')),
  reason_code text not null,
  grant_id uuid references foundation.access_grants(grant_id),
  occurred_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists grant_consent_events_app_time_idx
  on foundation.grant_consent_events (app_id, occurred_at desc);
create index if not exists grant_consent_events_owner_time_idx
  on foundation.grant_consent_events (owner_shine_id, occurred_at desc);

alter table foundation.grant_consent_events enable row level security;
revoke all on foundation.grant_consent_events from public, anon, authenticated;
grant select on foundation.grant_consent_events to service_role;

drop policy if exists grant_consent_events_external_deny
  on foundation.grant_consent_events;
create policy grant_consent_events_external_deny
on foundation.grant_consent_events
for select
to anon, authenticated
using (false);

drop trigger if exists grant_consent_events_append_only
  on foundation.grant_consent_events;
create trigger grant_consent_events_append_only
before update or delete on foundation.grant_consent_events
for each row execute function foundation.reject_append_only_mutation();

create or replace function foundation.issue_access_grant_v1(
  p_consent_id uuid,
  p_grant_id uuid,
  p_request_id uuid,
  p_owner_shine_id uuid,
  p_app_id text,
  p_scope text,
  p_purpose text,
  p_resource_id uuid,
  p_resource_category text,
  p_occurred_at timestamptz
)
returns table(outcome text, reason_code text, grant_id uuid)
language plpgsql
security definer
set search_path = pg_catalog, foundation
as $$
declare
  prior foundation.grant_consent_events%rowtype;
  app_manifest jsonb;
  matched_grant_id uuid;
  result_outcome text;
  result_reason text;
begin
  select * into prior
  from foundation.grant_consent_events
  where request_id=p_request_id;

  if found then
    if prior.owner_shine_id<>p_owner_shine_id
      or prior.app_id<>p_app_id
      or prior.scope<>p_scope
      or prior.purpose<>p_purpose
      or prior.resource_id is distinct from p_resource_id
      or prior.resource_category<>p_resource_category then
      raise exception 'grant-consent-replay-conflict' using errcode='23505';
    end if;
    return query select prior.outcome,prior.reason_code,prior.grant_id;
    return;
  end if;

  if p_scope !~ '^[a-z0-9][a-z0-9._:-]*$'
    or p_purpose !~ '^[a-z0-9][a-z0-9._:-]*$'
    or p_resource_category !~ '^[a-z0-9][a-z0-9._-]*$' then
    result_outcome:='denied';
    result_reason:='invalid-grant-request';
  else
    perform 1 from foundation.shine_identities
    where shine_id=p_owner_shine_id and account_state='active'
    for update;

    if not found then
      result_outcome:='denied';
      result_reason:='identity-unverified';
    else
      select manifest into app_manifest
      from foundation.app_registry
      where app_id=p_app_id and status='active';

      if app_manifest is null then
        result_outcome:='denied';
        result_reason:='app-unregistered';
      elsif not exists (
        select 1
        from pg_catalog.jsonb_array_elements(
          coalesce(app_manifest #> '{foundation,requestedScopes}','[]'::jsonb)
        ) as s(value)
        where s.value->>'scope'=p_scope
          and s.value->>'purpose'=p_purpose
          and s.value->>'resourceCategory'=p_resource_category
      ) then
        result_outcome:='denied';
        result_reason:='scope-not-declared';
      elsif p_resource_id is not null and not exists (
        select 1 from foundation.vault_resources
        where resource_id=p_resource_id
          and owner_shine_id=p_owner_shine_id
          and category=p_resource_category
      ) then
        result_outcome:='denied';
        result_reason:='resource-owner-mismatch';
      elsif p_resource_id is null and not exists (
        select 1 from foundation.vault_resources
        where owner_shine_id=p_owner_shine_id
          and category=p_resource_category
      ) then
        result_outcome:='denied';
        result_reason:='resource-not-found';
      else
        select g.grant_id into matched_grant_id
        from foundation.effective_access_grants g
        where g.owner_shine_id=p_owner_shine_id
          and g.app_id=p_app_id
          and g.scope=p_scope
          and g.purpose=p_purpose
          and g.effective_status='active'
          and (
            (p_resource_id is not null and g.resource_id=p_resource_id)
            or
            (p_resource_id is null and g.resource_id is null and g.resource_category=p_resource_category)
          )
        order by g.issued_at desc
        limit 1;

        if matched_grant_id is not null then
          result_outcome:='already-granted';
          result_reason:='grant-already-active';
        else
          insert into foundation.access_grants(
            grant_id,owner_shine_id,app_id,scope,purpose,
            resource_id,resource_category,status,issued_at,
            consent_method,consent_recorded_at,consent_evidence_ref
          ) values (
            p_grant_id,p_owner_shine_id,p_app_id,p_scope,p_purpose,
            p_resource_id,p_resource_category,'active',p_occurred_at,
            'explicit-user',p_occurred_at,
            'foundation://grant-consent/'||p_consent_id::text
          );
          matched_grant_id:=p_grant_id;
          result_outcome:='granted';
          result_reason:='grant-consent-recorded';
        end if;
      end if;
    end if;
  end if;

  insert into foundation.grant_consent_events(
    consent_id,request_id,owner_shine_id,app_id,scope,purpose,
    resource_id,resource_category,outcome,reason_code,grant_id,occurred_at
  ) values (
    p_consent_id,p_request_id,p_owner_shine_id,p_app_id,p_scope,p_purpose,
    p_resource_id,p_resource_category,result_outcome,result_reason,matched_grant_id,p_occurred_at
  );

  return query select result_outcome,result_reason,matched_grant_id;
end;
$$;

revoke all on function foundation.issue_access_grant_v1(
  uuid,uuid,uuid,uuid,text,text,text,uuid,text,timestamptz
) from public, anon, authenticated, service_role;
grant execute on function foundation.issue_access_grant_v1(
  uuid,uuid,uuid,uuid,text,text,text,uuid,text,timestamptz
) to foundation_runtime;

create or replace view foundation.app_connection_status
with (security_invoker = true)
as
with credential_counts as (
  select app_id,count(*) filter (where effective_status='active')::int as active_credentials
  from foundation.effective_app_credentials group by app_id
),
provider_counts as (
  select app_id,count(*) filter (where status='active')::int as active_identity_providers
  from foundation.app_identity_providers group by app_id
),
claim_provider_counts as (
  select app_id,count(*) filter (where status='active')::int as active_claim_identity_providers
  from foundation.app_claim_identity_providers group by app_id
),
claim_counts as (
  select app_id,
    count(*) filter (where outcome in ('linked','already-linked'))::int as successful_identity_claims,
    max(occurred_at) filter (where outcome in ('linked','already-linked')) as last_identity_claim_at
  from foundation.identity_claim_events group by app_id
),
consent_counts as (
  select app_id,
    count(*) filter (where outcome in ('granted','already-granted'))::int as successful_grant_consents,
    max(occurred_at) filter (where outcome in ('granted','already-granted')) as last_grant_consent_at
  from foundation.grant_consent_events group by app_id
),
grant_counts as (
  select app_id,count(*) filter (where effective_status='active')::int as active_grants
  from foundation.effective_access_grants group by app_id
),
audit_counts as (
  select app_id,
    count(*) filter (where decision='allow')::int as observed_allows,
    count(*) filter (where decision='deny')::int as observed_denies,
    max(occurred_at) as last_observed_at
  from foundation.access_audit_events group by app_id
),
last_audit as (
  select distinct on (app_id) app_id,decision as last_decision,reason_code as last_reason_code
  from foundation.access_audit_events order by app_id,occurred_at desc,created_at desc
)
select
  r.app_id,r.manifest->>'name' as app_name,r.status as registry_status,
  coalesce((r.manifest #>> '{foundation,standalonePrimaryPurposeAvailable}')::boolean,false)
    as standalone_primary_purpose_available,
  coalesce(c.active_credentials,0) as active_credentials,
  coalesce(p.active_identity_providers,0) as active_identity_providers,
  coalesce(g.active_grants,0) as active_grants,
  coalesce(a.observed_allows,0) as observed_allows,
  coalesce(a.observed_denies,0) as observed_denies,
  a.last_observed_at,l.last_decision,l.last_reason_code,
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
  ic.last_identity_claim_at,
  coalesce(gc.successful_grant_consents,0) as successful_grant_consents,
  gc.last_grant_consent_at
from foundation.app_registry r
left join credential_counts c on c.app_id=r.app_id
left join provider_counts p on p.app_id=r.app_id
left join claim_provider_counts cp on cp.app_id=r.app_id
left join claim_counts ic on ic.app_id=r.app_id
left join consent_counts gc on gc.app_id=r.app_id
left join grant_counts g on g.app_id=r.app_id
left join audit_counts a on a.app_id=r.app_id
left join last_audit l on l.app_id=r.app_id;

revoke all on foundation.app_connection_status from public, anon, authenticated;
grant select on foundation.app_connection_status to service_role;
