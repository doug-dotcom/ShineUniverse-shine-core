# Shine WhatsApp Gateway — test environment

Tracking: #213. **Not deployed; no real WhatsApp messages sent.**

## First acceptance test
Authorised test user sends `VC status` to Meta's official test number. Signed webhook receives event, verifies sender and message ID, obtains fresh approved non-clinical status from Shine, and replies through Meta Cloud API. Unknown status must return unavailable, never a fabricated completion percentage.

## Setup prerequisites
1. Create or access a Meta developer account at https://developers.facebook.com/ and create an app with WhatsApp Business Platform enabled.
2. In WhatsApp API Setup, use Meta's provided test sender and add an approved recipient number. Meta's test setup has recipient limits.
3. Record the WhatsApp phone number ID and business account ID; store API access token, app secret and webhook verify token only in server-side secret management, never in this repository.
4. Deploy an HTTPS staging endpoint that supports Meta webhook GET challenge verification and POST `X-Hub-Signature-256` validation using the app secret.
5. Add an allowlist, inbound idempotency, replay protection, audit logs without message body/clinical data, and an outbound-send kill switch (off by default).
6. Mock the Cloud API in tests; run an authorised real test only after credential setup and approval.

## Safety
No personal WhatsApp history, group access, patient records, automatic clinician notifications, or production messages. Keep clinical details in Veteran Care's secure portal. Outbound messages require consent and appropriate WhatsApp template/window rules.

## Status
Scaffold/setup guide committed. Webhook implementation, integration, tests, Meta credentials and deployment pending.
