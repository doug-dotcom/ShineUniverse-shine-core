import test from 'node:test';
import assert from 'node:assert/strict';
import {validateAtlasFeedEvent} from './validate-feed-event-v1.mjs';

function validEvent(overrides = {}) {
  const event = {
    atlasFeedEvent: 'shine-universe/atlas-feed-event',
    schemaVersion: '1.0.0',
    eventId: 'c6d2d5e2-04be-4dd4-a5d9-8d754ef05e23',
    topic: 'dive.site.condition',
    source: {
      appId: 'shine-dive',
      capabilityId: 'dive.site.condition.publish',
      releaseRef: 'git:abc123'
    },
    subject: {
      kind: 'dive_site',
      key: 'site:julian-rocks'
    },
    timing: {
      occurredAt: '2026-09-28T08:00:00.000Z',
      publishedAt: '2026-09-28T08:00:02.000Z',
      freshForSeconds: 3600
    },
    audience: {
      mode: 'owner',
      dataClass: 'general'
    },
    provenance: {
      mode: 'first_party',
      sourceObservedAt: '2026-09-28T08:00:00.000Z',
      evidenceRefs: []
    },
    payloadContract: {
      schemaRef: 'dive.site.condition',
      schemaVersion: '1.0.0'
    },
    payload: {
      state: 'good',
      confidence: 'observed'
    }
  };
  return {...event, ...overrides};
}

test('accepts a bounded first-party owner event', () => {
  assert.deepEqual(validateAtlasFeedEvent(validEvent()), {ok: true, errors: []});
});

test('fails closed on an unknown top-level field', () => {
  const result = validateAtlasFeedEvent(validEvent({unexpected: true}));
  assert.equal(result.ok, false);
  assert.match(result.errors.join('\n'), /unexpected is not allowed/);
});

test('requires a grant id for grant-scoped events', () => {
  const event = validEvent();
  event.audience = {mode: 'grant', dataClass: 'personal'};
  const result = validateAtlasFeedEvent(event);
  assert.equal(result.ok, false);
  assert.match(result.errors.join('\n'), /grantId/);
});

test('rejects a grant id outside grant mode', () => {
  const event = validEvent();
  event.audience = {mode: 'owner', dataClass: 'general', grantId: 'grant:123'};
  const result = validateAtlasFeedEvent(event);
  assert.equal(result.ok, false);
  assert.match(result.errors.join('\n'), /only when mode=grant/);
});

test('rejects published time before occurrence time', () => {
  const event = validEvent();
  event.timing = {
    occurredAt: '2026-09-28T08:00:10.000Z',
    publishedAt: '2026-09-28T08:00:02.000Z',
    freshForSeconds: 3600
  };
  const result = validateAtlasFeedEvent(event);
  assert.equal(result.ok, false);
  assert.match(result.errors.join('\n'), /must not precede/);
});

test('requires evidence for non-first-party provenance', () => {
  const event = validEvent();
  event.provenance = {
    mode: 'external',
    sourceObservedAt: '2026-09-28T08:00:00.000Z',
    evidenceRefs: []
  };
  const result = validateAtlasFeedEvent(event);
  assert.equal(result.ok, false);
  assert.match(result.errors.join('\n'), /requires at least one evidenceRef/);
});

test('rejects credential-bearing payload keys at any depth', () => {
  const event = validEvent();
  event.payload = {safe: {authorization: 'Bearer nope'}};
  const result = validateAtlasFeedEvent(event);
  assert.equal(result.ok, false);
  assert.match(result.errors.join('\n'), /forbidden credential-bearing key/);
});

test('rejects oversized payloads', () => {
  const event = validEvent();
  event.payload = {body: 'x'.repeat(66000)};
  const result = validateAtlasFeedEvent(event);
  assert.equal(result.ok, false);
  assert.match(result.errors.join('\n'), /exceeds 65536/);
});

test('accepts explicitly grant-scoped personal data when the grant id is present', () => {
  const event = validEvent();
  event.audience = {mode: 'grant', dataClass: 'personal', grantId: 'foundation-grant:7f5c'};
  const result = validateAtlasFeedEvent(event);
  assert.equal(result.ok, true, result.errors.join('\n'));
});
