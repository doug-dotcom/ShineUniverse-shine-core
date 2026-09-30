import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {
  validatePromotedReleaseResponse,
  assertPromotedReleaseResponse,
  PROMOTED_RELEASE_RESPONSE_CONTRACT
} from './promoted-release-response-v1.mjs';

const promoted={
  foundationPromotedReleaseResponse:'shine-foundation/promoted-release-response-v1',
  schemaVersion:'1.0.0',
  environment:'production',
  evaluatedAt:'2026-09-30T03:26:26.478533+00:00',
  available:true,
  state:'promoted',
  reasonCode:'promotion-closure-current',
  promotionClosureState:'closed',
  promotedRelease:{
    bindingId:'187d5232-83b5-4c2f-acc6-62da7a9a9515',
    releaseRef:'foundation:layer-58:1a8148a8',
    foundationLayer:58,
    sourceRef:'github://doug-dotcom/ShineUniverse-shine-core/commit/1a8148a8eb748a19ac03107d9e9ec7313297384b',
    sourceCommitSha:'1a8148a8eb748a19ac03107d9e9ec7313297384b',
    runtimeVersion:'90',
    artifactSha256:'3294e28293df667224ed9ab2551e2e5a6a88bab6f6805791bec14e7d22512692',
    closureId:'df864db1-abe4-4a28-b784-7a1d7b83dc5d',
    closureSha256:'38b479bb951e69e53438b8cf13637b4c67dba5f7965f6d520f90344721bc2b87',
    canonicalSourceTruthFingerprint:'3e7ce8f50385b3fadddddc247d3573bf',
    closedAt:'2026-09-30T03:16:26.554513+00:00'
  },
  promotedReleaseSha256:'ed4e6f4d7234161a6261fc98d58fd3bfd05ca35045fabfdc57dbf8c5ac51040f',
  runtimeReadinessClaimed:false,
  mutatesAuthoritativeTruth:false
};

const hold={
  foundationPromotedReleaseResponse:'shine-foundation/promoted-release-response-v1',
  schemaVersion:'1.0.0',
  environment:'production',
  evaluatedAt:'2026-09-30T03:26:26.478533+00:00',
  available:false,
  state:'hold',
  reasonCode:'promotion-closure-no-longer-current',
  promotionClosureState:'stale',
  promotedRelease:null,
  runtimeReadinessClaimed:false,
  mutatesAuthoritativeTruth:false
};

test('canonical schema identity matches validator identity',()=>{
  const schema=JSON.parse(readFileSync(
    new URL('../schemas/promoted-release-response-v1.schema.json',import.meta.url),
    'utf8'
  ));
  assert.equal(schema.$id,PROMOTED_RELEASE_RESPONSE_CONTRACT.id);
  assert.equal(schema.schemaVersion,PROMOTED_RELEASE_RESPONSE_CONTRACT.schemaVersion);
  assert.equal(schema.properties.runtimeReadinessClaimed.const,false);
  assert.equal(schema.properties.mutatesAuthoritativeTruth.const,false);
});

test('accepts a production-shaped promoted response',()=>{
  const result=validatePromotedReleaseResponse(promoted);
  assert.deepEqual(result,{ok:true,errors:[]});
  assert.deepEqual(assertPromotedReleaseResponse(promoted),promoted);
});

test('accepts a fail-closed hold response',()=>{
  assert.deepEqual(validatePromotedReleaseResponse(hold),{ok:true,errors:[]});
});

test('rejects promoted state without a current closure',()=>{
  const value=structuredClone(promoted);
  value.promotionClosureState='stale';
  assert.equal(validatePromotedReleaseResponse(value).ok,false);
});

test('rejects hold responses carrying a promoted release',()=>{
  const value={...hold,promotedRelease:structuredClone(promoted.promotedRelease)};
  assert.equal(validatePromotedReleaseResponse(value).ok,false);
});

test('rejects readiness or mutation claims',()=>{
  const readiness={...promoted,runtimeReadinessClaimed:true};
  const mutation={...promoted,mutatesAuthoritativeTruth:true};
  assert.equal(validatePromotedReleaseResponse(readiness).ok,false);
  assert.equal(validatePromotedReleaseResponse(mutation).ok,false);
});

test('rejects malformed provenance and unknown fields',()=>{
  const badSha=structuredClone(promoted);
  badSha.promotedRelease.sourceCommitSha='ABC';
  assert.equal(validatePromotedReleaseResponse(badSha).ok,false);

  const extra={...promoted,secretShortcut:true};
  assert.equal(validatePromotedReleaseResponse(extra).ok,false);
});

test('rejects promoted release fingerprint omission',()=>{
  const value=structuredClone(promoted);
  delete value.promotedReleaseSha256;
  assert.equal(validatePromotedReleaseResponse(value).ok,false);
});
