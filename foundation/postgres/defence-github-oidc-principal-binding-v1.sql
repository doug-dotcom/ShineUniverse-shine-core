-- Shine Defence immutable GitHub OIDC repository principal binding v1.
-- Repository names remain human-readable evidence, but authorization binds the
-- release source to GitHub's immutable repository/owner IDs.

with source(target_id,repository,repository_id,owner_name,owner_id) as (
  values
    ('railway:daash','doug-dotcom/Shine-DaAsh','1373763946','doug-dotcom','225530237'),
    ('railway:dive','doug-dotcom/shine-dive-','1361439227','doug-dotcom','225530237'),
    ('railway:dnd','doug-dotcom/shine-D-D','1384280308','doug-dotcom','225530237'),
    ('railway:fiona','doug-dotcom/Fiona-Finance','1357712835','doug-dotcom','225530237'),
    ('railway:fish','doug-dotcom/shine-fish','1384278684','doug-dotcom','225530237'),
    ('railway:my-money','doug-dotcom/shine-my-money-','1378329747','doug-dotcom','225530237'),
    ('railway:project-l','doug-dotcom/Project-L-Modular','1240491225','doug-dotcom','225530237'),
    ('railway:punt49','doug-dotcom/Punt-49','1359524189','doug-dotcom','225530237'),
    ('railway:recovery-companion','doug-dotcom/Project-RC','1354993812','doug-dotcom','225530237'),
    ('railway:rivers','doug-dotcom/shine-music','1377780406','doug-dotcom','225530237'),
    ('railway:shine-ai','doug-dotcom/Shine-Ai','1386493862','doug-dotcom','225530237'),
    ('railway:ski','doug-dotcom/Shine-Ski','1359646182','doug-dotcom','225530237'),
    ('railway:translate','doug-dotcom/shine-translate','1368992845','doug-dotcom','225530237'),
    ('railway:travel','doug-dotcom/shine-travel','1361434212','doug-dotcom','225530237')
)
update foundation.defence_estate_targets t
set metadata=t.metadata || jsonb_build_object(
  'sourceRepositoryId',source.repository_id,
  'sourceRepositoryOwner',source.owner_name,
  'sourceRepositoryOwnerId',source.owner_id,
  'oidcPrincipalBindingContract','shine-defence/github-oidc-immutable-principal-v1'
),
updated_at=clock_timestamp()
from source
where t.target_id=source.target_id
  and t.provider='railway'
  and t.lifecycle='active'
  and lower(t.metadata->>'sourceRepository')=lower(source.repository);

create or replace function foundation.get_defence_oidc_principal_binding_summary_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $principal$
declare
  v_required integer;
  v_bound integer;
  v_duplicate_ids integer;
  v_wrong_owner integer;
  v_identity_mismatch integer;
begin
  select count(*) into v_required
  from foundation.defence_estate_targets
  where provider='railway'
    and lifecycle='active'
    and required_for_estate;

  select count(*) into v_bound
  from foundation.defence_estate_targets
  where provider='railway'
    and lifecycle='active'
    and required_for_estate
    and metadata->>'sourceRepositoryId' ~ '^[0-9]{1,20}$'
    and metadata->>'sourceRepositoryOwner'='doug-dotcom'
    and metadata->>'sourceRepositoryOwnerId'='225530237'
    and metadata->>'oidcPrincipalBindingContract'='shine-defence/github-oidc-immutable-principal-v1';

  select count(*) into v_duplicate_ids
  from (
    select metadata->>'sourceRepositoryId'
    from foundation.defence_estate_targets
    where provider='railway'
      and lifecycle='active'
      and required_for_estate
      and metadata ? 'sourceRepositoryId'
    group by metadata->>'sourceRepositoryId'
    having count(*)>1
  ) x;

  select count(*) into v_wrong_owner
  from foundation.defence_estate_targets
  where provider='railway'
    and lifecycle='active'
    and required_for_estate
    and (
      metadata->>'sourceRepositoryOwner' is distinct from 'doug-dotcom'
      or metadata->>'sourceRepositoryOwnerId' is distinct from '225530237'
    );

  select count(*) into v_identity_mismatch
  from foundation.defence_estate_targets t
  join (
    values
      ('railway:daash','1373763946'),
      ('railway:dive','1361439227'),
      ('railway:dnd','1384280308'),
      ('railway:fiona','1357712835'),
      ('railway:fish','1384278684'),
      ('railway:my-money','1378329747'),
      ('railway:project-l','1240491225'),
      ('railway:punt49','1359524189'),
      ('railway:recovery-companion','1354993812'),
      ('railway:rivers','1377780406'),
      ('railway:shine-ai','1386493862'),
      ('railway:ski','1359646182'),
      ('railway:translate','1368992845'),
      ('railway:travel','1361434212')
  ) expected(target_id,repository_id) using(target_id)
  where t.provider='railway'
    and t.lifecycle='active'
    and t.required_for_estate
    and t.metadata->>'sourceRepositoryId' is distinct from expected.repository_id;

  return jsonb_build_object(
    'defenceOidcPrincipalBindingSummary','shine-defence/github-oidc-principal-binding-summary-v1',
    'schemaVersion','1.0.0',
    'state',case
      when v_required=14 and v_bound=14 and v_duplicate_ids=0 and v_wrong_owner=0 and v_identity_mismatch=0 then 'pass'
      else 'fail'
    end,
    'requiredTargets',v_required,
    'boundTargets',v_bound,
    'duplicateRepositoryIds',v_duplicate_ids,
    'wrongOwnerTargets',v_wrong_owner,
    'repositoryIdMismatches',v_identity_mismatch,
    'owner','doug-dotcom',
    'ownerId','225530237'
  );
end;
$principal$;

revoke all on function foundation.get_defence_oidc_principal_binding_summary_v1()
  from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_defence_oidc_principal_binding_summary_v1()
  to foundation_runtime,shine_defence_runtime,service_role;
