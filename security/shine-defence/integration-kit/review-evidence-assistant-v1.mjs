#!/usr/bin/env node
import {spawnSync} from 'node:child_process';
import {existsSync,mkdirSync,readFileSync,renameSync,rmSync,writeFileSync} from 'node:fs';
import {dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildReviewChecklist,gitBlobSha} from './review-checklist-lib-v1.mjs';
import {
  buildEvidenceSuggestions,
  scoreEvidence,
  validateEvidenceSuggestions
} from './review-evidence-assistant-lib-v1.mjs';

export const SHINE_DEFENCE_EVIDENCE_ASSISTANT_VERSION='1.0.0';

const root=fileURLToPath(new URL('../../../',import.meta.url));
const queuePath='security/shine-defence/review-candidates-v1.json';
const registryPath='security/shine-defence/canonical-registry-v1.json';
const checklistDir='security/shine-defence/review-checklists';
const suggestionDir='security/shine-defence/review-evidence-suggestions';

const json=value=>JSON.stringify(value,null,2)+'\n';
function fail(message){throw new Error(message)}
function atomicWrite(fullPath,bytes){
  mkdirSync(dirname(fullPath),{recursive:true});
  const temp=fullPath+'.tmp-'+process.pid;
  writeFileSync(temp,bytes);
  renameSync(temp,fullPath);
}
function readJson(relativePath){return JSON.parse(readFileSync(join(root,relativePath),'utf8'))}
function readCanonical(path){return readFileSync(join(root,path))}

function parseArgs(argv){
  const result={apply:false};
  for(let i=0;i<argv.length;i++){
    const arg=argv[i];
    if(arg==='--apply'){result.apply=true;continue}
    if(arg==='--self-test'){result.selfTest=true;continue}
    if(arg==='--help'||arg==='-h'){result.help=true;continue}
    if(arg==='--candidate'||arg==='--generated-at'){
      if(i+1>=argv.length)fail(arg+' requires a value');
      result[arg.slice(2).replace(/-([a-z])/g,(_,c)=>c.toUpperCase())]=argv[++i];
      continue;
    }
    fail('unknown argument '+arg);
  }
  return result;
}

function usage(){
  console.log(`Shine Defence review evidence assistant v${SHINE_DEFENCE_EVIDENCE_ASSISTANT_VERSION}

Usage:
  node security/shine-defence/integration-kit/review-evidence-assistant-v1.mjs \\
    --candidate <candidateId> [--generated-at <ISO timestamp|now>] [--apply]

The assistant reads only evidence already present in the canonical review checklist and
writes a separate advisory suggestion artifact. It never edits checklist state or authorization.
`);
}

function runVerification(){
  const result=spawnSync(process.execPath,['security/shine-defence/integration-kit/verify-review-evidence-suggestions-v1.mjs'],{cwd:root,encoding:'utf8'});
  if(result.stdout)process.stdout.write(result.stdout);
  if(result.stderr)process.stderr.write(result.stderr);
  if(result.status!==0)fail('review evidence suggestion verification failed');
}

