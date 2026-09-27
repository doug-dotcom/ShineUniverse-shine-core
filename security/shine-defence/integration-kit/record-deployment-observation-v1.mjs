#!/usr/bin/env node
import {readFileSync,renameSync,statSync,writeFileSync} from 'node:fs';
import {isAbsolute,join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {validateObservationLedger} from './deployment-observations-v1.mjs';

const root=fileURLToPath(new URL('../../../',import.meta.url));
const ledgerPath='security/shine-defence/deployment-observations-v1.json';
const json=v=>JSON.stringify(v,null,2)+'\n';
const fail=m=>{throw new Error(m)};
function atomicWrite(path,bytes){const t=path+'.tmp-'+process.pid;writeFileSync(t,bytes);renameSync(t,path)}
function readInput(path){if(!path)fail('--input is required');const f=isAbsolute(path)?path:resolve(process.cwd(),path),s=statSync(f);if(!s.isFile()||s.size>16*1024)fail('input must be JSON no larger than 16 KiB');try{return JSON.parse(readFileSync(f,'utf8'))}catch{fail('input is not valid JSON')}}
function parse(argv){const r={apply:false};for(let i=0;i<argv.length;i++){if(argv[i]==='--apply'){r.apply=true;continue}if(argv[i]==='--self-test'){r.selfTest=true;continue}if(argv[i]==='--input'){r.input=argv[++i];continue}fail('unknown argument '+argv[i])}return r}
export function appendObservation({ledger,observation}){
  const next=JSON.parse(JSON.stringify(ledger));next.observations.push(observation);
  const failures=validateObservationLedger(next);if(failures.length)fail(failures.join('; '));
  return next;
}
function selfTest(){
  const base={ledger:'shine-defence/deployment-observations-v1',version:'1.0.0',observations:[]};
  const o={observationId:'deploy-app-1',appId:'app',repository:'owner/app',releaseCommitSha:'a'.repeat(40),profileBlobSha:'b'.repeat(40),observedAt:'2026-09-27T01:00:00.000Z',source:'railway',reference:'deployment-1'};
  if(appendObservation({ledger:base,observation:o}).observations.length!==1)fail('append failed');
  let blocked=false;try{appendObservation({ledger:{...base,observations:[o]},observation:o})}catch{blocked=true}if(!blocked)fail('duplicate observation id accepted');
  console.log('SHINE DEFENCE DEPLOYMENT OBSERVATION RECORDER SELF-TEST: PASS append + duplicate fail-closed');
}
function main(){
  const a=parse(process.argv.slice(2));if(a.selfTest)return selfTest();
  const observation=readInput(a.input),full=join(root,ledgerPath),original=readFileSync(full),ledger=JSON.parse(original.toString('utf8')),next=appendObservation({ledger,observation});
  console.log('SHINE DEFENCE DEPLOYMENT OBSERVATION PLAN');console.log('observation: '+observation.observationId);console.log('app: '+observation.appId);console.log('release: '+observation.releaseCommitSha);console.log((a.apply?'WRITE ':'WOULD WRITE ')+ledgerPath);console.log('certification authority: untouched');
  if(!a.apply){console.log('DRY RUN: no files changed.');return}
  try{atomicWrite(full,Buffer.from(json(next)));console.log('SHINE DEFENCE DEPLOYMENT OBSERVATION: APPLIED '+observation.observationId)}catch(e){atomicWrite(full,original);throw e}
}
main();
