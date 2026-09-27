-- Historical production backfill: temporary runtime select required by the
-- original operational-status view. Mirrors migration 20260926235208.

grant select on foundation.app_connection_status to foundation_runtime;
