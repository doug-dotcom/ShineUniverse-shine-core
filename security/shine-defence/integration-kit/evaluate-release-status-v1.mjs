#!/usr/bin/env node
import {createHash} from 'node:crypto';
import {existsSync,readFileSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

const sha=/^[a-f0-9]{40}$/;
const labels={
  reviewed_release:'Protected by Shine Defence',
  revoked_release:'Defence certification withdrawn',
  unreviewed_revision:'Defence review pending for this revision',
  profile_drift:'Defence profile changed since review',
  receipt_missing:'No Defence receipt for this build',
  verification_failed:'Defence verification failed'
};
const result=(state,extra={})=>({state,badgeCurrent:state==='reviewed_release',display:labels[state],...extra});

export function evaluateReleaseStatus({receipt,registry,registryBlobSha,revocations,releaseCommitSha,profileBlobSha}){
  if(!receipt)return result('receipt_missing');
  const errors=[];
  if(receipt.receipt!=='shine-defence/certification-receipt-v1'||receipt.version!=='1.0.0')errors.push('unsupported receipt');
  for(const [name,value] of [['reviewCommitSha',receipt.reviewCommitSha],['profileBlobSha',receipt.profileBlobSha],['registryBlobSha',receipt.registryBlobSha],['releaseCommitSha',releaseCommitSha],['currentProfileBlobSha',profileBlobSha]])if(!sha.test(value||''))errors.push('invalid '+name);
  if(typeof receipt.appId!=='string'||!receipt.appId)errors.push('invalid appId');
  if(!Array.isArray(receipt.policies)||!receipt.policies.length)errors.push('missing policies');
  if(!registry||registry.registry!=='shine-defence/canonical-registry-v1'||receipt.registryVersion!==registry.version||receipt.registryBlobSha!==registryBlobSha)errors.push('registry snapshot mismatch');
  const canonical=new Map((registry?.entries||[]).map(entry=>[entry.id,entry]));
  for(const id of receipt.policies||[])if(!canonical.has(id))errors.push('unknown canonical policy '+id);
  const release=canonical.get('release-claim');
  if(!release||receipt.releaseClaimContractVersion!==release.version||receipt.releaseClaimContractBlobSha!==release.blobSha)errors.push('release-claim contract mismatch');
  const receiptContract=canonical.get('certification-receipt');
  if(!receiptContract||receiptContract.version!==receipt.version)errors.push('receipt contract mismatch');
  if(!revocations||revocations.ledger!=='shine-defence/revocations-v1'||revocations.version!=='1.0.0'||!Array.isArray(revocations.revocations))errors.push('revocation ledger invalid');
  if(errors.length)return result('verification_failed',{appId:receipt.appId||null,errors});

  const revoked=revocations.revocations.find(item=>item.appId===receipt.appId&&item.reviewCommitSha===receipt.reviewCommitSha&&item.profileBlobSha===receipt.profileBlobSha);
  const shared={appId:receipt.appId,reviewedCommitSha:receipt.reviewCommitSha,reviewedProfileBlobSha:receipt.profileBlobSha,receiptRegistryBlobSha:receipt.registryBlobSha,reviewedReleaseRevoked:Boolean(revoked)};
  if(releaseCommitSha!==receipt.reviewCommitSha)return result('unreviewed_revision',shared);
  if(profileBlobSha!==receipt.profileBlobSha)return result('profile_drift',shared);
  if(revoked)return result('revoked_release',{...shared,revocationId:revoked.revocationId,revokedAt:revoked.revokedAt,reasonCode:revoked.reasonCode,publicReason:revoked.publicReason,replacementReviewCommitSha:revoked.replacementReviewCommitSha||null});
  return result('reviewed_release',shared);
}

function gitBlobSha(bytes){return createHash('sha1').update(Buffer.from('blob '+bytes.length+'\0')).update(bytes).digest('hex')}

function selfTest(){
  const registry={registry:'shine-defence/canonical-registry-v1',version:'1.0.0',entries:[
    {id:'baseline',version:'1.0.0',blobSha:'1'.repeat(40)},
    {id:'release-claim',version:'1.0.0',blobSha:'2'.repeat(40)},
    {id:'certification-receipt',version:'1.0.0',blobSha:'3'.repeat(40)}
  ]};
  const receipt={receipt:'shine-defence/certification-receipt-v1',version:'1.0.0',appId:'demo',reviewCommitSha:'a'.repeat(40),profileBlobSha:'b'.repeat(40),policies:['baseline'],registryVersion:'1.0.0',registryBlobSha:'c'.repeat(40),releaseClaimContractVersion:'1.0.0',releaseClaimContractBlobSha:'2'.repeat(40)};
  const revocations={ledger:'shine-defence/revocations-v1',version:'1.0.0',revocations:[{revocationId:'r1',appId:'demo',reviewCommitSha:'a'.repeat(40),profileBlobSha:'b'.repeat(40),revokedAt:'2026-01-01T00:00:00Z',reasonCode:'critical_defect',publicReason:'withdrawn'}]};
  const cases=[
    ['receipt_missing',evaluateReleaseStatus({receipt:null,registry,registryBlobSha:'c'.repeat(40),revocations,releaseCommitSha:'a'.repeat(40),profileBlobSha:'b'.repeat(40)})],
    ['verification_failed',evaluateReleaseStatus({receipt:{...receipt,registryBlobSha:'d'.repeat(40)},registry,registryBlobSha:'c'.repeat(40),revocations,releaseCommitSha:'a'.repeat(40),profileBlobSha:'b'.repeat(40)})],
    ['unreviewed_revision',evaluateReleaseStatus({receipt,registry,registryBlobSha:'c'.repeat(40),revocations,releaseCommitSha:'d'.repeat(40),profileBlobSha:'b'.repeat(40)})],
    ['profile_drift',evaluateReleaseStatus({receipt,registry,registryBlobSha:'c'.repeat(40),revocations,releaseCommitSha:'a'.repeat(40),profileBlobSha:'d'.repeat(40)})],
    ['revoked_release',evaluateReleaseStatus({receipt,registry,registryBlobSha:'c'.repeat(40),revocations,releaseCommitSha:'a'.repeat(40),profileBlobSha:'b'.repeat(40)})],
    ['reviewed_release',evaluateReleaseStatus({receipt,registry,registryBlobSha:'c'.repeat(40),revocations:{...revocations,revocations:[]},releaseCommitSha:'a'.repeat(40),profileBlobSha:'b'.repeat(40)})]
  ];
  for(const [expected,value] of cases)if(value.state!==expected)throw new Error('expected '+expected+', got '+value.state);
  if(!cases.at(-1)[1].badgeCurrent||cases.slice(0,-1).some(([,value])=>value.badgeCurrent))throw new Error('badgeCurrent state error');
  console.log('SHINE DEFENCE RELEASE STATUS: PASS '+cases.length+' states');
}

function main(){
  const args=process.argv.slice(2);
  if(args.includes('--self-test'))return selfTest();
  const value=name=>{const i=args.indexOf(name);return i>=0?args[i+1]:undefined};
  const receiptPath=value('--receipt');
  const releaseCommitSha=value('--release-sha'),profileBlobSha=value('--profile-blob-sha');
  if(!sha.test(releaseCommitSha||'')||!sha.test(profileBlobSha||'')){console.error('release/profile SHA required');process.exit(64)}
  if(!receiptPath||!existsSync(receiptPath)){console.log(JSON.stringify(result('receipt_missing')));process.exitCode=2;return}
  const receipt=JSON.parse(readFileSync(receiptPath,'utf8'));
  const snapshotsDir=value('--registry-snapshots-dir')||'security/shine-defence/registry-snapshots';
  if(!sha.test(receipt.registryBlobSha||'')){console.log(JSON.stringify(result('verification_failed',{errors:['invalid registryBlobSha']})));process.exitCode=2;return}
  const snapshotPath=join(snapshotsDir,receipt.registryBlobSha+'.json');
  let bytes,registry;
  try{bytes=readFileSync(snapshotPath);registry=JSON.parse(bytes.toString('utf8'))}catch{console.log(JSON.stringify(result('verification_failed',{errors:['registry snapshot unavailable']})));process.exitCode=2;return}
  const registryBlobSha=gitBlobSha(bytes);
  let revocations;
  try{revocations=JSON.parse(readFileSync(value('--revocations')||'security/shine-defence/revocations-v1.json','utf8'))}catch{revocations=null}
  const output=evaluateReleaseStatus({receipt,registry,registryBlobSha,revocations,releaseCommitSha,profileBlobSha});
  console.log(JSON.stringify(output));
  process.exitCode=output.badgeCurrent?0:2;
}
if(import.meta.url===pathToFileURL(process.argv[1]).href)main();
