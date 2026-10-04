# Foundation Layer 202 — Canonical access request builder

Saved and locally tested 4 October 2026. Extracted the shared Gateway-v2 request envelope builder and integrated it into createFoundationAppClient. Keeps the existing wire format, header authentication, random trace/request IDs, request time, resources and context. Does not accept top-level credentials or a caller-claimed Shine ID into the generated permission body. Caller-supplied context remains subject to existing rules; this change does not claim to sanitise arbitrary context.

All 21 onboarding acceptance tests passed. New builder tests are wired into Foundation CI. Remote CI and deployment into consuming apps are separate; no running app is asserted to have adopted this commit. Layer 203 strengthens validation before transport.
