#!/usr/bin/env node
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';

const root=fileURLToPath(new URL('../../../',import.meta.url));
const ledger=JSON.parse(readFileSync(join(root,'security/shine-defence/ecosystem-profile-ledger-v1.json'),'utf8'));
const sources=JSON.parse(readFileSync(join(root,'security/shine-defence/deployment-sources-v1.json'),'utf8'));
const observations=JSON.parse(readFileSync(join(root,'security/shine-defence/deployment-observations-v1.json'),'utf8'));
const exceptions=JSON.parse(readFileSync(join(root,'security/shine-defence/deployment-source-exceptions-v1.json'),'utf8'));

export function buildCoverage({ledger,sources,observations,exceptions}){
  const src=new Map((sources.sources||[]).map(s=>[s.appId,s]));
  const obs=new Set((observations.observations||[]).map(o=>o.appId));
  const exc=new Map((exceptions.exceptions||[]).map(e=>[e.appId,e]));
  const items=[];
  for(const app of [...(ledger.apps||[])].sort((a,b)=>a.id.localeCompare(b.id))){
    const source=src.get(app.id),exception=exc.get(app.id);
    if(source&&source.repository&&source.repository!==app.repo)throw new Error(app.id+': source repository mismatch');
    if(exception&&exception.repository!==app.repo)throw new Error(app.id+': exception repository mismatch');
    let state='unmapped';
    if(source) state=obs.has(app.id)?'observed':'mapped_unobserved';
    else if(exception?.state==='partial_service') state='partial_service';
    items.push({appId:app.id,repository:app.repo,state,source:source||null,exception:exception||null});
  }
  const counts={};for(const i of items)counts[i.state]=(counts[i.state]||0)+1;
  return {report:'shine-defence/deployment-coverage-v1',version:'1.0.0',reviewedApps:items.length,fullCoverage:(counts.observed||0)+(counts.mapped_unobserved||0),observed:counts.observed||0,partial:counts.partial_service||0,unmapped:counts.unmapped||0,states:counts,items};
}

function selfTest(){
  const r=buildCoverage({
    ledger:{apps:[{id:'a',repo:'o/a'},{id:'b',repo:'o/b'},{id:'c',repo:'o/c'},{id:'d',repo:'o/d'}]},
    sources:{sources:[{appId:'a',repository:'o/a'},{appId:'b',repository:'o/b'}]},
    observations:{observations:[{appId:'a'}]},
    exceptions:{exceptions:[{appId:'c',state:'partial_service',repository:'o/c'}]}
  });
  const s=new Map(r.items.map(i=>[i.appId,i.state]));
  if(s.get('a')!=='observed'||s.get('b')!=='mapped_unobserved'||s.get('c')!=='partial_service'||s.get('d')!=='unmapped')throw new Error('coverage state mismatch');
  console.log('SHINE DEFENCE DEPLOYMENT COVERAGE SELF-TEST: PASS 4 states');
}
export const SHINE_DEFENCE_DEPLOYMENT_COVERAGE_VERSION='1.1.0';
function main(){
  if(process.argv.includes('--self-test'))return selfTest();
  const r=buildCoverage({ledger,sources,observations,exceptions});
  console.log(process.argv.includes('--json')?JSON.stringify(r,null,2):JSON.stringify(r,null,2));
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)main();
