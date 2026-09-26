#!/usr/bin/env node
import {createHash} from 'node:crypto';
import {readdirSync,readFileSync} from 'node:fs';

const root=new URL('../../../',import.meta.url);
const registryBytes=readFileSync(new URL('security/shine-defence/canonical-registry-v1.json',root));
const registry=JSON.parse(registryBytes.toString('utf8'));
const registryBlobSha=createHash('sha1').update(Buffer.from('blob '+registryBytes.length+'\0')).update(registryBytes).digest('hex');
const ledger=JSON.parse(readFileSync(new URL('security/shine-defence/ecosystem-profile-ledger-v1.json',root),'utf8'));
const receiptsDir=new URL('security/shine-defence/receipts/',root);
const canonical=new Map(registry.entries.map(entry=>[entry.id,entry]));
const ledgerApps=new Map(ledger.apps.map(app=>[app.id,app]));
const files=readdirSync(receiptsDir).filter(name=>name.endsWith('.json')).sort();
const failures=[],seen=new Set();
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
  for(const id of receipt.policies)if(!canonical.has(id))failures.push(file+': unknown canonical policy '+id);
  if(receipt.registryVersion!==registry.version||receipt.registryBlobSha!==registryBlobSha)failures.push(file+': canonical registry identity mismatch');
  const release=canonical.get('release-claim');
  if(!release||receipt.releaseClaimContractVersion!==release.version||receipt.releaseClaimContractBlobSha!==release.blobSha)failures.push(file+': release-claim contract mismatch');
}
for(const id of ledgerApps.keys())if(!seen.has(id))failures.push(id+': missing certification receipt');
for(const id of seen)if(!ledgerApps.has(id))failures.push(id+': receipt has no ledger entry');
if(failures.length){for(const failure of failures)console.error('FAIL '+failure);process.exit(1)}
console.log('SHINE DEFENCE RECEIPTS: PASS '+files.length+' reviewed release receipts');
