-- Foundation Layer 67 advisor hardening.
-- Cover owner_service_id FK lookups independently of the environment/time index.

create index if not exists foundation_promoted_release_owner_handoffs_owner_service_idx
  on foundation.foundation_promoted_release_owner_handoffs(owner_service_id);
