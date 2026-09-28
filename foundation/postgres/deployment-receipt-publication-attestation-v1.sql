-- Foundation Layer 33: deployment receipt publication attestation.
-- Preserve immutable deployment identity while recording every accepted publication/re-attestation event.

create table foundation.service_deployment_receipt_publications (
  publication_sequence bigint generated always as identity primary key,
  publication_id uuid not null unique default gen_random_uuid(),
  publication_key text not null unique,
  receipt_id uuid not null references foundation.service_deployment_receipts(receipt_id),
  service_id text not null references foundation.service_registry(service_id),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  provider text not null
    check (provider in ('supabase-edge','railway','manual-verified')),
  runtime_version text not null,
  artifact_sha256 text not null
    check (artifact_sha256 ~ '^[a-fA-F0-9]{64}$'),
  source_ref text not null
    check (source_ref ~ '^github://[^/]+/[^/]+/commit/[a-fA-F0-9]{40}$'),
  provider_evidence_ref text not null,
  publication_outcome text not null
    check (publication_outcome in ('accepted-new','replayed-existing')),
  submitted_by text not null,
  transport text not null,
  transport_run_id text,
  transport_run_attempt text,
  transport_event text,
  transport_repository text,
  transport_ref text,
  transport_workflow_ref text,
  transport_workflow_sha text,
  rollback boolean not null default false,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  published_at timestamptz not null default now()
);

alter table foundation.service_deployment_receipt_publications enable row level security;

create policy foundation_runtime_service_deployment_receipt_publications_select
on foundation.service_deployment_receipt_publications
for select
to foundation_runtime
using (true);

revoke all on foundation.service_deployment_receipt_publications
  from public,anon,authenticated,foundation_gateway;
grant select on foundation.service_deployment_receipt_publications
  to foundation_runtime;
grant select,insert on foundation.service_deployment_receipt_publications
  to service_role;

create index service_deployment_receipt_publications_receipt_idx
  on foundation.service_deployment_receipt_publications(
    receipt_id,published_at desc,publication_sequence desc
  );

create index service_deployment_receipt_publications_service_idx
  on foundation.service_deployment_receipt_publications(
    service_id,environment,published_at desc
  );

create trigger service_deployment_receipt_publications_append_only
before update or delete on foundation.service_deployment_receipt_publications
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_service_deployment_receipt_publication
with (security_invoker=true)
as
select distinct on (service_id,environment)
  publication_sequence,
  publication_id,
  publication_key,
  receipt_id,
  service_id,
  environment,
  provider,
  runtime_version,
  artifact_sha256,
  source_ref,
  provider_evidence_ref,
  publication_outcome,
  submitted_by,
  transport,
  transport_run_id,
  transport_run_attempt,
  transport_event,
  transport_repository,
  transport_ref,
  transport_workflow_ref,
  transport_workflow_sha,
  rollback,
  metadata,
  published_at
from foundation.service_deployment_receipt_publications
order by
  service_id,environment,published_at desc,publication_sequence desc;

revoke all on foundation.current_service_deployment_receipt_publication
  from public,anon,authenticated,foundation_gateway;
grant select on foundation.current_service_deployment_receipt_publication
  to foundation_runtime;


