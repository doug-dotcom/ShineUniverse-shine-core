# Foundation Layer 29 — Canonical privileged-operation audit truth

**Status:** LIVE  
**Scope:** append-only front-door policy + outcome audit for every privileged Gateway POST attempt

Layer 28 made privileged operation policy unavoidable at the HTTP front door.

Layer 29 makes that enforcement reconstructable after the fact.

Foundation now records one canonical audit chain that answers:

- which privileged route was attempted;
- which canonical operation it mapped to;
- which policy state/reason applied;
- which dependency evidence supported that policy;
- which atomic/service guard remained authoritative behind admission;
- which exact Gateway runtime/source artefact handled the request;
- what HTTP/domain outcome followed.

It does this without copying request bodies, auth tokens, conversation text, specialist inputs or integration context payloads.

## Two-event audit chain

Each privileged attempt receives a generated `operation_audit_id`.

The canonical chain is:

1. **policy**
   - written before route-specific execution;
   - mandatory in production;
   - failure to record fails the request closed with HTTP 503;
   - snapshots route, policy, dependency and exact deployment evidence.

2. **outcome**
   - appended after the route response is known;
   - records HTTP status, outcome class and reason;
   - links to the policy event with `previous_event_hash`.

Both rows are immutable.

The policy event has no predecessor hash.

The outcome event's `previous_event_hash` must equal the policy event's SHA-256 `event_hash`.

## Canonical audit ledger

Layer 29 adds:

`foundation.gateway_operation_audit_events`

Key evidence includes:

- operation audit ID;
- phase;
- Gateway runtime version;
- deployment evidence ref;
- exact Git source ref;
- artefact SHA-256;
- route symbol;
- HTTP method/path template;
- operation key;
- risk/effect class;
- policy state/reason;
- operation-policy evidence ref;
- impact scope;
- dependency evidence;
- execution guard ref;
- HTTP status;
- outcome class;
- response reason;
- optional domain request ID;
- event/predecessor hashes.

The table is append-only and RLS-protected.

## Data minimisation

The canonical operation audit deliberately does **not** store:

- HTTP request bodies;
- auth tokens;
- JWT bodies;
- passwords/secrets;
- conversation content;
- integration context payloads;
- capability inputs;
- user file contents.

The audit is evidence about control decisions and outcomes, not another copy of user data.

## Recorder privilege boundary

The Gateway does not receive direct INSERT access to the audit table.

Instead it can execute only:

`foundation.record_gateway_operation_audit_event_v1(...)`

The recorder is a narrowly scoped SECURITY DEFINER function with an empty/fixed search path and public execution revoked.

Verified production boundary:

- audit table RLS: **enabled**;
- `foundation_gateway` direct INSERT: **false**;
- `foundation_gateway` recorder EXECUTE: **true**;
- anon recorder EXECUTE: **false**;
- anon audit SELECT: **false**.

## Database-authoritative policy evidence

The first v80/v81 production exercise uncovered a useful boundary problem.

The HTTP handler had a valid route policy, but the JSON snapshot did not reach the database recorder in a usable form. Because pre-execution audit is mandatory, the Gateway correctly failed closed with:

`operation-audit-unavailable`

rather than executing an unaudited privileged request.

Layer 29 hardened this boundary in two ways:

1. the runtime adapter normalises hosted JSONB values that may arrive as JSON strings;
2. the database recorder recomputes the authoritative route policy from:
   - method;
   - route;
   - environment;
   - recorded policy timestamp.

The Edge-supplied snapshot is now optional consistency evidence rather than the source of truth.

If a usable snapshot is supplied and disagrees with the database-authoritative policy state/reason, the recorder rejects the event.

This makes canonical audit truth independent of driver JSON representation.

## Outcome failure semantics

Pre-execution policy audit is mandatory and fail-closed.

Post-execution outcome audit has a different safety rule.

If the domain operation has already completed, an outcome-audit append failure does **not** rewrite the successful/failed domain response into a retry-inducing infrastructure error. That could cause duplicate side effects.

Instead:

- the real route response is preserved;
- the policy-only trace remains open;
- audit health reports that open trace after the configured stale interval.

This gives Foundation both safety and detectable audit incompleteness.

## Audit health

`foundation.get_gateway_operation_audit_health_v1(environment, stale_after_seconds)`

reports:

- policy event count;
- outcome event count;
- stale/open trace count;
- broken hash-chain count.

States:

- **pass** — no stale open trace and no broken predecessor hash;
- **degraded** — one or more stale policy-only traces;
- **fail** — a broken/missing predecessor chain exists;
- **unknown** — no policy event has been observed.

