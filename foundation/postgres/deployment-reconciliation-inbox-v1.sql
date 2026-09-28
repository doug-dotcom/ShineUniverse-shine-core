-- Foundation Layer 31: management-plane deployment reconciliation inbox.
-- Accepts minimal verified deployment receipts without storing provider management credentials.

create table foundation.service_deployment_receipts (
  receipt_id uuid primary key default gen_random_uuid(),
  service_id text not null references foundation.service_registry(service_id),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  provider text not null
    check (provider in ('supabase-edge','railway','manual-verified')),
  runtime_ref text not null,
  runtime_version text not null,
  artifact_sha256 text not null
    check (artifact_sha256 ~ '^[a-fA-F0-9]{64}$'),
  runtime_state text not null
    check (runtime_state in ('active','inactive','failed')),
  source_ref text not null
    check (source_ref ~ '^github://[^/]+/[^/]+/commit/[a-fA-F0-9]{40}$'),
  provider_evidence_ref text not null,
  provider_observed_at timestamptz not null,
  submitted_by text not null
    check (submitted_by ~ '^[a-z0-9][a-z0-9._:-]*$'),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  recorded_at timestamptz not null default now(),
  unique(service_id,environment,runtime_version,artifact_sha256,source_ref)
);

alter table foundation.service_deployment_receipts enable row level security;

create policy foundation_runtime_service_deployment_receipts_select
on foundation.service_deployment_receipts
for select
to foundation_runtime
using (true);

revoke all on foundation.service_deployment_receipts from public,anon,authenticated,foundation_gateway;
grant select on foundation.service_deployment_receipts to foundation_runtime;
grant select,insert on foundation.service_deployment_receipts to service_role;

create index service_deployment_receipts_current_idx
  on foundation.service_deployment_receipts(
    service_id,environment,provider_observed_at desc,recorded_at desc
  );

create trigger service_deployment_receipts_append_only
before update or delete on foundation.service_deployment_receipts
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_service_deployment_receipt
with (security_invoker=true)
as
select distinct on (service_id,environment)
  receipt_id,
  service_id,
  environment,
  provider,
  runtime_ref,
  runtime_version,
  artifact_sha256,
  runtime_state,
  source_ref,
  provider_evidence_ref,
  provider_observed_at,
  submitted_by,
  metadata,
  recorded_at
from foundation.service_deployment_receipts
order by
  service_id,environment,
  provider_observed_at desc,recorded_at desc,receipt_id desc;

revoke all on foundation.current_service_deployment_receipt from public,anon,authenticated,foundation_gateway;
grant select on foundation.current_service_deployment_receipt to foundation_runtime;


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
as $layer31$
declare
  v_service foundation.service_registry%rowtype;
  v_existing foundation.service_deployment_receipts%rowtype;
  v_current_expectation foundation.service_deployment_expectations%rowtype;
  v_runtime_ref text;
  v_receipt_id uuid;
  v_expectation_evidence text;
  v_observation_evidence text;
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

  select * into v_existing
  from foundation.service_deployment_receipts
  where service_id=p_service_id
    and environment=p_environment
    and runtime_version=p_runtime_version
    and lower(artifact_sha256)=lower(p_artifact_sha256)
    and source_ref=p_source_ref;

  if v_existing.receipt_id is not null then
    return jsonb_build_object(
      'deploymentReceiptResponse','shine-foundation/service-deployment-receipt-response-v1',
      'schemaVersion','1.0.0',
      'status','replayed',
      'receiptId',v_existing.receipt_id,
      'serviceId',p_service_id,
      'environment',p_environment,
      'runtimeVersion',p_runtime_version
    );
  end if;

  select * into v_current_expectation
  from foundation.current_service_deployment_expectations
  where service_id=p_service_id
    and environment=p_environment;

  if v_current_expectation.expectation_id is not null
     and v_current_expectation.expected_version is not null
     and p_runtime_version ~ '^[0-9]+$'
     and v_current_expectation.expected_version ~ '^[0-9]+$'
     and p_runtime_version::numeric < v_current_expectation.expected_version::numeric
     and coalesce(p_metadata->>'rollback','false')<>'true' then
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

  return jsonb_build_object(
    'deploymentReceiptResponse','shine-foundation/service-deployment-receipt-response-v1',
    'schemaVersion','1.0.0',
    'status','reconciled',
    'receiptId',v_receipt_id,
    'serviceId',p_service_id,
    'environment',p_environment,
    'runtimeVersion',p_runtime_version,
    'deploymentTruth',foundation.get_service_deployment_truth_v1(
      p_service_id,p_environment
    ),
    'readiness',case
      when p_service_id='foundation.gateway'
        then foundation.evaluate_foundation_readiness_v1(p_environment,now())
      else null
    end
  );
