#!/usr/bin/env node
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('../../../',import.meta.url));
const sources=JSON.parse(readFileSync(join(root,'security/shine-defence/deployment-sources-v1.json'),'utf8'));
const ledger=JSON.parse(readFileSync(join(root,'security/shine-defence/ecosystem-profile-ledger-v1.json'),'utf8'));
const failures=[];
if(sources.contract!=='shine-defence/deployment-sources-v1'||sources.version!=='1.0.0'||!Array.isArray(sources.sources))failures.push('unsupported source registry');
const apps=new Map((ledger.apps||[]).map(a=>[a.id,a])),ids=new Set(),scopes=new Set();
for(const s of sources.sources||[]){
  if(ids.has(s.appId))failures.push(s.appId+': duplicate app source');ids.add(s.appId);
  const scope=[s.provider,s.projectId,s.environmentId,s.serviceId].join(':');
  if(scopes.has(scope))failures.push(s.appId+': duplicate provider scope');scopes.add(scope);
  if(s.provider!=='railway')failures.push(s.appId+': unsupported provider');
  const app=apps.get(s.appId);
  if(!app)failures.push(s.appId+': source app is not canonically reviewed');
  else{
    if(s.repository!==app.repo)failures.push(s.appId+': repository differs from reviewed ledger');
    if(s.profilePath!==app.path)failures.push(s.appId+': profile path differs from reviewed ledger');
  }
  for(const k of ['projectId','environmentId','serviceId'])if(typeof s[k]!=='string'||!s[k])failures.push(s.appId+': missing '+k);
}
if(failures.length){for(const f of failures)console.error('FAIL '+f);process.exit(1)}
console.log('SHINE DEFENCE DEPLOYMENT SOURCES: PASS '+sources.sources.length+' reviewed app source'+(sources.sources.length===1?'':'s'));
