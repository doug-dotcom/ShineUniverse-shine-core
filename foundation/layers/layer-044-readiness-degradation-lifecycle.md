# Foundation Layer 44 — Persistent readiness degradation lifecycle

**Status:** LIVE

Layer 44 gives operational readiness degradation its own append-only lifecycle, separate from release-projection incidents.

## Why separate

A release can remain correctly identified and projection-aligned while dependencies or Defence degrade privileged scopes.

That is an operational readiness problem, not release identity drift.

## Lifecycle

Incident key:

`production:readiness`

Events:

- `detected`
- `opened`
- `changed`
- `recovered`

Default persistence threshold:

**300 seconds**

One unhealthy sample creates only a watch.

Unchanged unhealthy evidence below 300 seconds does not open an incident.

Persistent unhealthy evidence opens.

Materially changed unhealthy evidence appends `changed`.

Ready evidence appends `recovered`.

## Severity

Restricted/degraded readiness is warning severity.

Not-ready/unknown readiness, or blocked dependency scopes, is critical.

## Production proof

The first production sentinel ran against the existing Layer-43 degraded baseline.

Result:

- event: `detected`
- severity: warning
- persistence: 0 seconds
- watch count: 1
- active readiness incidents: 0
- degraded scopes: context, control, credential, identity, permission, protected operations

Gateway v90 release identity remains PASS and release projection remains ALIGNED.

## CI

Foundation run `36419640803` passed end-to-end.

Acceptance proves:

- first degraded sample -> detected watch;
- 299 seconds -> no open;
- 300 seconds -> opened warning;
- blocked/not-ready evidence -> changed critical;
- ready evidence -> recovered;
- recovered summary -> normal.

## Advisors

Layer-44 security findings: 0.

All foreign keys are indexed. The observation index is currently unused INFO because production has only the initial watch event.

## Invariant

> Persistent operational degradation deserves an incident, but it must never masquerade as release identity drift.
