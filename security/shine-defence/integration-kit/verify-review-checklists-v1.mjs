#!/usr/bin/env node
import {createHash} from 'node:crypto';
import {existsSync,readdirSync,readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {validateReviewChecklist} from './review-checklist-lib-v1.mjs';

const root=fileURLToPath(new URL('../../../',import.meta.url));
const queue=JSON.parse(readFileSync(join(root,'security/shine-defence/review-candidates-v1.json'),'utf8'));
const decisionsLedger=JSON.parse(readFileSync(join(root,'security/shine-defence/review-decisions-v1.json'),'utf8'));
const registryPath=join(root,'security/shine-defence/canonical-registry-v1.json');
const registryBytes=readFileSync(registryPath);
const registry=JSON.parse(registryBytes.toString('utf8'));
const reviewDir=join(root,'security/shine-defence/review-checklists');
const candidates=new Map(queue.candidates.map(candidate=>[candidate.candidateId,candidate]));
const decisions=new Map((decisionsLedger.decisions||[]).map(decision=>[decision.candidateId,decision]));
const failures=[];
let checked=0,approved=0,rejected=0,pending=0,historical=0;

const readArtefact=path=>readFileSync(join(root,path));
const gitBlobSha=bytes=>createHash('sha1').update(Buffer.from('blob '+bytes.length+'\0')).update(bytes).digest('hex');
const sameArray=(a,b)=>JSON.stringify(a)===JSON.stringify(b);

function verifyHistoricalChecklist({file,bytes,checklist,candidate,decision}){
  if(!decision){failures.push(file+': finalized candidate missing decision');return}
  if(decision.reviewChecklistBlobSha!==gitBlobSha(bytes))failures.push(file+': finalized checklist bytes do not match decision fingerprint');
  if(decision.reviewRegistryBlobSha!==checklist.registryBlobSha)failures.push(file+': finalized checklist registry identity does not match decision fingerprint');

  const bindings={
    candidateId:candidate.candidateId,
    appId:candidate.appId,
    repository:candidate.repository,
    releaseCommitSha:candidate.releaseCommitSha,
    profilePath:candidate.profilePath,
    profileBlobSha:candidate.profileBlobSha,
    profileVersion:candidate.profileVersion,
    candidateObservedAt:candidate.observedAt
  };
  for(const [key,expected] of Object.entries(bindings))if(checklist[key]!==expected)failures.push(file+': historical '+key+' binding mismatch');
  if(!sameArray(checklist.policies,candidate.policies))failures.push(file+': historical policy binding mismatch');

  if(candidate.status==='accepted'){
    if(checklist.humanAuthorization?.status!=='approved')failures.push(file+': accepted candidate checklist is not human-approved');
    else{
      if(decision.authority!==checklist.humanAuthorization.reviewerId)failures.push(file+': accepted decision reviewer mismatch');
      if(decision.decidedAt!==checklist.humanAuthorization.reviewedAt)failures.push(file+': accepted decision timestamp mismatch');
      if(decision.summary!==checklist.humanAuthorization.summary)failures.push(file+': accepted decision summary mismatch');
    }
  }
  if(candidate.status==='dismissed'){
    if(checklist.humanAuthorization?.status!=='rejected')failures.push(file+': dismissed candidate checklist is not human-rejected');
    else{
      if(decision.authority!==checklist.humanAuthorization.reviewerId)failures.push(file+': dismissed decision reviewer mismatch');
      if(decision.decidedAt!==checklist.humanAuthorization.reviewedAt)failures.push(file+': dismissed decision timestamp mismatch');
      if(decision.summary!==checklist.humanAuthorization.summary)failures.push(file+': dismissed decision summary mismatch');
      if(candidate.decisionReason!==checklist.humanAuthorization.summary)failures.push(file+': dismissed candidate reason does not match human rejection summary');
    }
  }
}

if(existsSync(reviewDir)){
  const files=readdirSync(reviewDir).filter(name=>name.endsWith('.json')).sort();
  const seen=new Set();
  for(const file of files){
    let checklist,bytes;
    try{
      bytes=readFileSync(join(reviewDir,file));
      checklist=JSON.parse(bytes.toString('utf8'));
    }catch{failures.push(file+': invalid JSON');continue}

    if(seen.has(checklist.candidateId))failures.push(file+': duplicate checklist candidate');
    seen.add(checklist.candidateId);
    if(file!==checklist.candidateId+'.json')failures.push(file+': filename does not match candidate id');
    const candidate=candidates.get(checklist.candidateId);
    if(!candidate){failures.push(file+': candidate missing from review queue');continue}

    if(candidate.status==='pending_review'){
      const itemFailures=validateReviewChecklist({checklist,candidate,registry,registryBytes,readArtefact});
      for(const failure of itemFailures)failures.push(file+': '+failure);
    }else{
      verifyHistoricalChecklist({file,bytes,checklist,candidate,decision:decisions.get(candidate.candidateId)});
      historical++;
    }

    checked++;
    if(checklist.humanAuthorization?.status==='approved')approved++;
    else if(checklist.humanAuthorization?.status==='rejected')rejected++;
    else pending++;
  }
}

if(failures.length){for(const failure of failures)console.error('FAIL '+failure);process.exit(1)}
console.log('SHINE DEFENCE REVIEW CHECKLISTS: PASS '+checked+' checklist'+(checked===1?'':'s')+'; '+approved+' approved, '+rejected+' rejected, '+pending+' pending; '+historical+' fingerprint-locked historical');
