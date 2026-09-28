const CONTRACT_ID = 'shine-universe/atlas-feed-event';
const SCHEMA_VERSION = '1.0.0';
const TOP_LEVEL = new Set([
  'atlasFeedEvent',
  'schemaVersion',
  'eventId',
  'topic',
  'source',
  'subject',
  'timing',
  'audience',
  'provenance',
  'payloadContract',
  'payload'
]);
const FORBIDDEN_PAYLOAD_KEYS = new Set([
  'password',
  'secret',
  'token',
  'api_key',
  'apikey',
  'authorization',
  'cookie',
  'set-cookie'
]);
const AUDIENCE_MODES = new Set(['owner', 'grant', 'internal']);
const DATA_CLASSES = new Set(['general', 'personal', 'sensitive']);
const PROVENANCE_MODES = new Set(['first_party', 'external', 'derived', 'mixed']);
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const NAMESPACE_RE = /^[a-z0-9]+(?:[._-][a-z0-9]+){1,7}$/;
const SEMVER_RE = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;

function object(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function exactKeys(value, allowed, prefix, errors) {
  if (!object(value)) {
    errors.push(`${prefix} must be an object`);
    return false;
  }
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) errors.push(`${prefix}.${key} is not allowed`);
  }
  return true;
}

function required(value, fields, prefix, errors) {
  for (const field of fields) {
    if (!(field in value)) errors.push(`${prefix}.${field} is required`);
  }
}

function boundedString(value, prefix, max, errors) {
  if (typeof value !== 'string' || value.length === 0) {
    errors.push(`${prefix} must be a non-empty string`);
    return false;
  }
  if (value.length > max) errors.push(`${prefix} exceeds ${max} characters`);
  return true;
}

function parseDate(value, prefix, errors) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T/.test(value)) {
    errors.push(`${prefix} must be an ISO date-time string`);
    return null;
  }
  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) {
    errors.push(`${prefix} must be a valid date-time`);
    return null;
  }
  return timestamp;
}

function inspectPayload(value, depth, errors, path) {
  if (depth > 8) {
    errors.push('payload exceeds maximum depth of 8');
    return;
  }
  if (Array.isArray(value)) {
    for (let i = 0; i < value.length; i += 1) {
      inspectPayload(value[i], depth + 1, errors, `${path}[${i}]`);
    }
    return;
  }
  if (!object(value)) return;

  for (const [key, child] of Object.entries(value)) {
    const normalised = key.toLowerCase();
    if (FORBIDDEN_PAYLOAD_KEYS.has(normalised)) {
      errors.push(`${path}.${key} is a forbidden credential-bearing key`);
    }
    if (key === '__proto__' || key === 'prototype' || key === 'constructor') {
      errors.push(`${path}.${key} is forbidden`);
    }
    inspectPayload(child, depth + 1, errors, `${path}.${key}`);
  }
}

