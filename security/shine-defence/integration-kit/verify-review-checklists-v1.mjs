#!/usr/bin/env node
import {existsSync,readdirSync,readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {validateReviewChecklist} from './review-checklist-lib-v1.mjs';

const root=fileURLToPath(new URL('../../../',import.meta.url));
const queue=JSON.parse(readFileSync(join(root,'security/shine-defence/review-candidates-v1.json'),'utf8'));
const registryPath=join(root,'security/shine-defence/canonical-registry-v1.json');
const registryBytes=readFileSync(registryPath);
const registry=JSON.parse(registryBytes.toString('utf8'));
const reviewDir=join(root,'security/shine-defence/review-checklists');
const candidates=new Map(queue.candidates.map(candidate=>[candidate.candidateId,candidate]));
const failures=[];
let checked=0,approved=0,rejected=0,pending=0;

const readArtefact=path=>readFileSync(join(root,path));

if(existsSync(reviewDir)){
  const files=readdirSync(reviewDir).filter(name=>name.endsWith('.json')).sort();
  const seen=new Set();
  for(const file of files){
    let checklist;
    try{checklist=JSON.parse(readFileSync(join(reviewDir,file),'utf8'))}
    catch{failures.push(file+': invalid JSON');continue}
    if(seen.has(checklist.candidateId))failures.push(file+': duplicate checklist candidate');
    seen.add(checklist.candidateId);
    if(file!==checklist.candidateId+'.json')failures.push(file+': filename does not match candidate id');
    const candidate=candidates.get(checklist.candidateId);
    if(!candidate){failures.push(file+': candidate missing from review queue');continue}
    const itemFailures=validateReviewChecklist({checklist,candidate,registry,registryBytes,readArtefact});
    for(const failure of itemFailures)failures.push(file+': '+failure);
    checked++;
    if(checklist.humanAuthorization?.status==='approved')approved++;
    else if(checklist.humanAuthorization?.status==='rejected')rejected++;
    else pending++;
  }
}

if(failures.length){for(const failure of failures)console.error('FAIL '+failure);process.exit(1)}
console.log('SHINE DEFENCE REVIEW CHECKLISTS: PASS '+checked+' checklist'+(checked===1?'':'s')+'; '+approved+' approved, '+rejected+' rejected, '+pending+' pending');
