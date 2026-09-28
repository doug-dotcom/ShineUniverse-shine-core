# Foundation Layer 35 — Immutable release identity

**Status:** LIVE  
**Scope:** bind verified Foundation layer truth to the exact current deployment receipt and trusted publication identity

Layer 34 made trusted deployment-publication provenance part of readiness.

Layer 35 makes that provenance durable as an immutable release identity.

A registry row can no longer be advanced to a new verified Foundation layer merely because the control plane looks healthy. The layer now has an append-only binding to the exact canonical gateway deployment and the exact publication proof that established it.

## Release identity ledger

Layer 35 adds:

`foundation.foundation_release_identity_bindings`

Each binding records:

- Foundation layer number;
- canonical runtime source ref;
- runtime version;
- artefact SHA-256;
- deployment receipt UUID;
- publication UUID;
- publication assurance class;
- readiness state and evidence fingerprint at bind time;
- binder identity and timestamp.

The ledger is append-only.

Direct writes are not granted to Foundation runtime or service role. New bindings are created only through the validated binder.

## Binder

The control-plane binder is:

`foundation.bind_foundation_release_identity_v1(integer,text,jsonb)`

It is callable only by `service_role`.

Before writing anything it requires:

1. deployment truth is `aligned`;
2. the current deployment receipt has publication state `pass`;
3. publication assurance is `github-oidc`;
4. publication source/runtime/artefact exactly match canonical deployment truth;
5. Foundation readiness is in a bindable state: `ready`, `restricted` or `degraded`.

`unknown` and `not-ready` cannot be bound.

The release reference is not supplied by the caller. Foundation generates it from the canonical deployment source commit:

`foundation:layer-<layer>:<first-8-runtime-source-sha>`

This prevents a caller from inventing a release identity string that does not match deployment truth.

## Release identity health

Layer 35 adds:

`foundation.get_foundation_release_identity_health_v1(text)`

The reader continuously compares the latest immutable binding with current:

- deployment truth;
- deployment receipt;
- publication identity;
- source commit;
- runtime version;
- artefact SHA;
- publication assurance.

States are:

- **PASS** — binding still matches current deployment and publication;
- **DEGRADED** — identity still matches but publication assurance has degraded;
- **UNKNOWN** — required identity evidence is missing;
- **FAIL** — canonical deployment or publication no longer matches the bound release.

A deployment moving after a binding therefore cannot leave stale green registry metadata looking authoritative.

## Readiness is evidence, not immutable identity

The readiness fingerprint and readiness state are captured at bind time for auditability.

They are deliberately **not** part of durable release identity.

Defence, health or dependency state can legitimately change after a deployment without changing the deployed artefact. The health reader therefore reports:

`readinessChangedSinceBinding`

without treating that alone as release-identity drift.

## Universe release projection

The live release binding is:

`foundation:layer-35:b7c5331f`

The Universe readiness ledger contains the matching release entry and `universe.app_registry` now points to it.

The two source references serve different purposes:

- the release identity suffix `b7c5331f` is the exact **deployed gateway runtime source**;
- the Universe release evidence commit records the **Layer-35 control-plane implementation/acceptance source**.

That distinction is intentional.

## Production evidence

Current bound production identity:

- Foundation layer: **35**;
- release identity: `foundation:layer-35:b7c5331f`;
- Gateway runtime: **85**;
- runtime source:
  `b7c5331f93eff28a781f0794c89ccf50e90a4045`;
- artefact:
  `a596c895d31e272d2358d69e500eb708a43462de69df32e7e8a87d540907b83f`;
- deployment receipt:
  `bac106fe-57c4-4b38-b8bb-0acb5de11086`;
- publication:
  `2649330b-6117-44a0-9614-aae8f6fb8478`;
- assurance: **github-oidc**;
- release identity health: **PASS**;
- current deployment match: **true**;
- current publication match: **true**.

Readiness at bind time was **RESTRICTED** because Defence was guarded. That is an operational posture and does not represent release identity drift.

## CI

Foundation persistence CI now applies:

`foundation/postgres/foundation-release-identity-binding-v1.sql`

and runs:

`foundation/postgres/foundation-release-identity-binding-v1.test.sql`.

Run `36402082988` passed both Layer-35 steps:

- apply immutable release identity binding;
- run immutable release identity acceptance tests.

The shared workflow later failed in a separate Shine Defence rollback-recovery-ladder acceptance test after the Layer-35 steps had completed successfully.

## Advisor hardening

Post-deployment advisors found the two new foreign keys initially lacked covering indexes.

Layer 35 now also creates indexes for:

- `deployment_receipt_id`;
- `publication_id`.

After that hardening:

- no Layer-35 unindexed foreign-key findings remain;
- no Layer-35 security-advisor findings remain.

## Closure invariant

A verified Foundation release now means:

> **The registry layer points to a real release ledger entry, and that release has an immutable binding to the exact canonical runtime, artefact, deployment receipt and trusted GitHub-OIDC publication that established it.**

If deployment identity moves, the old binding fails closed instead of silently remaining green.
