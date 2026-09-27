#!/usr/bin/env node
import {spawnSync} from 'node:child_process';
import {readFileSync,renameSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {validateObservationLedger} from './deployment-observations-v1.mjs';

export const SHINE_DEFENCE_DEPLOYMENT_COLLECTOR_VERSION='1.0.0';
const root=fileURLToPath(new URL('../../../',import.meta.url));
const sourcesPath='security/shine-defence/deployment-sources-v1.json';
const observationsPath='security/shine-defence/deployment-observations-v1.json';
const SHA=/^[a-f0-9]{40}$/;
const json=v=>JSON.stringify(v,null,2)+'\n';
const fail=m=>{throw new Error(m)};
function atomicWrite(path,bytes){const t=path+'.tmp-'+process.pid;writeFileSync(t,bytes);renameSync(t,path)}
function command(bin,args,env=process.env){
  const r=spawnSync(bin,args,{cwd:root,encoding:'utf8',env});
  if(r.status!==0)fail(bin+' failed: '+String(r.stderr||r.stdout).trim());
  return r.stdout;
}
export function observationFromSource({source,deployment,profileBlobSha}){
  if(deployment?.status!=='SUCCESS')fail('latest deployment is not SUCCESS');
  const commit=deployment?.meta?.commitHash;
  if(!SHA.test(commit||''))fail('Railway deployment missing exact commitHash');
  if(!SHA.test(profileBlobSha||''))fail('GitHub profile lookup missing exact blob SHA');
  if(deployment.serviceId!==source.serviceId||deployment.environmentId!==source.environmentId)fail('Railway deployment scope mismatch');
  return {
    observationId:'railway-'+deployment.id,
    appId:source.appId,
    repository:source.repository,
    releaseCommitSha:commit,
    profileBlobSha,
    observedAt:deployment.updatedAt,
    source:'railway',
    reference:'deployment:'+deployment.id
  };
}
export function appendNewObservations({ledger,observations}){
  const next=JSON.parse(JSON.stringify(ledger));
  const seen=new Set(next.observations.map(o=>o.observationId));
  for(const o of observations)if(!seen.has(o.observationId)){next.observations.push(o);seen.add(o.observationId)}
  const failures=validateObservationLedger(next);if(failures.length)fail(failures.join('; '));
  return next;
}
function collectSource(source){
  const raw=command('railway',['deployment','list','--project',source.projectId,'--environment',source.environmentId,'--service',source.serviceId,'--json']);
  let deployments;try{deployments=JSON.parse(raw)}catch{fail('Railway deployment output is not JSON for '+source.appId)}
  const list=Array.isArray(deployments)?deployments:(deployments.deployments||[]);
  const deployment=list.find(d=>d.status==='SUCCESS');
  if(!deployment)fail('no successful Railway deployment for '+source.appId);
  const commit=deployment.meta?.commitHash;if(!SHA.test(commit||''))fail('no exact commit hash for '+source.appId);
  const api='repos/'+source.repository+'/contents/'+source.profilePath+'?ref='+commit;
  const profileBlobSha=command('gh',['api',api,'--jq','.sha']).trim();
  return observationFromSource({source,deployment,profileBlobSha});
}
function selfTest(){
  const source={appId:'app',repository:'owner/app',projectId:'p',environmentId:'e',serviceId:'s',profilePath:'security/profile.json'};
  const deployment={id:'d1',status:'SUCCESS',updatedAt:'2026-09-27T01:00:00.000Z',serviceId:'s',environmentId:'e',meta:{commitHash:'a'.repeat(40)}};
  const o=observationFromSource({source,deployment,profileBlobSha:'b'.repeat(40)});
  if(o.observationId!=='railway-d1'||o.releaseCommitSha!=='a'.repeat(40))fail('observation construction failed');
  const ledger={ledger:'shine-defence/deployment-observations-v1',version:'1.0.0',observations:[o]};
  if(appendNewObservations({ledger,observations:[o]}).observations.length!==1)fail('collector must deduplicate deployment ids');
  let blocked=false;try{observationFromSource({source,deployment:{...deployment,serviceId:'other'},profileBlobSha:'b'.repeat(40)})}catch{blocked=true}if(!blocked)fail('scope mismatch accepted');
  console.log('SHINE DEFENCE DEPLOYMENT COLLECTOR SELF-TEST: PASS exact identity + deduplication + scope fail-closed');
}
function main(){
  const args=process.argv.slice(2);if(args.includes('--self-test'))return selfTest();
  const apply=args.includes('--apply');
  const sources=JSON.parse(readFileSync(join(root,sourcesPath),'utf8'));
  if(sources.contract!=='shine-defence/deployment-sources-v1'||!Array.isArray(sources.sources))fail('unsupported deployment source registry');
  const ledgerFull=join(root,observationsPath),original=readFileSync(ledgerFull),ledger=JSON.parse(original.toString('utf8'));
  const observations=sources.sources.map(collectSource);
  const next=appendNewObservations({ledger,observations});
  const added=next.observations.length-ledger.observations.length;
  console.log('SHINE DEFENCE DEPLOYMENT COLLECTOR');
  console.log('sources: '+sources.sources.length);console.log('new observations: '+added);
  for(const o of observations)console.log('  '+o.appId+' '+o.releaseCommitSha+' / '+o.profileBlobSha);
  if(!apply){console.log('DRY RUN: no files changed.');return}
  try{atomicWrite(ledgerFull,Buffer.from(json(next)));console.log('SHINE DEFENCE DEPLOYMENT COLLECTOR: APPLIED '+added+' new observation'+(added===1?'':'s'))}catch(e){atomicWrite(ledgerFull,original);throw e}
}
main();
