-- Shine Defence active release-attestation authority state v1.
-- Time-fresh caller evidence is non-admissible once its signed reusable-workflow
-- authority no longer matches the active Defence authority.

create table foundation.defence_attestation_authority_activations (
  activation_sequence bigint generated always as identity primary key,
  authority_sha text not null
    check (authority_sha ~ '^[a-fA-F0-9]{40}$'),
  authority_ref text not null
    check (length(authority_ref) between 1 and 1024 and authority_ref !~ '[[:cntrl:]]'),
  workflow_blob_sha text not null
    check (workflow_blob_sha ~ '^[a-fA-F0-9]{40}$'),
  activation_kind text not null
    check (activation_kind in ('bootstrap','promotion','rollback')),
  activated_at timestamptz not null,
  evidence_ref text not null unique,
  metadata jsonb not null default '{}'::jsonb,
  recorded_at timestamptz not null default now(),
  check (jsonb_typeof(metadata)='object'),
  check (right(lower(authority_ref),41)='@'||lower(authority_sha))
);

alter table foundation.defence_attestation_authority_activations enable row level security;

create policy shine_defence_runtime_attestation_authority_select
on foundation.defence_attestation_authority_activations
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_attestation_authority_activations
  from public,anon,authenticated;
grant select on foundation.defence_attestation_authority_activations
  to foundation_runtime,shine_defence_runtime,service_role;
grant insert on foundation.defence_attestation_authority_activations
  to service_role;

create unique index defence_attestation_authority_activation_identity_idx
  on foundation.defence_attestation_authority_activations(
    lower(authority_sha),activated_at,activation_kind
  );

create index defence_attestation_authority_activation_time_idx
  on foundation.defence_attestation_authority_activations(
    activated_at desc,activation_sequence desc
  );

create trigger defence_attestation_authority_activations_append_only
before update or delete on foundation.defence_attestation_authority_activations
for each row execute function foundation.reject_append_only_mutation();

insert into foundation.defence_attestation_authority_activations(
  authority_sha,authority_ref,workflow_blob_sha,activation_kind,
  activated_at,evidence_ref,metadata
) values (
  '7bfd7fe685b4b2da814ac53dafdbfac2350591c8',
  'doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-release-attestation-v1.yml@7bfd7fe685b4b2da814ac53dafdbfac2350591c8',
  '71218df29b79919af76115b9180a6afbbd8dbf79',
  'bootstrap',
  '2026-09-30T06:58:39.000Z'::timestamptz,
  'shine-defence:attestation-authority:bootstrap:7bfd7fe685b4',
  jsonb_build_object(
    'contract','shine-defence/release-attestation-authority-state-v1',
    'source','security/shine-defence/release-attestation-authority-lineage-v1.json'
  )
)
on conflict (evidence_ref) do nothing;

create view foundation.current_defence_attestation_authority
with (security_invoker=true)
as
select
  activation_sequence,authority_sha,authority_ref,workflow_blob_sha,
  activation_kind,activated_at,evidence_ref,metadata,recorded_at
from foundation.defence_attestation_authority_activations
order by activated_at desc,activation_sequence desc
limit 1;

revoke all on foundation.current_defence_attestation_authority
  from public,anon,authenticated;
grant select on foundation.current_defence_attestation_authority
  to foundation_runtime,shine_defence_runtime,service_role;