export function validateAtlasFeedEvent(event) {
  const errors = [];

  if (!exactKeys(event, TOP_LEVEL, 'event', errors)) {
    return {ok: false, errors};
  }

  required(event, [...TOP_LEVEL], 'event', errors);

  if (event.atlasFeedEvent !== CONTRACT_ID) errors.push(`event.atlasFeedEvent must equal ${CONTRACT_ID}`);
  if (event.schemaVersion !== SCHEMA_VERSION) errors.push(`event.schemaVersion must equal ${SCHEMA_VERSION}`);
  if (typeof event.eventId !== 'string' || !UUID_RE.test(event.eventId)) errors.push('event.eventId must be a UUID');
  if (typeof event.topic !== 'string' || !NAMESPACE_RE.test(event.topic)) errors.push('event.topic must be a lowercase namespaced string');

  if (exactKeys(event.source, new Set(['appId', 'capabilityId', 'releaseRef']), 'event.source', errors)) {
    required(event.source, ['appId', 'capabilityId', 'releaseRef'], 'event.source', errors);
    boundedString(event.source.appId, 'event.source.appId', 100, errors);
    boundedString(event.source.capabilityId, 'event.source.capabilityId', 160, errors);
    boundedString(event.source.releaseRef, 'event.source.releaseRef', 200, errors);
  }

  if (exactKeys(event.subject, new Set(['kind', 'key']), 'event.subject', errors)) {
    required(event.subject, ['kind', 'key'], 'event.subject', errors);
    boundedString(event.subject.kind, 'event.subject.kind', 64, errors);
    boundedString(event.subject.key, 'event.subject.key', 200, errors);
  }

  if (exactKeys(event.timing, new Set(['occurredAt', 'publishedAt', 'freshForSeconds', 'expiresAt']), 'event.timing', errors)) {
    required(event.timing, ['occurredAt', 'publishedAt', 'freshForSeconds'], 'event.timing', errors);
    const occurredAt = parseDate(event.timing.occurredAt, 'event.timing.occurredAt', errors);
    const publishedAt = parseDate(event.timing.publishedAt, 'event.timing.publishedAt', errors);
    if (occurredAt !== null && publishedAt !== null && publishedAt < occurredAt) {
      errors.push('event.timing.publishedAt must not precede occurredAt');
    }
    if (!Number.isInteger(event.timing.freshForSeconds) || event.timing.freshForSeconds < 0 || event.timing.freshForSeconds > 604800) {
      errors.push('event.timing.freshForSeconds must be an integer from 0 to 604800');
    }
    if ('expiresAt' in event.timing) {
      const expiresAt = parseDate(event.timing.expiresAt, 'event.timing.expiresAt', errors);
      if (expiresAt !== null && publishedAt !== null && expiresAt <= publishedAt) {
        errors.push('event.timing.expiresAt must be after publishedAt');
      }
    }
  }

  if (exactKeys(event.audience, new Set(['mode', 'grantId', 'dataClass']), 'event.audience', errors)) {
    required(event.audience, ['mode', 'dataClass'], 'event.audience', errors);
    if (!AUDIENCE_MODES.has(event.audience.mode)) errors.push('event.audience.mode is invalid');
    if (!DATA_CLASSES.has(event.audience.dataClass)) errors.push('event.audience.dataClass is invalid');
    if (event.audience.mode === 'grant') {
      boundedString(event.audience.grantId, 'event.audience.grantId', 160, errors);
    } else if ('grantId' in event.audience) {
      errors.push('event.audience.grantId is allowed only when mode=grant');
    }
  }

  if (exactKeys(event.provenance, new Set(['mode', 'sourceObservedAt', 'evidenceRefs']), 'event.provenance', errors)) {
    required(event.provenance, ['mode', 'sourceObservedAt', 'evidenceRefs'], 'event.provenance', errors);
    if (!PROVENANCE_MODES.has(event.provenance.mode)) errors.push('event.provenance.mode is invalid');
    parseDate(event.provenance.sourceObservedAt, 'event.provenance.sourceObservedAt', errors);
    if (!Array.isArray(event.provenance.evidenceRefs) || event.provenance.evidenceRefs.length > 12) {
      errors.push('event.provenance.evidenceRefs must be an array with at most 12 items');
    } else {
      for (let i = 0; i < event.provenance.evidenceRefs.length; i += 1) {
        boundedString(event.provenance.evidenceRefs[i], `event.provenance.evidenceRefs[${i}]`, 240, errors);
      }
      if (event.provenance.mode !== 'first_party' && event.provenance.evidenceRefs.length === 0) {
        errors.push('non-first-party provenance requires at least one evidenceRef');
      }
    }
  }

  if (exactKeys(event.payloadContract, new Set(['schemaRef', 'schemaVersion']), 'event.payloadContract', errors)) {
    required(event.payloadContract, ['schemaRef', 'schemaVersion'], 'event.payloadContract', errors);
    if (typeof event.payloadContract.schemaRef !== 'string' || !NAMESPACE_RE.test(event.payloadContract.schemaRef)) {
      errors.push('event.payloadContract.schemaRef must be a lowercase namespaced string');
    }
    if (typeof event.payloadContract.schemaVersion !== 'string' || !SEMVER_RE.test(event.payloadContract.schemaVersion)) {
      errors.push('event.payloadContract.schemaVersion must be semver');
    }
  }

  if (!object(event.payload)) {
    errors.push('event.payload must be an object');
  } else {
    let size = Infinity;
    try {
      size = Buffer.byteLength(JSON.stringify(event.payload), 'utf8');
    } catch {
      errors.push('event.payload must be JSON serializable');
    }
    if (size > 65536) errors.push('event.payload exceeds 65536 UTF-8 bytes');
    inspectPayload(event.payload, 1, errors, 'event.payload');
  }

  return {ok: errors.length === 0, errors};
}

export const ATLAS_FEED_EVENT_CONTRACT = Object.freeze({
  id: CONTRACT_ID,
  schemaVersion: SCHEMA_VERSION,
  maximumPayloadBytes: 65536,
  maximumPayloadDepth: 8,
  maximumFreshnessSeconds: 604800
});
