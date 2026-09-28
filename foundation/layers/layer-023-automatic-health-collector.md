# Foundation Layer 23 — Automatic health collector

**Status:** LIVE  
**Scope:** scheduled public health probes + immutable probe evidence + automatic health refresh

Layer 22 gave Foundation an evidence-backed health model, but the evidence still had to be sampled manually.

Layer 23 closes that gap.

Foundation now generates its own fresh health evidence continuously using Supabase Cron and pg_net. It probes the public Gateway health endpoint every five minutes, harvests asynchronous responses every minute, validates the response contract, records immutable request/result evidence, and refreshes the service health window automatically.

## Production loop

Two active pg_cron jobs drive the collector:

- `shine-foundation-health-probe-5m` — every five minutes;
- `shine-foundation-health-harvest-1m` — every minute.

The probe job calls:

`GET https://sjpxqeyewahraxvidvcc.supabase.co/functions/v1/foundation-gateway/health`

No token or secret is stored because the Gateway health endpoint is deliberately public and contains no private/user data.

The expected response contract is:

```json
{
  "service": "shine-foundation-gateway",
  "status": "ok",
  "schemaVersion": "1.0.0"
}
```

A response is only considered contract-valid when:

- HTTP status is 2xx;
- the request did not time out;
- pg_net did not report an error;
- the response body parses as JSON;
- `service`, `status` and `schemaVersion` all match the configured target.

## New control-plane objects

Layer 23 adds:

- `foundation.service_health_probe_targets`;
- `foundation.service_health_probe_requests`;
- `foundation.service_health_probe_results`;
- `foundation.current_service_health_probe_target`;
- `foundation.record_service_health_probe_request_v1`;
- `foundation.record_service_health_probe_result_v1`;
- `foundation.refresh_service_health_from_probes_v1`;
- hosted `foundation.enqueue_service_health_probe_v1`;
- hosted `foundation.harvest_service_health_probe_responses_v1`.

Probe targets, requests and results are append-only.

The hosted scheduler plumbing lives in `automatic-health-collector-hosted-v1.sql` because plain PostgreSQL CI does not provide Supabase's pg_net runtime. The portable persistence, aggregation and policy logic remains testable in clean Postgres.

## Health policy v1.1

Automatic synthetic probes use the current one-hour evaluation window with:

- evidence freshness: 10 minutes;
- minimum sample: 3 probe results;
- warning failure rate: 10%;
- critical failure rate: 50%;
- warning p95 round-trip: 5,000 ms;
- critical p95 round-trip: 10,000 ms;
- warning runtime/probe errors: 1;
- critical runtime/probe errors: 2.

Synthetic probe failures include:

- timeout;
- networking error;
- missing HTTP status;
- non-2xx/non-3xx health response;
- 2xx response with an invalid health contract.

4xx traffic from normal application requests is still not treated as a general service failure by Layer 22; a 4xx from the dedicated health probe is different because the probe endpoint itself is expected to return a valid 2xx health contract.

## Live production proof

The initial end-to-end production exercise queued three pg_net health requests and harvested them through the production collector.

All three returned:

- HTTP 200;
- no timeout;
- no networking error;
- valid Foundation Gateway health contract;
- approximately 20 ms round-trip.

The resulting automatic evidence window contains 3/3 successful probes and evaluates:

- service health: **healthy**;
- deployment truth: **aligned**;
- service operational state: **operational**.

The one-minute harvester has also been observed executing successfully under pg_cron.

## Batch correctness fix

Live testing exposed a subtle ordering bug before the layer was closed.

When several responses arrived with an identical `window_ended_at` inside one transaction, Layer 22's current-evidence view could fall back to UUID ordering and choose a two-sample window instead of the final three-sample window.

Layer 23 fixes this by:

1. harvesting the complete response batch first;
2. refreshing health once per enabled target after ingestion;
3. using the collector's monotonic `latestProbeResultSequence` as the deterministic tie-breaker for batched health evidence.

This turns a previously nondeterministic edge case into deterministic control-plane behaviour.

## Failure behaviour

The collector fails conservative:

- missing target → no probe, explicit skipped result;
- disabled target → no probe;
- missing responses → no fabricated evidence;
- under three samples → health **unknown**;
- stale evidence → health **unknown**;
- warning thresholds crossed → **degraded**;
- critical thresholds crossed → **unhealthy**.

No stale or absent evidence can be converted into healthy.

## Security boundary

Layer 23 stores no new credential.

The collector:

- calls only the configured public HTTPS health endpoint;
- cannot read Vault resources;
- cannot grant permissions;
- cannot impersonate users;
- cannot modify historical probe evidence;
- exposes no probe-write functions to `anon`, `authenticated` or `foundation_runtime`;
- keeps normal Foundation runtime access read-only.

## Machine-readable contract

`foundation/contracts/automatic-health-collector-v1.json`

## Acceptance

Layer 23 is complete when:

- portable collector state-machine tests pass;
- health target/request/result ledgers are append-only;
- request and result replay are idempotent;
- three successful probes evaluate healthy;
- warning failures evaluate degraded;
- critical failures evaluate unhealthy;
- the hosted pg_net pipeline returns valid Gateway responses;
- both cron jobs are active;
- the harvester is observed succeeding under pg_cron;
- batched evidence ordering is deterministic;
- current service state returns operational from automatic evidence;
- Supabase advisors show no new Layer-23-specific regression.

Layer 23 is the point where Foundation starts **watching itself** rather than merely answering health questions when a human asks.

## Closure verification

Production closure verification observed the collector running without manual invocation:

- `shine-foundation-health-probe-5m` succeeded at 2026-09-28 00:45 UTC;
- request `pg-net:health-probe-request:foundation.gateway:production:4` was queued by that cron execution;
- the Gateway returned HTTP 200 with a valid health contract in approximately 8.6 ms;
- `shine-foundation-health-harvest-1m` succeeded at 2026-09-28 00:46 UTC;
- automatic evidence advanced to `health-probe-window:foundation.gateway:production:26`;
- the current automatic window contains 4 successful probes, 0 4xx, 0 5xx and 0 runtime/probe errors;
- service health is **healthy** and combined service state is **operational**.

Supabase security advisors reported no Layer-23-specific finding.

The performance advisor initially identified two Layer-23 foreign keys without covering indexes on `service_health_probe_requests`. Both were corrected before closure with:

- `service_health_probe_requests_service_idx`;
- `service_health_probe_requests_target_idx`.

After remediation, no Layer-23 unindexed-foreign-key finding remains.

