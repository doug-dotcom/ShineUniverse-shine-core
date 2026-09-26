#!/usr/bin/env node
import {readFileSync} from 'node:fs';
const root=new URL('../../../',import.meta.url);
const ledger=JSON.parse(readFileSync(new URL('security/shine-defence/ecosystem-profile-ledger-v1.json',root),'utf8'));
const revocations=JSON.parse(readFileSync(new URL('security/shine-defence/revocations-v1.json',root),'utf8'));
const apps=new Map(ledger.apps.map(app=>[app.id,app])),ids=new Set(),targets=new Set(),failures=[];
const reasonCodes=new Set(['critical_defect','credential_exposure','policy_breach','supply_chain','other']);
if(revocations.ledger!=='shine-defence/revocations-v1'||revocations.version!=='1.0.0'||!Array.isArray(revocations.revocations))failures.push('unsupported revocation ledger');
for(const item of revocations.revocations||[]){
  if(typeof item.revocationId!=='string'||!item.revocationId.trim()||ids.has(item.revocationId))failures.push('invalid or duplicate revocation id'); else ids.add(item.revocationId);
  const app=apps.get(item.appId);
  if(!app)failures.push(item.revocationId+': app not in reviewed ledger');
  else if(item.reviewCommitSha!==app.reviewCommitSha||item.profileBlobSha!==app.profileBlobSha)failures.push(item.revocationId+': target does not match exact reviewed release');
  const target=item.appId+'|'+item.reviewCommitSha+'|'+item.profileBlobSha;if(targets.has(target))failures.push(item.revocationId+': duplicate release revocation');else targets.add(target);
  if(!reasonCodes.has(item.reasonCode))failures.push(item.revocationId+': invalid reason code');
  if(typeof item.publicReason!=='string'||!item.publicReason.trim()||item.publicReason.length>500)failures.push(item.revocationId+': invalid public reason');
  if(typeof item.revokedAt!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/.test(item.revokedAt)||!Number.isFinite(Date.parse(item.revokedAt)))failures.push(item.revocationId+': invalid revokedAt');
  if(item.replacementReviewCommitSha!==undefined&&(!/^[a-f0-9]{40}$/.test(item.replacementReviewCommitSha)||item.replacementReviewCommitSha===item.reviewCommitSha))failures.push(item.revocationId+': invalid replacement review commit');
}
if(failures.length){for(const failure of failures)console.error('FAIL '+failure);process.exit(1)}
console.log('SHINE DEFENCE REVOCATIONS: PASS '+(revocations.revocations||[]).length+' revocation record'+((revocations.revocations||[]).length===1?'':'s'));
