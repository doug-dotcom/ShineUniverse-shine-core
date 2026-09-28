# Foundation Layer 22 — Health & state evidence

**Status:** LIVE  
**Scope:** evidence-backed service health + combined operational state

Layer 21 answered: **is the deployed runtime the runtime Foundation expects?**

Layer 22 answers the different question: **is that runtime actually healthy?**

The distinction is deliberate. A service can be deployed exactly as expected and still be slow, failing or stale. Foundation therefore keeps deployment truth and runtime health as independent evidence domains and combines them only in the service-state reader.

## Health evidence model

Layer 22 adds:

- `foundation.service_health_policies` — append-only health threshold versions;
- `foundation.service_health_evidence` — append-only telemetry windows;
- `foundation.current_service_health_policy`;
- `foundation.current_service_health_evidence`;
- `foundation.get_service_health_v1(text,text)`;
- `foundation.get_service_state_v1(text,text)`;
- `foundation.get_foundation_health_v1(text)`.

Health evidence records:

- request volume;
- 4xx count for context;
- 5xx count and rate;
- average execution latency;
- p95 execution latency;
- runtime error count;
- telemetry source;
- evidence window and freshness.

4xx responses are retained as evidence but do not automatically count as service failures because authentication, validation and user-request errors can legitimately produce 4xx responses.

## Health decisions

The health reader returns:

- **healthy** — fresh, adequately sampled evidence is below warning thresholds;
- **degraded** — at least one warning threshold is crossed;
- **unhealthy** — at least one critical threshold is crossed;
- **unknown** — evidence is missing, stale, under-sampled or the service has no health policy.

Unknown is a first-class state. Foundation does not convert absence of evidence into health.

## Foundation Gateway policy v1

The initial production policy for `foundation.gateway` uses a one-hour evidence window with:

- evidence freshness: 15 minutes;
- minimum requests: 20;
- warning 5xx rate: 1%;
- critical 5xx rate: 5%;
- warning p95 latency: 8,000 ms;
- critical p95 latency: 15,000 ms;
- warning runtime-error count: 1;
- critical runtime-error count: 5.

These are explicit operational thresholds, not hidden heuristics. Future threshold changes are new append-only policy versions.

## Initial live evidence

The first live evidence window was collected from Supabase Edge Function logs for Gateway v71:

- window: 2026-09-27 23:22:06.635Z → 2026-09-28 00:21:06.086Z;
- requests: 84;
- 4xx: 0;
- 5xx: 0;
- average execution: 5,159.7 ms;
- p95 execution: 5,719.2 ms;
- function-log events: 165;
- log messages containing `error`: 0;
- log messages containing `exception`: 0.

Under policy v1, this evidence evaluates to **healthy**.

The observation is operational data and is intentionally written directly to the live evidence ledger rather than embedded into the schema migration. That keeps clean rebuilds deterministic and prevents historical telemetry from pretending to be fresh.

## Combined service state

`foundation.get_service_state_v1` combines Layer 21 deployment truth with Layer 22 health:

- aligned + healthy → **operational**;
- aligned + degraded → **degraded**;
- any unhealthy health result → **unhealthy**;
- deployment drift → **drift** unless health is already unhealthy;
- missing/stale evidence → **unknown**.

`foundation.get_foundation_health_v1` then evaluates all active services marked `required_for_core` and returns one Foundation-wide operational state plus the per-service evidence.

## Security boundary

Health policy and evidence are private control-plane data:

- RLS is enabled;
- public, anonymous and normal authenticated roles have no table access;
- `foundation_runtime` has read-only access;
- `service_role` can append policy/evidence;
- the readers are `SECURITY INVOKER`;
- policy and evidence ledgers reject update/delete mutation.

## Machine-readable contract

`foundation/contracts/service-health-v1.json`

## Acceptance

Layer 22 is complete when:

- a fresh low-error evidence window evaluates healthy;
- aligned deployment + healthy telemetry evaluates operational;
- warning-level 5xx evidence evaluates degraded;
- critical-level 5xx evidence evaluates unhealthy;
- stale evidence evaluates unknown;
- an unhealthy required service makes Foundation unhealthy;
- health evidence cannot be mutated;
- public database roles cannot read the evidence or execute health readers;
- `foundation_runtime` can execute all three readers;
- Supabase advisors show no new Layer-22-specific regression.

Layer 22 means Foundation no longer treats **exists**, **deployed**, **aligned** and **healthy** as synonyms.