create or replace function foundation.get_deployment_receipt_publication_health_v1(
  p_service_id text,
  p_environment text default 'production',
  p_max_age_seconds integer default 86400
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, foundation
as $layer33$
declare
  v_receipt foundation.service_deployment_receipts%rowtype;
  v_publication foundation.service_deployment_receipt_publications%rowtype;
  v_age_seconds numeric;
  v_state text;
  v_reason text;
  v_assurance text;
begin
  if p_max_age_seconds<60 or p_max_age_seconds>2592000 then
    raise exception 'deployment-publication-health-window-invalid';
  end if;

  select * into v_receipt
  from foundation.current_service_deployment_receipt
  where service_id=p_service_id
    and environment=p_environment;

  if v_receipt.receipt_id is null then
    return jsonb_build_object(
      'deploymentReceiptPublicationHealthResponse',
      'shine-foundation/deployment-receipt-publication-health-response-v1',
      'schemaVersion','1.0.0',
      'serviceId',p_service_id,
      'environment',p_environment,
      'state','unknown',
      'assurance','none',
      'reasonCode','deployment-receipt-missing',
      'publication',null
    );
  end if;

  select * into v_publication
  from foundation.service_deployment_receipt_publications
  where receipt_id=v_receipt.receipt_id
  order by published_at desc,publication_sequence desc
  limit 1;

  if v_publication.publication_id is null then
    return jsonb_build_object(
      'deploymentReceiptPublicationHealthResponse',
      'shine-foundation/deployment-receipt-publication-health-response-v1',
      'schemaVersion','1.0.0',
      'serviceId',p_service_id,
      'environment',p_environment,
      'state','unknown',
      'assurance','none',
      'reasonCode','publication-attestation-missing',
      'receiptId',v_receipt.receipt_id,
      'publication',null
    );
  end if;

  v_age_seconds := greatest(
    0,
    extract(epoch from (now()-v_publication.published_at))
  );

  v_assurance := case
    when v_publication.transport='github-oidc'
      and v_publication.submitted_by='github-actions-oidc'
      and v_publication.transport_repository='doug-dotcom/ShineUniverse-shine-core'
      and v_publication.transport_ref='refs/heads/main'
      then 'github-oidc'
    when v_publication.transport='github-actions-workflow-dispatch'
      then 'github-secret-workflow'
    else 'manual-or-other'
  end;

  if v_age_seconds>p_max_age_seconds then
    v_state := 'degraded';
    v_reason := 'publication-attestation-stale';
  elsif v_assurance='github-oidc' then
    v_state := 'pass';
    v_reason := 'publication-attested-by-github-oidc';
  else
    v_state := 'degraded';
    v_reason := 'publication-attestation-not-oidc';
  end if;

  return jsonb_build_object(
    'deploymentReceiptPublicationHealthResponse',
    'shine-foundation/deployment-receipt-publication-health-response-v1',
    'schemaVersion','1.0.0',
    'serviceId',p_service_id,
    'environment',p_environment,
    'state',v_state,
    'assurance',v_assurance,
    'reasonCode',v_reason,
    'receiptId',v_receipt.receipt_id,
    'runtimeVersion',v_receipt.runtime_version,
    'artifactSha256',v_receipt.artifact_sha256,
    'sourceRef',v_receipt.source_ref,
    'publication',jsonb_build_object(
      'publicationId',v_publication.publication_id,
      'publicationOutcome',v_publication.publication_outcome,
      'submittedBy',v_publication.submitted_by,
      'transport',v_publication.transport,
      'transportRunId',v_publication.transport_run_id,
      'transportRunAttempt',v_publication.transport_run_attempt,
      'transportEvent',v_publication.transport_event,
      'transportRepository',v_publication.transport_repository,
      'transportRef',v_publication.transport_ref,
      'transportWorkflowRef',v_publication.transport_workflow_ref,
      'transportWorkflowSha',v_publication.transport_workflow_sha,
      'rollback',v_publication.rollback,
      'publishedAt',v_publication.published_at,
      'ageSeconds',round(v_age_seconds,3)
    )
  );
end;
$layer33$;

revoke all on function foundation.get_deployment_receipt_publication_health_v1(
  text,text,integer
) from public,anon,authenticated;
grant execute on function foundation.get_deployment_receipt_publication_health_v1(
  text,text,integer
) to foundation_runtime;


create or replace function foundation.submit_service_deployment_receipt_v1(
  p_service_id text,
  p_environment text,
  p_provider text,
  p_runtime_ref text,
  p_runtime_version text,
  p_artifact_sha256 text,
  p_runtime_state text,
  p_source_ref text,
  p_provider_evidence_ref text,
  p_provider_observed_at timestamptz,
  p_submitted_by text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer33$
declare
  v_service foundation.service_registry%rowtype;
  v_existing foundation.service_deployment_receipts%rowtype;
  v_current_expectation foundation.service_deployment_expectations%rowtype;
  v_runtime_ref text;
  v_receipt_id uuid;
  v_expectation_evidence text;
  v_observation_evidence text;
  v_publication_id uuid;
  v_publication_key text;
  v_publication_outcome text;
  v_transport text;
  v_transport_run_id text;
  v_transport_run_attempt text;
  v_transport_event text;
  v_transport_repository text;
  v_transport_ref text;
  v_transport_workflow_ref text;
  v_transport_workflow_sha text;
  v_rollback boolean;
  v_result_status text;
begin
  select * into v_service
  from foundation.service_registry
  where service_id=p_service_id
    and lifecycle='active';

  if v_service.service_id is null then
    raise exception 'deployment-receipt-service-unknown';
  end if;

  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$' then
    raise exception 'deployment-receipt-environment-invalid';
  end if;

  if p_provider not in ('supabase-edge','railway','manual-verified') then
    raise exception 'deployment-receipt-provider-invalid';
  end if;

  if p_runtime_version is null or char_length(p_runtime_version)>128 then
    raise exception 'deployment-receipt-version-invalid';
  end if;

  if p_artifact_sha256 is null
     or p_artifact_sha256 !~ '^[a-fA-F0-9]{64}$' then
    raise exception 'deployment-receipt-artifact-invalid';
  end if;

  if p_runtime_state not in ('active','inactive','failed') then
    raise exception 'deployment-receipt-state-invalid';
  end if;

  if p_source_ref is null
     or p_source_ref !~ '^github://[^/]+/[^/]+/commit/[a-fA-F0-9]{40}$' then
    raise exception 'deployment-receipt-source-invalid';
  end if;

  if p_provider_evidence_ref is null
     or char_length(p_provider_evidence_ref)>1000 then
    raise exception 'deployment-receipt-evidence-invalid';
  end if;

  if p_provider_observed_at is null
     or p_provider_observed_at>now()+interval '5 minutes'
     or p_provider_observed_at<now()-interval '30 days' then
    raise exception 'deployment-receipt-observed-at-invalid';
  end if;

  if p_submitted_by is null
     or p_submitted_by !~ '^[a-z0-9][a-z0-9._:-]*$' then
    raise exception 'deployment-receipt-submitter-invalid';
  end if;

  if p_metadata is null
     or jsonb_typeof(p_metadata)<>'object'
     or pg_column_size(p_metadata)>16384 then
    raise exception 'deployment-receipt-metadata-invalid';
  end if;

  v_runtime_ref := case
    when p_service_id='foundation.gateway'
         and p_provider='supabase-edge'
      then 'supabase://sjpxqeyewahraxvidvcc/functions/foundation-gateway'
    else p_runtime_ref
  end;

  if p_service_id='foundation.gateway'
     and p_provider='supabase-edge'
     and p_runtime_ref<>v_runtime_ref then
    raise exception 'deployment-receipt-runtime-ref-mismatch';
  end if;

  v_transport := coalesce(nullif(p_metadata->>'transport',''),'unspecified');
  v_transport_run_id := nullif(p_metadata->>'githubRunId','');
  v_transport_run_attempt := nullif(p_metadata->>'githubRunAttempt','');
  v_transport_event := nullif(p_metadata->>'githubEvent','');
  v_transport_repository := nullif(p_metadata->>'githubRepository','');
  v_transport_ref := nullif(p_metadata->>'githubRef','');
  v_transport_workflow_ref := nullif(p_metadata->>'githubWorkflowRef','');
  v_transport_workflow_sha := nullif(p_metadata->>'githubWorkflowSha','');
  v_rollback := coalesce((p_metadata->>'rollback')::boolean,false);

  select * into v_existing
  from foundation.service_deployment_receipts
  where service_id=p_service_id
    and environment=p_environment
    and runtime_version=p_runtime_version
    and lower(artifact_sha256)=lower(p_artifact_sha256)
    and source_ref=p_source_ref;

  if v_existing.receipt_id is not null then
    v_receipt_id := v_existing.receipt_id;
    v_publication_outcome := 'replayed-existing';
    v_result_status := 'replayed';
  else
    select * into v_current_expectation
    from foundation.current_service_deployment_expectations
    where service_id=p_service_id
      and environment=p_environment;

    if v_current_expectation.expectation_id is not null
       and v_current_expectation.expected_version is not null
       and p_runtime_version ~ '^[0-9]+$'
       and v_current_expectation.expected_version ~ '^[0-9]+$'
       and p_runtime_version::numeric < v_current_expectation.expected_version::numeric
       and not v_rollback then
      raise exception 'deployment-receipt-version-regression';
    end if;

    insert into foundation.service_deployment_receipts(
      service_id,environment,provider,runtime_ref,runtime_version,
      artifact_sha256,runtime_state,source_ref,provider_evidence_ref,
      provider_observed_at,submitted_by,metadata
    )
    values (
      p_service_id,p_environment,p_provider,v_runtime_ref,p_runtime_version,
      lower(p_artifact_sha256),p_runtime_state,p_source_ref,p_provider_evidence_ref,
      p_provider_observed_at,p_submitted_by,p_metadata
    )
    returning receipt_id into v_receipt_id;

    v_expectation_evidence :=
      'deployment-receipt:' || v_receipt_id::text || ':expectation';
    v_observation_evidence :=
      'deployment-receipt:' || v_receipt_id::text || ':observation';

    insert into foundation.service_deployment_expectations(
      service_id,environment,expected_runtime_ref,expected_version,
      expected_artifact_sha256,expected_state,source_ref,effective_at,
      evidence_ref,evidence_note
    )
    values (
      p_service_id,p_environment,v_runtime_ref,p_runtime_version,
      lower(p_artifact_sha256),p_runtime_state,p_source_ref,p_provider_observed_at,
      v_expectation_evidence,
      'Reconciled automatically from verified management-plane deployment receipt ' || v_receipt_id::text || '.'
    );

    insert into foundation.service_deployment_observations(
      service_id,environment,runtime_ref,runtime_version,artifact_sha256,
      runtime_state,health_state,observed_at,evidence_kind,evidence_ref,
      evidence_note,metadata
    )
    values (
      p_service_id,p_environment,v_runtime_ref,p_runtime_version,lower(p_artifact_sha256),
      p_runtime_state,'unknown',p_provider_observed_at,
      case p_provider
        when 'supabase-edge' then 'supabase-api'
        when 'railway' then 'railway-api'
        else 'manual-verified'
      end,
      v_observation_evidence,
      'Runtime observation reconciled from deployment receipt ' || v_receipt_id::text || '.',
      jsonb_build_object(
        'deploymentReceiptId',v_receipt_id,
        'provider',p_provider,
        'providerEvidenceRef',p_provider_evidence_ref,
        'submittedBy',p_submitted_by,
        'receiptMetadata',p_metadata
      )
    );

    v_publication_outcome := 'accepted-new';
    v_result_status := 'reconciled';
  end if;

  v_publication_key := case
    when v_transport='github-oidc'
         and v_transport_run_id is not null
         and v_transport_run_attempt is not null
      then 'github-oidc:' || v_transport_run_id || ':' || v_transport_run_attempt || ':' || v_receipt_id::text
    else
      'submission:' || p_submitted_by || ':' ||
      encode(extensions.digest(
        convert_to(
          p_provider_evidence_ref || '|' ||
          p_provider_observed_at::text || '|' ||
          v_receipt_id::text,
          'UTF8'
        ),
        'sha256'
      ),'hex')
  end;

  insert into foundation.service_deployment_receipt_publications(
    publication_key,receipt_id,service_id,environment,provider,runtime_version,
    artifact_sha256,source_ref,provider_evidence_ref,publication_outcome,
    submitted_by,transport,transport_run_id,transport_run_attempt,transport_event,
    transport_repository,transport_ref,transport_workflow_ref,transport_workflow_sha,
    rollback,metadata,published_at
  )
  values (
    v_publication_key,v_receipt_id,p_service_id,p_environment,p_provider,p_runtime_version,
    lower(p_artifact_sha256),p_source_ref,p_provider_evidence_ref,v_publication_outcome,
    p_submitted_by,v_transport,v_transport_run_id,v_transport_run_attempt,v_transport_event,
    v_transport_repository,v_transport_ref,v_transport_workflow_ref,v_transport_workflow_sha,
    v_rollback,p_metadata,now()
  )
  on conflict (publication_key) do nothing
  returning publication_id into v_publication_id;

  if v_publication_id is null then
    select publication_id into v_publication_id
    from foundation.service_deployment_receipt_publications
    where publication_key=v_publication_key;
  end if;

  return jsonb_build_object(
    'deploymentReceiptResponse','shine-foundation/service-deployment-receipt-response-v1',
    'schemaVersion','1.1.0',
    'status',v_result_status,
    'receiptId',v_receipt_id,
    'publicationId',v_publication_id,
    'publicationOutcome',v_publication_outcome,
    'serviceId',p_service_id,
    'environment',p_environment,
    'runtimeVersion',p_runtime_version,
    'deploymentTruth',foundation.get_service_deployment_truth_v1(
      p_service_id,p_environment
    ),
    'publicationAttestation',foundation.get_deployment_receipt_publication_health_v1(
      p_service_id,p_environment,86400
    ),
    'readiness',case
      when p_service_id='foundation.gateway'
        then foundation.evaluate_foundation_readiness_v1(p_environment,now())
      else null
    end
  );
end;
$layer33$;

revoke all on function foundation.submit_service_deployment_receipt_v1(
  text,text,text,text,text,text,text,text,text,timestamptz,text,jsonb
) from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.submit_service_deployment_receipt_v1(
  text,text,text,text,text,text,text,text,text,timestamptz,text,jsonb
) to service_role;
