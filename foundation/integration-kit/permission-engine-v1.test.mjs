import test from 'node:test';
import assert from 'node:assert/strict';
import {evaluateAccess} from './permission-engine-v1.mjs';

const shineId='11111111-1111-4111-8111-111111111111';
const resourceId='22222222-2222-4222-8222-222222222222';
const grantId='33333333-3333-4333-8333-333333333333';
const requestId='44444444-4444-4444-8444-444444444444';

const request={
  requestId,
  appId:'shine.travel',
  shineId,
  scope:'vault.location.read',
  purpose:'travel.home-airport',
  resourceId,
  resourceCategory:'profile.location'
};

const resource={
  resourceId,
  ownerShineId:shineId,
  category:'profile.location'
};

const grant={
  grantId,
  ownerShineId:shineId,
  appId:'shine.travel',
  scope:'vault.location.read',
  purpose:'travel.home-airport',
  resourceSelector:{resourceId},
  status:'active',
  issuedAt:'2026-09-01T00:00:00Z',
  expiresAt:'2026-12-01T00:00:00Z'
};

const now='2026-09-26T06:00:00Z';

test('allows an exact active grant match',()=>{
  assert.deepEqual(evaluateAccess({request,resource,grants:[grant],now}),{
    requestId,
    decision:'allow',
    reasonCode:'grant-match',
    grantId
  });
});

test('denies when the app has no matching grant',()=>{
  const result=evaluateAccess({request,resource,grants:[{...grant,appId:'shine.dive'}],now});
  assert.equal(result.decision,'deny');
  assert.equal(result.reasonCode,'no-matching-grant');
});

test('denies a scope escalation',()=>{
  const result=evaluateAccess({request:{...request,scope:'vault.location.write'},resource,grants:[grant],now});
  assert.equal(result.reasonCode,'scope-mismatch');
});

test('denies a purpose change',()=>{
  const result=evaluateAccess({request:{...request,purpose:'advertising.targeting'},resource,grants:[grant],now});
  assert.equal(result.reasonCode,'purpose-mismatch');
});

test('denies a different resource',()=>{
  const result=evaluateAccess({
    request:{...request,resourceId:'55555555-5555-4555-8555-555555555555'},
    resource:{...resource,resourceId:'55555555-5555-4555-8555-555555555555'},
    grants:[grant],
    now
  });
  assert.equal(result.reasonCode,'resource-mismatch');
});

test('denies a revoked grant',()=>{
  const result=evaluateAccess({request,resource,grants:[{...grant,status:'revoked',revokedAt:'2026-09-20T00:00:00Z'}],now});
  assert.equal(result.reasonCode,'grant-revoked');
});

test('denies an expired grant',()=>{
  const result=evaluateAccess({request,resource,grants:[{...grant,expiresAt:'2026-09-25T00:00:00Z'}],now});
  assert.equal(result.reasonCode,'grant-expired');
});

test('denies a resource owned by another Shine identity',()=>{
  const result=evaluateAccess({
    request,
    resource:{...resource,ownerShineId:'66666666-6666-4666-8666-666666666666'},
    grants:[grant],
    now
  });
  assert.equal(result.reasonCode,'resource-owner-mismatch');
});

test('Shine Defence can veto an otherwise valid grant',()=>{
  const result=evaluateAccess({request,resource,grants:[grant],now,defenceDecision:'deny'});
  assert.equal(result.reasonCode,'defence-denied');
});

test('Foundation denial does not define app standalone behaviour',()=>{
  const result=evaluateAccess({request,resource,grants:[],now});
  assert.equal(result.decision,'deny');
  assert.equal(Object.hasOwn(result,'disableApp'),false);
});
