-- Shine Foundation advisor FK indexes v1
-- Covers append-only evidence foreign keys used by Layers 14 and 15.

create index if not exists grant_consent_events_grant_id_idx
  on foundation.grant_consent_events (grant_id)
  where grant_id is not null;

create index if not exists identity_claim_events_source_provider_idx
  on foundation.identity_claim_events (source_provider_id);

create index if not exists identity_claim_events_target_provider_idx
  on foundation.identity_claim_events (target_provider_id);
