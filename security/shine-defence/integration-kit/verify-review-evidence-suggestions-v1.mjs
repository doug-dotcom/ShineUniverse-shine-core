#!/usr/bin/env node
import {createHash} from 'node:crypto';
import {existsSync,readdirSync,readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {
  validateEvidenceSuggestions,
  validateHistoricalEvidenceSuggestions
} from './review-evidence-assistant-lib-v1.mjs';

const root=fileURLToPath(new URL('../../../',import.meta.url));
const queue=JSON.parse(readFileSync(join(root,'security/shine-defence/review-candidates-v1.json'),'utf8'));
const decisionsLedger=JSON.parse(readFileSync(join(root,'security/shine-defence/review-decisions-v1.json'),'utf8'));
const registryPath=join(root,'security/shine-defence/canonical-registry-v1.json');
const registryBytes=readFileSync(registryPath);
const registry=JSON.parse(registryBytes.toString('utf8'));
const checklistDir=join(root,'security/shine-defence/review-checklists');
const suggestionDir=join(root,'security/shine-defence/review-evidence-suggestions');
const candidates=new Map(queue.candidates.map(candidate=>[candidate.candidateId,candidate]));
const decisions=new Map((decisionsLedger.decisions||[]).map(decision=>[decision.candidateId,decision]));
const readArtefact=path=>readFileSync(join(root,path));
const gitBlobSha=bytes=>createHash('sha1').update(Buffer.from('blob '+bytes.length+'\0')).update(bytes).digest('hex');
const failures=[];
let checked=0,gaps=0,mappings=0,historical=0;

if(existsSync(suggestionDir)){
  const files=readdirSync(suggestionDir).filter(name=>name.endsWith('.json')).sort();
  const seen=new Set();
  for(const file of files){
    let artifact;
    try{artifact=JSON.parse(readFileSync(join(suggestionDir,file),'utf8'))}
    catch{failures.push(file+': invalid JSON');continue}

    if(seen.has(artifact.candidateId))failures.push(file+': duplicate suggestion artifact candidate');
    seen.add(artifact.candidateId);
    if(file!==artifact.candidateId+'.json')failures.push(file+': filename does not match candidate id');

    const candidate=candidates.get(artifact.candidateId);
    if(!candidate){failures.push(file+': candidate missing from review queue');continue}

    const checklistPath=join(checklistDir,artifact.candidateId+'.json');
    if(!existsSync(checklistPath)){failures.push(file+': canonical review checklist missing');continue}
    let checklist,checklistBytes;
    try{
      checklistBytes=readFileSync(checklistPath);
      checklist=JSON.parse(checklistBytes.toString('utf8'));
    }catch{failures.push(file+': checklist invalid JSON');continue}

    let itemFailures=[];
    if(candidate.status==='pending_review'){
      itemFailures=validateEvidenceSuggestions({
        artifact,candidate,checklist,registry,registryBytes,readArtefact
      });
    }else{
      const decision=decisions.get(candidate.candidateId);
      if(!decision){
        itemFailures.push('finalized candidate decision missing');
      }else{
        if(decision.reviewChecklistBlobSha!==gitBlobSha(checklistBytes))itemFailures.push('historical checklist fingerprint mismatch');
        if(decision.reviewRegistryBlobSha!==checklist.registryBlobSha)itemFailures.push('historical registry fingerprint mismatch');
      }
      if(!itemFailures.length){
        itemFailures=validateHistoricalEvidenceSuggestions({artifact,candidate,checklist});
        historical++;
      }
    }

    for(const failure of itemFailures)failures.push(file+': '+failure);
    checked++;
    gaps+=(artifact.items||[]).filter(item=>item.evidenceGap).length;
    mappings+=(artifact.items||[]).reduce((sum,item)=>sum+(item.suggestions||[]).length,0);
  }
}

if(failures.length){
  for(const failure of failures)console.error('FAIL '+failure);
  process.exit(1);
}
console.log('SHINE DEFENCE REVIEW EVIDENCE SUGGESTIONS: PASS '+checked+' artifact'+(checked===1?'':'s')+'; '+mappings+' suggested mappings; '+gaps+' evidence gaps; '+historical+' historical');
