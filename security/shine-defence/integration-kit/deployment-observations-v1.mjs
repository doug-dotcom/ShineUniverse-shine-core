#!/usr/bin/env node
import {createHash} from 'node:crypto';
import {existsSync,readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {evaluateReleaseStatus} from './evaluate-release-status-v1.mjs';

export const SHINE_DEFENCE_DEPLOYMENT_OBSERVATIONS_VERSION='1.0.0';
const root=fileURLToPath(new URL('../../../',import.meta.url));
const P={observations:'security/shine-defence/deployment-observations-v1.json',receipts:'security/shine-defence/receipts',snapshots:'security/shine-defence/registry-snapshots',revocations:'security/shine-defence/revocations-v1.json'};
const SHA=/^[a-f0-9]{40}$/;
const ISO=/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/;
const ID=/^[a-z0-9][a-z0-9._-]{0,127}$/;
const REPO=/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const secretLike=/(?:bearer\s+[a-z0-9._-]{12,}|sk-[a-z0-9_-]{12,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(?:token|secret|password)\s*[=:]\s*[^\s]{8,})/i;
const gitBlobSha=b=>createHash('sha1').update(Buffer.from('blob '+b.length+'\0')).update(b).digest('hex');
const clean=(v,n)=>typeof v==='string'&&v.trim().length>0&&v.length<=n&&!secretLike.test(v);
const fail=m=>{throw new Error(m)};

export function validateObservationLedger(ledger){
  const failures=[];
  if(ledger?.ledger!=='shine-defence/deployment-observations-v1'||ledger.version!=='1.0.0'||!Array.isArray(ledger.observations))return ['unsupported deployment observation ledger'];
  const ids=new Set();
  for(const [i,o] of ledger.observations.entries()){
    const p='observation '+i;
    if(!ID.test(o.observationId||''))failures.push(p+': invalid observationId');
    else if(ids.has(o.observationId))failures.push(p+': duplicate observationId');
    else ids.add(o.observationId);
    if(!ID.test(o.appId||''))failures.push(p+': invalid appId');
    if(!REPO.test(o.repository||''))failures.push(p+': invalid repository');
    if(!SHA.test(o.releaseCommitSha||''))failures.push(p+': invalid releaseCommitSha');
    if(!SHA.test(o.profileBlobSha||''))failures.push(p+': invalid profileBlobSha');
    if(!ISO.test(o.observedAt||'')||!Number.isFinite(Date.parse(o.observedAt)))failures.push(p+': invalid observedAt');
    if(!clean(o.source,64)||!clean(o.reference,256))failures.push(p+': invalid or secret-like provenance');
  }
  return failures;
}

export function latestObservations(ledger){
  const failures=validateObservationLedger(ledger);if(failures.length)fail(failures.join('; '));
  const latest=new Map();
  for(const o of ledger.observations){
    const current=latest.get(o.appId);
    if(!current||o.observedAt>current.observedAt||(o.observedAt===current.observedAt&&o.observationId>current.observationId))latest.set(o.appId,o);
  }
  return latest;
}

function mapped(status){
  return {reviewed_release:'protected',unreviewed_revision:'deployment_drift',profile_drift:'profile_drift',revoked_release:'revoked',receipt_missing:'needs_review',verification_failed:'needs_review'}[status]||'needs_review';
}

export function evaluateObservation({observation,receipt,registry,registryBlobSha,revocations}){
  const raw=evaluateReleaseStatus({receipt,registry,registryBlobSha,revocations,releaseCommitSha:observation.releaseCommitSha,profileBlobSha:observation.profileBlobSha});
  return {
    appId:observation.appId,
    repository:observation.repository,
    observationId:observation.observationId,
    observedAt:observation.observedAt,
    observedReleaseCommitSha:observation.releaseCommitSha,
    observedProfileBlobSha:observation.profileBlobSha,
    state:mapped(raw.state),
    badgeCurrent:raw.badgeCurrent,
    releaseStatus:raw.state,
    details:raw
  };
}

export function loadLiveDeploymentReport(){
  const ledger=JSON.parse(readFileSync(join(root,P.observations),'utf8'));
  const latest=latestObservations(ledger);
  const revocations=JSON.parse(readFileSync(join(root,P.revocations),'utf8'));
  const items=[];
  for(const observation of [...latest.values()].sort((a,b)=>a.appId.localeCompare(b.appId))){
    const receiptPath=join(root,P.receipts,observation.appId+'.json');
    let receipt=null,registry=null,registryBlobSha=null;
    if(existsSync(receiptPath)){
      try{
        receipt=JSON.parse(readFileSync(receiptPath,'utf8'));
        const snapshotPath=join(root,P.snapshots,receipt.registryBlobSha+'.json');
        const bytes=readFileSync(snapshotPath);
        registry=JSON.parse(bytes.toString('utf8'));
        registryBlobSha=gitBlobSha(bytes);
      }catch{
        receipt=receipt||{appId:observation.appId};
      }
    }
    items.push(evaluateObservation({observation,receipt,registry,registryBlobSha,revocations}));
  }
  const states={};for(const i of items)states[i.state]=(states[i.state]||0)+1;
  return {report:'shine-defence/deployment-observations-v1',version:'1.0.0',observedApps:items.length,states,items};
}

function selfTest(){
  const registry={registry:'shine-defence/canonical-registry-v1',version:'1.0.0',entries:[{id:'baseline',version:'1.0.0',blobSha:'1'.repeat(40)},{id:'release-claim',version:'1.0.0',blobSha:'2'.repeat(40)},{id:'certification-receipt',version:'1.0.0',blobSha:'3'.repeat(40)}]};
  const receipt={receipt:'shine-defence/certification-receipt-v1',version:'1.0.0',appId:'app',reviewCommitSha:'a'.repeat(40),profileBlobSha:'b'.repeat(40),policies:['baseline'],registryVersion:'1.0.0',registryBlobSha:'c'.repeat(40),releaseClaimContractVersion:'1.0.0',releaseClaimContractBlobSha:'2'.repeat(40)};
  const revocations={ledger:'shine-defence/revocations-v1',version:'1.0.0',revocations:[]};
  const base={observationId:'obs-1',appId:'app',repository:'owner/app',releaseCommitSha:'a'.repeat(40),profileBlobSha:'b'.repeat(40),observedAt:'2026-09-27T01:00:00.000Z',source:'railway',reference:'deploy-1'};
  const cases=[
    ['protected',base,receipt,revocations],
    ['deployment_drift',{...base,releaseCommitSha:'d'.repeat(40)},receipt,revocations],
    ['profile_drift',{...base,profileBlobSha:'d'.repeat(40)},receipt,revocations],
    ['revoked',base,receipt,{...revocations,revocations:[{revocationId:'r1',appId:'app',reviewCommitSha:'a'.repeat(40),profileBlobSha:'b'.repeat(40),revokedAt:'2026-09-27T00:00:00Z',reasonCode:'other',publicReason:'withdrawn'}]}],
    ['needs_review',base,null,revocations]
  ];
  for(const [expected,observation,r,rev] of cases){
    const out=evaluateObservation({observation,receipt:r,registry,registryBlobSha:'c'.repeat(40),revocations:rev});
    if(out.state!==expected)fail('expected '+expected+', got '+out.state);
  }
  const ledger={ledger:'shine-defence/deployment-observations-v1',version:'1.0.0',observations:[base,{...base,observationId:'obs-2',observedAt:'2026-09-27T02:00:00.000Z',releaseCommitSha:'d'.repeat(40)}]};
  if(latestObservations(ledger).get('app').observationId!=='obs-2')fail('latest observation selection failed');
  console.log('SHINE DEFENCE DEPLOYMENT OBSERVATIONS SELF-TEST: PASS 5 states + deterministic latest selection');
}

function main(){const a=process.argv.slice(2);if(a.includes('--self-test'))return selfTest();const r=loadLiveDeploymentReport();console.log(a.includes('--json')?JSON.stringify(r,null,2):JSON.stringify(r,null,2))}
main();