function selfTest(){
  const evidence=[
    {source:'github',kind:'security_review',reference:'auth-session-review',checkedAt:'2026-09-27T00:00:00.000Z',summary:'Server authentication session expiry rotation revocation and CSRF checks passed.'},
    {source:'railway',kind:'deployment_success',reference:'deploy-123',checkedAt:'2026-09-27T00:00:00.000Z',summary:'Production deployment build and regression tests passed.'},
    {source:'github',kind:'data_review',reference:'provider-review',checkedAt:'2026-09-27T00:00:00.000Z',summary:'External provider HTTPS deadline response size schema timestamp freshness and provenance checks passed.'}
  ];
  const authReq='Session state has explicit idle and absolute expiry, and expiry is enforced by the server rather than inferred only by the client.';
  const providerReq='Provider requests have bounded deadlines and response bodies are byte-limited before JSON parsing.';
  const unrelatedReq='Minor participants receive age appropriate safeguards against restrictive dieting and appearance judgement.';

  const numbered=evidence.map((item,index)=>({evidenceId:'E'+String(index+1),...item}));
  const authScores=numbered.map(e=>scoreEvidence(authReq,e)).filter(Boolean).sort((a,b)=>b.score-a.score);
  if(authScores[0]?.evidenceId!=='E1')fail('self-test: auth evidence was not ranked first');
  const providerScores=numbered.map(e=>scoreEvidence(providerReq,e)).filter(Boolean).sort((a,b)=>b.score-a.score);
  if(providerScores[0]?.evidenceId!=='E3')fail('self-test: provider evidence was not ranked first');
  if(numbered.map(e=>scoreEvidence(unrelatedReq,e)).filter(Boolean).length)fail('self-test: unrelated requirement should remain a gap');

  const policyBytes=Buffer.from(json({
    policy:'shine-defence/test-v1',
    version:'1.0.0',
    requirements:[authReq,providerReq,unrelatedReq]
  }));
  const registry={
    registry:'shine-defence/canonical-registry-v1',
    version:'1.0.0',
    entries:[{id:'test',path:'test.json',version:'1.0.0',blobSha:gitBlobSha(policyBytes)}]
  };
  const registryBytes=Buffer.from(json(registry));
  const candidate={
    candidateId:'app-'+'a'.repeat(12),appId:'app',repository:'owner/app',releaseCommitSha:'a'.repeat(40),
    profilePath:'security/profile.json',profileBlobSha:'b'.repeat(40),profileVersion:'1.0.0',
    policies:['test'],status:'pending_review',observedAt:'2026-09-27T00:00:00.000Z',evidence
  };
  const readArtefact=path=>path==='test.json'?policyBytes:null;
  const checklist=buildReviewChecklist({
    candidate,
    generatedAt:'2026-09-27T00:05:00.000Z',
    registry,
    registryBytes,
    readArtefact
  });
  const artifact=buildEvidenceSuggestions({
    candidate,checklist,registry,registryBytes,
    generatedAt:'2026-09-27T00:06:00.000Z',
    readArtefact
  });
  const failures=validateEvidenceSuggestions({artifact,candidate,checklist,registry,registryBytes,readArtefact});
  if(failures.length)fail('self-test: clean artifact invalid: '+failures.join('; '));
  if(artifact.items[0].suggestions[0]?.evidenceId!=='E1')fail('self-test: auth suggestion mismatch');
  if(artifact.items[1].suggestions[0]?.evidenceId!=='E3')fail('self-test: provider suggestion mismatch');
  if(artifact.items[2].evidenceGap!==true)fail('self-test: unrelated requirement should be an evidence gap');

  const drifted=JSON.parse(JSON.stringify(artifact));
  drifted.items[0].suggestions[0].score=1;
  if(!validateEvidenceSuggestions({artifact:drifted,candidate,checklist,registry,registryBytes,readArtefact}).length)fail('self-test: tampered score was accepted');

  if(checklist.policyReviews.some(policy=>policy.requirements.some(item=>item.state!=='unreviewed'||item.evidenceRefs.length)))fail('self-test: assistant mutated checklist');

  console.log('SHINE DEFENCE REVIEW EVIDENCE ASSISTANT SELF-TEST: PASS ranking, gap detection, drift rejection and advisory-only behavior');
}

function main(){
  const args=parseArgs(process.argv.slice(2));
  if(args.help){usage();return}
  if(args.selfTest){selfTest();return}
  if(!args.candidate)fail('--candidate is required');

  const queue=readJson(queuePath);
  const matches=queue.candidates.filter(candidate=>candidate.candidateId===args.candidate);
  if(matches.length!==1)fail('candidate must exist exactly once');
  const candidate=matches[0];
  if(candidate.status!=='pending_review')fail('candidate must be pending_review');

  const checklistPath=join(checklistDir,candidate.candidateId+'.json');
  const checklistFull=join(root,checklistPath);
  if(!existsSync(checklistFull))fail('canonical review checklist missing; generate it first');
  const checklist=JSON.parse(readFileSync(checklistFull,'utf8'));

  const registryBytes=readFileSync(join(root,registryPath));
  const registry=JSON.parse(registryBytes.toString('utf8'));
  const generatedAt=args.generatedAt==='now'||!args.generatedAt?new Date().toISOString():args.generatedAt;
  const artifact=buildEvidenceSuggestions({
    candidate,checklist,registry,registryBytes,generatedAt,readArtefact:readCanonical
  });
  const validation=validateEvidenceSuggestions({
    artifact,candidate,checklist,registry,registryBytes,readArtefact:readCanonical
  });
  if(validation.length)fail('generated suggestions invalid: '+validation.join('; '));

  const relativePath=join(suggestionDir,candidate.candidateId+'.json');
  const fullPath=join(root,relativePath);
  console.log('SHINE DEFENCE REVIEW EVIDENCE ASSISTANT');
  console.log('candidate: '+candidate.candidateId);
  console.log('requirements: '+artifact.items.length);
  console.log('evidence gaps: '+artifact.items.filter(item=>item.evidenceGap).length);
  console.log('suggested mappings: '+artifact.items.reduce((sum,item)=>sum+item.suggestions.length,0));
  console.log((args.apply?'WRITE ':'WOULD WRITE ')+relativePath);
  console.log('authority: advisory only; checklist state unchanged');

  if(!args.apply){
    console.log('DRY RUN: no files changed.');
    return;
  }

  const original=existsSync(fullPath)?readFileSync(fullPath):null;
  try{
    atomicWrite(fullPath,Buffer.from(json(artifact)));
    runVerification();
    console.log('SHINE DEFENCE REVIEW EVIDENCE ASSISTANT: GENERATED '+candidate.candidateId);
  }catch(error){
    if(original===null){if(existsSync(fullPath))rmSync(fullPath)}
    else atomicWrite(fullPath,original);
    console.error('SHINE DEFENCE REVIEW EVIDENCE ASSISTANT: ROLLED BACK');
    throw error;
  }
}

main();