end;
$layer31$;

revoke all on function foundation.submit_service_deployment_receipt_v1(
  text,text,text,text,text,text,text,text,text,timestamptz,text,jsonb
) from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.submit_service_deployment_receipt_v1(
  text,text,text,text,text,text,text,text,text,timestamptz,text,jsonb
) to service_role;


create or replace function foundation.get_deployment_reconciliation_status_v1(
  p_service_id text,
  p_environment text default 'production'
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, foundation
as $layer31$
declare
  v_receipt foundation.service_deployment_receipts%rowtype;
  v_truth jsonb;
  v_health jsonb;
  v_readiness jsonb;
  v_state text;
  v_reason text;
begin
  select * into v_receipt
  from foundation.current_service_deployment_receipt
  where service_id=p_service_id
    and environment=p_environment;

  v_truth := foundation.get_service_deployment_truth_v1(
    p_service_id,p_environment
  );

  v_health := foundation.get_service_health_v1(
    p_service_id,p_environment
  );

  if p_service_id='foundation.gateway' then
    v_readiness := foundation.evaluate_foundation_readiness_v1(
      p_environment,now()
    );
  end if;

  if v_receipt.receipt_id is null then
    v_state := 'unknown';
    v_reason := 'deployment-receipt-missing';
  elsif coalesce(v_truth->>'deploymentState','unknown')<>'aligned' then
    v_state := 'drift';
    v_reason := 'deployment-truth-not-aligned';
  elsif coalesce(v_health->>'runtimeVersion','')<>v_receipt.runtime_version then
    v_state := 'awaiting-proof';
    v_reason := 'current-runtime-health-pending';
  elsif p_service_id='foundation.gateway'
        and coalesce(v_readiness->>'readinessState','unknown')='unknown' then
    v_state := 'awaiting-proof';
    v_reason := 'current-runtime-readiness-pending';
  else
    v_state := 'reconciled';
    v_reason := 'deployment-reconciled';
  end if;

  return jsonb_build_object(
    'deploymentReconciliationStatusResponse','shine-foundation/deployment-reconciliation-status-response-v1',
    'schemaVersion','1.0.0',
    'serviceId',p_service_id,
    'environment',p_environment,
    'state',v_state,
    'reasonCode',v_reason,
    'receipt',case
      when v_receipt.receipt_id is null then null
      else jsonb_build_object(
        'receiptId',v_receipt.receipt_id,
        'provider',v_receipt.provider,
        'runtimeVersion',v_receipt.runtime_version,
        'artifactSha256',v_receipt.artifact_sha256,
        'sourceRef',v_receipt.source_ref,
        'providerEvidenceRef',v_receipt.provider_evidence_ref,
        'providerObservedAt',v_receipt.provider_observed_at,
        'submittedBy',v_receipt.submitted_by
      )
    end,
    'deploymentTruth',v_truth,
    'health',v_health,
    'readiness',v_readiness
  );
end;
$layer31$;

revoke all on function foundation.get_deployment_reconciliation_status_v1(text,text)
  from public,anon,authenticated;
grant execute on function foundation.get_deployment_reconciliation_status_v1(text,text)
  to foundation_runtime;
