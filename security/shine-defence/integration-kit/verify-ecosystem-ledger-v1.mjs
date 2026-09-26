#!/usr/bin/env node
import {readFileSync} from 'node:fs';
const root=new URL('../../../',import.meta.url);
const registry=JSON.parse(readFileSync(new URL('security/shine-defence/canonical-registry-v1.json',root),'utf8'));
const ledger=JSON.parse(readFileSync(new URL('security/shine-defence/ecosystem-profile-ledger-v1.json',root),'utf8'));
const canonical=new Set(registry.entries.map(x=>x.id));
const ids=new Set(),repos=new Set(),failures=[];
if(ledger.ledger!=='shine-defence/ecosystem-profile-ledger-v1'||ledger.version!=='1.1.0')failures.push('unsupported ecosystem ledger version');
for(const app of ledger.apps){
 if(ids.has(app.id))failures.push(app.id+': duplicate app id'); ids.add(app.id);
 if(repos.has(app.repo))failures.push(app.id+': duplicate repository'); repos.add(app.repo);
 if(!/^[a-f0-9]{40}$/.test(app.reviewCommitSha||''))failures.push(app.id+': invalid reviewed commit sha');
 if(!/^[a-f0-9]{40}$/.test(app.profileBlobSha||''))failures.push(app.id+': invalid profile blob sha');
 if(!/^\d+\.\d+\.\d+$/.test(app.profileVersion||''))failures.push(app.id+': invalid profile version');
 if(typeof app.path!=='string'||!app.path.startsWith('security/shine-defence'))failures.push(app.id+': profile path outside Defence namespace');
 if(!Array.isArray(app.policies)||!app.policies.length)failures.push(app.id+': no canonical policies');
 for(const policy of app.policies)if(!canonical.has(policy))failures.push(app.id+': unknown canonical policy '+policy);
}
if(failures.length){for(const failure of failures)console.error('FAIL '+failure);process.exit(1)}
console.log('SHINE DEFENCE ECOSYSTEM LEDGER: PASS '+ledger.apps.length+' reviewed app profiles');
