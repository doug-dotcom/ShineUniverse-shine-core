import test from 'node:test';
import assert from 'node:assert/strict';
import {createPublicDefenceStatusService} from './defence-status-v1.mjs';

const reviewed='a'.repeat(40),profile='b'.repeat(40),later='c'.repeat(40),changed='d'.repeat(40);
const ledger={
  ledger:'shine-defence/ecosystem-profile-ledger-v1',version:'1.1.0',
  apps:[{id:'shine-daash',reviewCommitSha:reviewed,profileBlobSha:profile,profileVersion:'1.3.0',policies:['baseline','exercise-companion-safety']}]
};
const empty={ledger:'shine-defence/revocations-v1',version:'1.0.0',revocations:[]};

test('exact reviewed release is current',()=>{
  const evaluate=createPublicDefenceStatusService({ledger,revocations:empty});
  const out=evaluate({appId:'shine-daash',releaseSha:reviewed,profileBlobSha:profile});
  assert.equal(out.state,'reviewed_release');assert.equal(out.badgeCurrent,true);
  assert.equal(out.display,'Protected by Shine Defence');
  assert.deepEqual(out.policies,['baseline','exercise-companion-safety']);
});

test('later app commit does not inherit certification',()=>{
  const evaluate=createPublicDefenceStatusService({ledger,revocations:empty});
  const out=evaluate({appId:'shine-daash',releaseSha:later,profileBlobSha:profile});
  assert.equal(out.state,'unreviewed_revision');assert.equal(out.badgeCurrent,false);
});

test('profile drift on reviewed commit is not current',()=>{
  const evaluate=createPublicDefenceStatusService({ledger,revocations:empty});
  const out=evaluate({appId:'shine-daash',releaseSha:reviewed,profileBlobSha:changed});
  assert.equal(out.state,'profile_drift');assert.equal(out.badgeCurrent,false);
});

test('revocation overrides exact reviewed status',()=>{
  const revocations={...empty,revocations:[{
    revocationId:'rev-1',appId:'shine-daash',reviewCommitSha:reviewed,profileBlobSha:profile,
    revokedAt:'2026-09-26T08:00:00Z',reasonCode:'critical_defect',publicReason:'Release withdrawn.'
  }]};
  const evaluate=createPublicDefenceStatusService({ledger,revocations});
  const out=evaluate({appId:'shine-daash',releaseSha:reviewed,profileBlobSha:profile});
  assert.equal(out.state,'revoked_release');assert.equal(out.badgeCurrent,false);
  assert.equal(out.revocation.publicReason,'Release withdrawn.');
});

test('unknown app is explicitly uncertified without leaking repository metadata',()=>{
  const evaluate=createPublicDefenceStatusService({ledger,revocations:empty});
  const out=evaluate({appId:'unknown-app',releaseSha:reviewed,profileBlobSha:profile});
  assert.equal(out.state,'uncertified');assert.equal(out.badgeCurrent,false);
  assert.equal(Object.hasOwn(out,'reviewedCommitSha'),false);
});

test('malformed query fails before lookup',()=>{
  const evaluate=createPublicDefenceStatusService({ledger,revocations:empty});
  assert.throws(()=>evaluate({appId:'../bad',releaseSha:'no',profileBlobSha:profile}),/invalid/);
});