create or replace function foundation.is_defence_release_source_authority_current_v1(
  p_metadata jsonb
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, foundation
as $$
  select coalesce((
    select
      jsonb_typeof(p_metadata)='object'
      and lower(coalesce(p_metadata->>'githubJobWorkflowSha',''))=lower(a.authority_sha)
      and coalesce(p_metadata->>'githubJobWorkflowRef','')=a.authority_ref
    from foundation.current_defence_attestation_authority a
  ),false);
$$;

revoke all on function foundation.is_defence_release_source_authority_current_v1(jsonb)
  from public,anon,authenticated;
grant execute on function foundation.is_defence_release_source_authority_current_v1(jsonb)
  to foundation_runtime,shine_defence_runtime,service_role;

create or replace function foundation.get_defence_release_authority_parity_summary_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_authority foundation.defence_attestation_authority_activations%rowtype;
  v_required integer := 0;
  v_aligned integer := 0;
  v_missing integer := 0;
  v_drift integer := 0;
  v_state text;
  v_attention jsonb := '[]'::jsonb;
begin
  select a.* into v_authority
  from foundation.defence_attestation_authority_activations a
  order by a.activated_at desc,a.activation_sequence desc
  limit 1;

  if v_authority.activation_sequence is null then
    return jsonb_build_object(
      'defenceReleaseAuthorityParity','shine-defence/release-authority-parity-v1',
      'schemaVersion','1.0.0',
      'state','warning',
      'reasonCode','active-attestation-authority-missing',
      'requiredTargets',0,
      'alignedTargets',0,
      'missingTargets',0,
      'driftedTargets',0,
      'attention','[]'::jsonb,
      'evaluatedAt',now()
    );
  end if;

  with x as (
    select
      t.target_id,
      t.metadata->>'sourceRepository' as repository,
      h.observation_id,
      h.observed_at,
      h.valid_until,
      h.metadata->>'githubJobWorkflowSha' as observed_authority_sha,
      h.metadata->>'githubJobWorkflowRef' as observed_authority_ref,
      foundation.is_defence_release_source_authority_current_v1(h.metadata) as authority_current
    from foundation.defence_estate_targets t
    left join foundation.current_defence_release_source_heads h using(target_id)
    where t.provider='railway'
      and t.lifecycle='active'
      and t.required_for_estate
  )
  select
    count(*),
    count(*) filter (where observation_id is not null and authority_current),
    count(*) filter (where observation_id is null),
    count(*) filter (where observation_id is not null and not authority_current)
  into v_required,v_aligned,v_missing,v_drift
  from x;

  with x as (
    select
      t.target_id,
      t.metadata->>'sourceRepository' as repository,
      h.observation_id,
      h.observed_at,
      h.valid_until,
      h.metadata->>'githubJobWorkflowSha' as observed_authority_sha,
      h.metadata->>'githubJobWorkflowRef' as observed_authority_ref,
      foundation.is_defence_release_source_authority_current_v1(h.metadata) as authority_current
    from foundation.defence_estate_targets t
    left join foundation.current_defence_release_source_heads h using(target_id)
    where t.provider='railway'
      and t.lifecycle='active'
      and t.required_for_estate
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'targetId',target_id,
      'repository',repository,
      'observedAt',observed_at,
      'validUntil',valid_until,
      'expectedAuthoritySha',lower(v_authority.authority_sha),
      'expectedAuthorityRef',v_authority.authority_ref,
      'observedAuthoritySha',observed_authority_sha,
      'observedAuthorityRef',observed_authority_ref,
      'reasonCode',case
        when observation_id is null then 'release-source-authority-evidence-missing'
        else 'release-source-authority-stale'
      end
    ) order by target_id
  ),'[]'::jsonb)
  into v_attention
  from x
  where observation_id is null or not authority_current;

  v_state := case when v_missing>0 or v_drift>0 then 'warning' else 'pass' end;

  return jsonb_build_object(
    'defenceReleaseAuthorityParity','shine-defence/release-authority-parity-v1',
    'schemaVersion','1.0.0',
    'state',v_state,
    'activeAuthority',jsonb_build_object(
      'authoritySha',lower(v_authority.authority_sha),
      'authorityRef',v_authority.authority_ref,
      'workflowBlobSha',lower(v_authority.workflow_blob_sha),
      'activationKind',v_authority.activation_kind,
      'activatedAt',v_authority.activated_at
    ),
    'requiredTargets',v_required,
    'alignedTargets',v_aligned,
    'missingTargets',v_missing,
    'driftedTargets',v_drift,
    'attention',v_attention,
    'evaluatedAt',now()
  );
end;
$$;

revoke all on function foundation.get_defence_release_authority_parity_summary_v1()
  from public,anon,authenticated;
grant execute on function foundation.get_defence_release_authority_parity_summary_v1()
  to foundation_runtime,shine_defence_runtime,service_role;