At closure:

- policy events (24h): **6**;
- outcome events (24h): **6**;
- open traces: **0**;
- broken chains: **0**;
- audit health: **PASS**.

Normal scheduled worker traffic is already generating canonical audit chains automatically.

## Domain evidence reconstruction

`foundation.get_gateway_operation_audit_trace_v1(operation_audit_id)`

returns the canonical policy/outcome chain plus existing domain evidence linked by domain request ID.

Core evidence sources include:

- access audit;
- grant consent;
- grant revocation;
- identity claim.

Later specialist/Concierge evidence tables are discovered dynamically with `to_regclass` and dynamic SQL.

This keeps the canonical audit reader portable in a clean Foundation rebuild while still enriching production traces when later feature schemas are installed.

The acceptance suite proves a canonical trace can link back to a grant-consent domain event without copying its payload into the operation ledger.

## Supersession-aware route coverage

During Layer 29, Concierge Layer 192 added:

`POST /v1/concierge/supersede`

The Gateway registry now contains:

- routes: **40**;
- privileged route contracts: **24**;
- distinct privileged operation policies: **23**.

The supersede route intentionally reuses the canonical `concierge.cancel` control policy.

Operation-policy coverage remains **PASS**:

- covered privileged route contracts: **24 / 24**;
- missing policies: **0**;
- missing admission bindings: **0**;
- missing dependency scopes: **0**;
- dependency-admission policies: **21**;
- worker-only policies: **2**.

## Exact-source Gateway deployment

The first audit-enabled Gateway candidate, v80, was source-bound and healthy, but correctly fail-closed privileged requests while the recorder boundary problem was being diagnosed.

Gateway **v81** contains the runtime JSON-boundary hardening and is exact-source bound to:

`github://doug-dotcom/ShineUniverse-shine-core/commit/60837a74d766742dbd4b88ca1cd0da0e14ec2d55`

Deployment truth is aligned to:

- runtime version: **81**;
- artefact SHA-256: `6aebc29aac7e2eab77695549995f50a0c5e4ee5ab9b184ea4b25983bf8aa522d`;
- source commit: `60837a74d766742dbd4b88ca1cd0da0e14ec2d55`.

The later database-authoritative audit hardening is captured by repository/database migrations without changing the v81 Edge bundle.

## v81 production proof

Current deployment-bounded Gateway health:

- probe results: **5**;
- 4xx: **0**;
- 5xx: **0**;
- runtime/probe errors: **0**;
- p95 probe latency: approximately **24.8 ms**;
- health: **HEALTHY**.

Production audit probes demonstrate:

### Permission route

`POST /v1/grants/consent` without credentials:

- current policy state: `admit-degraded`;
- policy reason: `dependency-degraded`;
- impact scope: `permission-operations`;
- current Defence evidence: warning/degraded;
- route result: HTTP **401 unauthenticated**;
- outcome class: `authentication-rejected`;
- policy/outcome hashes correctly linked.

This is correct: the policy broker admitted the degraded scope, the request then reached its normal authentication boundary, and the audit preserved both facts.

### Worker route

`POST /v1/concierge/retry/claim`:

- policy: `worker-only`;
- normal worker auth/service semantics preserved;
- canonical policy/outcome pairs recorded.

Scheduled retry traffic is also being audited automatically.

## CI

Layer 29 adds gates for:

- audit schema/acceptance;
- policy-before-outcome ordering;
- idempotent replay;
- hash-chain integrity;
- append-only enforcement;
- runtime-role privileges;
- optional domain evidence portability;
- JSONB string/object normalisation;
- production Edge audit wiring;
- Node HTTP behaviour;
- Deno type checking.

The final full Shine Foundation workflow for commit:

`0116ff801284a45b0d9bb0cc63175976f46e510c`

completed **SUCCESS**.

Workflow run:

`36378138630`

## Advisors

No Layer-29-specific Supabase security finding remains.

The Layer-29 missing foreign-key index was fixed with:

`gateway_operation_audit_events_service_idx`

After remediation, the only audit-related performance INFO is that this newly created index has not yet accumulated usage statistics.

## Machine-readable artefacts

- `foundation/contracts/gateway-operation-audit-v1.json`
- `foundation/deployments/layer-029-gateway-source.json`

## Closure

Layer 29 changes Foundation from:

> “we enforced the correct privileged-operation policy”

to:

> “we can prove which policy was enforced, what evidence supported it, which exact runtime executed it, and what happened next — through an immutable hash-linked trace.”

Foundation now has a canonical audit trail worthy of the control plane it protects.
