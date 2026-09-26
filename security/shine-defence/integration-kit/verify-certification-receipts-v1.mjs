#!/usr/bin/env node
import {createHash} from 'node:crypto';
import {readdirSync,readFileSync} from 'node:fs';

const root=new URL('../../../',import.meta.url);
const ledger=JSON.parse(readFileSync(new URL('security/shine-defence/ecosystem-profile-ledger-v1.json',root),'utf8'));
const receiptsDir=new URL('security/shine-defence/receipts/',root);
const snapshotsDir=new URL('security/shine-defence/registry-snapshots/',root);
const ledgerApps=new Map(ledger.apps.map(app=>[app.id,app]));
const files=readdirSync(receiptsDir).filter(name=>name.endsWith('.json')).sort();
const failures=[],seen=new Set(),snapshotCache=new Map();
const gitBlobSha=bytes=>createHash('sha1').update(Buffer.from('blob '+bytes.length+'\0')).update(bytes).digest('hex');

function registryFor(receipt,file){
  const sha=receipt.registryBlobSha;
  if(!/^[a-f0-9]{40}$/.test(sha||'')){failures.push(file+': invalid registry blob sha');return null}
  if(snapshotCache.has(sha))return snapshotCache.get(sha);
  let bytes;
  try{bytes=readFileSync(new URL(sha+'.json',snapshotsDir))}catch{failures.push(file+': registry snapshot missing '+sha);return null}
  const actual=gitBlobSha(bytes);
  if(actual!==sha){failures.push(file+': registry snapshot hash mismatch '+actual+' != '+sha);return null}
  let registry;
  try{registry=JSON.parse(bytes.toString('utf8'))}catch{failures.push(file+': registry snapshot invalid JSON');return null}
  snapshotCache.set(sha,registry);
  return registry;
}

for(const file of files){
  let receipt;try{receipt=JSON.parse(readFileSync(new URL(file,receiptsDir),'utf8'))}catch{failures.push(file+': invalid JSON');continue}
  if(receipt.receipt!=='shine-defence/certification-receipt-v1'||receipt.version!=='1.0.0')failures.push(file+': unsupported receipt');
  if(seen.has(receipt.appId))failures.push(file+': duplicate app receipt');seen.add(receipt.appId);
  const app=ledgerApps.get(receipt.appId);
  if(!app){failures.push(file+': app not in reviewed ledger');continue}
  for(const [key,expected] of Object.entries({repository:app.repo,reviewCommitSha:app.reviewCommitSha,profilePath:app.path,profileBlobSha:app.profileBlobSha,profileVersion:app.profileVersion})){
    if(receipt[key]!==expected)failures.push(file+': '+key+' does not match reviewed ledger');
  }
  if(JSON.stringify(receipt.policies)!==JSON.stringify(app.policies))failures.push(file+': policies do not match reviewed ledger');

  const registry=registryFor(receipt,file);
  if(!registry)continue;
  if(receipt.registryVersion!==registry.version)failures.push(file+': registry version mismatch');
  const canonical=new Map(registry.entries.map(entry=>[entry.id,entry]));
  for(const id of receipt.policies)if(!canonical.has(id))failures.push(file+': unknown canonical policy '+id);
  const release=canonical.get('release-claim');
  if(!release||receipt.releaseClaimContractVersion!==release.version||receipt.releaseClaimContractBlobSha!==release.blobSha)failures.push(file+': release-claim contract mismatch');
}
for(const id of ledgerApps.keys())if(!seen.has(id))failures.push(id+': missing certification receipt');
for(const id of seen)if(!ledgerApps.has(id))failures.push(id+': receipt has no ledger entry');
if(failures.length){for(const failure of failures)console.error('FAIL '+failure);process.exit(1)}
console.log('SHINE DEFENCE RECEIPTS: PASS '+files.length+' reviewed release receipts across '+snapshotCache.size+' immutable registry snapshot'+(snapshotCache.size===1?'':'s'));
