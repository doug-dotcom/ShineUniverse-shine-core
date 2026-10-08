# VC live readiness — checkpoint 01: deployed wiring baseline

The original source sprint remains **40/40 complete (0 remaining)**. This is the first checkpoint of the subsequent live-readiness phase, with no new sprint denominator assigned. It closes the baseline investigation, not a private integration or production acceptance gate.

Foundation baseline: `74ecaf3f45e8a30dfb64ba4d131c2aa14d23ff79`.
VC inspected source: `doug-dotcom/Shine-Veteran-` at `7e83800135b08fd498577fbfade70ff1ad465a6c`.

## Current observation

Railway reports the production `shine-veteran-care` service online with deployment `32e9e395-6124-4060-afb1-34a7264f84d5`, status SUCCESS and one running replica. Its deployment metadata names the inspected VC commit. No pending operation was reported. The service domain is `shine-veteran-care-production.up.railway.app`. Three earlier failed deployments remain in the recent eight-hour history; this report does not diagnose those historical failures.

The companion JSON records the metadata observation time and exact project/environment/service identifiers. This is live provider metadata plus pinned source inspection. It is **not** an independent HTTP/runtime observation, a verified runtime artifact digest or a signed-in/private journey. Another room may advance the deployment after this observation.

## Concrete wiring gap

The inspected `server.mjs` mounts `/api/adj/overview`, public/static pages, `/auth-config` and `/health`. It does not import or mount the Foundation VC–AI–L selected-memory read pipeline. `package.json` declares the Supabase client and esbuild; it does not declare a Foundation package. This finding concerns the inspected entry point and package, not a claim that every possible service or private adapter has been inspected.

`master-connector/identity.mjs` explicitly describes an offline-tested identity boundary, not a mounted authentication service. Its success still returns transfer blocked because patient mapping and consent are not enforced. That clinic connector is a separate responsibility from the Foundation selected-memory route and must not be enabled to work around the missing Foundation wiring.

`integration-readiness.mjs` is planning-only and always keeps connectionEnabled false. `connection-register.mjs` reports source/saved-receipt evidence, liveProbePerformed false, and live checks pending. These independent source observations agree with the layer-40 handover; an online process does not demonstrate an integrated protected read.

## Next Foundation increment

Define a server-only integration entry point for the selected-memory pipeline with mandatory trusted dependencies and a default blocked state when any dependency is absent. Keep caller identity, L client/user verification, selected consent/resource authority, task status, recipient verification and vault custody independent. No production credentials or private data belong in its request/configuration examples or evidence receipts.

Foundation owns composition and the injectable contract. VC Integrations/Security owns real verified adapters and runtime mounting; VC Orchestration owns scheduler/checkpoint/retry stores; L owns Companion consent/read adapters. These are responsibility areas from the handover, not acknowledgements from other rooms. No other repository was changed and no room was sent a message.

After the entry point exists, acceptance requires an explicitly configured protected runtime route and independent synthetic live journeys, including wrong owner/audience, withdrawn consent, cancellation and dependency outage. Absence of required adapters must return a safe denial without reading memory. Do not substitute fixture callbacks, request-supplied authority flags or the provider's deployment record for live authority/runtime proof.

## Evidence and boundary

Read-only Railway calls: list projects, environment status, list deployments and list domains. GitHub source reads were pinned to the provider-reported VC commit for server.mjs, package.json, integration-readiness.mjs, master-connector/identity.mjs and connection-register.mjs.

No deployment, database change, account sign-in, private read, token inspection or connector enablement occurred. Foundation's 439-test suite is re-run for this documentation checkpoint; all three repository CI checks must pass before merge. The PR history records their actual outcomes.
