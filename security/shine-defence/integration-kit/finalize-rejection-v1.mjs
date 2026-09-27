#!/usr/bin/env node
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {existsSync,readFileSync,renameSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildReviewChecklist,validateReviewChecklist} from './review-checklist-lib-v1.mjs';

export const SHINE_DEFENCE_REJECTION_FINALIZER_VERSION='1.0.0';

const root=fileURLToPath(new URL('../../../',import.meta.url));
const paths={
  queue:'security/shine-defence/review-candidates-v1.json',
  decisions:'security/shine-defence/review-decisions-v1.json',
  registry:'security/shine-defence/canonical-registry-v1.json',
  checklists:'security/shine-defence/review-checklists'
};

const json=value=>JSON.stringify(value,null,2)+'\n';
const clone=value=>JSON.parse(JSON.stringify(value));
const gitBlobSha=bytes=>createHash('sha1').update(Buffer.from('blob '+bytes.length+'\0')).update(bytes).digest('hex');

function fail(message){throw new Error(message)}
function readJson(relativePath){return JSON.parse(readFileSync(join(root,relativePath),'utf8'))}
function readCanonical(path){return readFileSync(join(root,path))}
function atomicWrite(fullPath,bytes){
  const temp=fullPath+'.tmp-'+process.pid;
  writeFileSync(temp,bytes);
  renameSync(temp,fullPath);
}

export function buildRejectionFinalization({candidateId,queue,decisions,checklist,checklistBytes,registry,registryBytes,readArtefact}){
  if(queue.ledger!=='shine-defence/review-candidates-v1'||!Array.isArray(queue.candidates))fail('unsupported review candidate queue');
  if(decisions.ledger!=='shine-defence/review-decisions-v1'||!Array.isArray(decisions.decisions))fail('unsupported review decision ledger');
  if(registry.registry!=='shine-defence/canonical-registry-v1'||!Array.isArray(registry.entries))fail('unsupported canonical registry');

  const matches=queue.candidates.filter(candidate=>candidate.candidateId===candidateId);
  if(matches.length!==1)fail('candidate must exist exactly once');
  const candidate=matches[0];
  if(candidate.status!=='pending_review')fail('candidate must be pending_review');
  if(decisions.decisions.some(decision=>decision.candidateId===candidateId))fail('candidate already has a review decision');

  if(!Buffer.isBuffer(checklistBytes))fail('checklist bytes are required');
  const failures=validateReviewChecklist({checklist,candidate,registry,registryBytes,readArtefact});
  if(failures.length)fail('review checklist invalid: '+failures.join('; '));
  const auth=checklist.humanAuthorization;
  if(auth?.status!=='rejected')fail('explicit human rejection is required');

  const nextQueue=clone(queue);
  const nextCandidate=nextQueue.candidates.find(item=>item.candidateId===candidateId);
  nextCandidate.status='dismissed';
  nextCandidate.decisionReason=auth.summary;

  const nextDecisions=clone(decisions);
  nextDecisions.decisions.push({
    decisionId:candidateId+'-dismissed',
    candidateId,
    appId:candidate.appId,
    outcome:'dismissed',
    decidedAt:auth.reviewedAt,
    authority:auth.reviewerId,
    summary:auth.summary,
    reviewChecklistBlobSha:gitBlobSha(checklistBytes),
    reviewRegistryBlobSha:checklist.registryBlobSha
  });

  return {candidate,nextQueue,nextDecisions,authorization:clone(auth)};
}

function parseArgs(argv){
  const result={apply:false};
  for(let i=0;i<argv.length;i++){
    const arg=argv[i];
    if(arg==='--apply'){result.apply=true;continue}
    if(arg==='--self-test'){result.selfTest=true;continue}
    if(arg==='--help'||arg==='-h'){result.help=true;continue}
    if(arg==='--candidate'){
      if(i+1>=argv.length)fail('--candidate requires a value');
      result.candidate=argv[++i];
      continue;
    }
    fail('unknown argument '+arg);
  }
  return result;
}

function usage(){
  console.log(`Shine Defence rejection finalizer v${SHINE_DEFENCE_REJECTION_FINALIZER_VERSION}

Usage:
  node security/shine-defence/integration-kit/finalize-rejection-v1.mjs \\
    --candidate <candidateId> [--apply]

The candidate must still be pending_review and its canonical checklist must contain an
explicit human rejection. The helper changes only candidate status/decisionReason and the
separate review-decision ledger. Without --apply it is a dry-run.
`);
}

function runVerification(){
  const scripts=[
    'security/shine-defence/integration-kit/verify-review-candidates-v1.mjs',
    'security/shine-defence/integration-kit/verify-review-decisions-v1.mjs',
    'security/shine-defence/integration-kit/verify-review-checklists-v1.mjs',
    'security/shine-defence/integration-kit/verify-review-rejections-v1.mjs',
    'security/shine-defence/integration-kit/review-queue-v1.mjs --json'
  ];
  for(const command of scripts){
    const [script,...args]=command.split(' ');
    const result=spawnSync(process.execPath,[script,...args],{cwd:root,encoding:'utf8'});
    if(result.stdout)process.stdout.write(result.stdout);
    if(result.stderr)process.stderr.write(result.stderr);
    if(result.status!==0)fail('verification failed: '+command);
  }
}

function selfTest(){
  const policyBytes=Buffer.from(json({
    policy:'shine-defence/example-v1',
    version:'1.0.0',
    requirements:['Control must be present.']
  }));
  const {createHash}=await import('node:crypto');
  const blobSha=bytes=>createHash('sha1').update(Buffer.from('blob '+bytes.length+'\0')).update(bytes).digest('hex');
  const registry={
    registry:'shine-defence/canonical-registry-v1',
    version:'1.0.0',
    entries:[{id:'example',path:'example.json',version:'1.0.0',blobSha:blobSha(policyBytes)}]
  };
  const registryBytes=Buffer.from(json(registry));
  const readArtefact=path=>path==='example.json'?policyBytes:null;
  const candidate={
    candidateId:'app-'+'a'.repeat(12),
    appId:'app',
    repository:'owner/app',
    releaseCommitSha:'a'.repeat(40),
    profilePath:'security/profile.json',
    profileBlobSha:'b'.repeat(40),
    profileVersion:'1.0.0',
    policies:['example'],
    status:'pending_review',
    observedAt:'2026-09-27T00:00:00.000Z',
    evidence:[{source:'github',kind:'review',reference:'owner/app@release',checkedAt:'2026-09-27T00:00:00.000Z',summary:'Review evidence.'}]
  };
  const checklist=buildReviewChecklist({
    candidate,
    generatedAt:'2026-09-27T00:05:00.000Z',
    registry,
    registryBytes,
    readArtefact
  });
  checklist.policyReviews[0].requirements[0].state='not_satisfied';
  checklist.policyReviews[0].requirements[0].evidenceRefs=['E1'];
  checklist.policyReviews[0].requirements[0].reviewerNotes='The reviewed release does not satisfy this control.';
  checklist.humanAuthorization={
    status:'rejected',
    reviewerId:'reviewer-1',
    reviewedAt:'2026-09-27T00:10:00.000Z',
    summary:'Rejected because a required control is not satisfied.'
  };
  const queue={ledger:'shine-defence/review-candidates-v1',version:'1.0.0',candidates:[candidate]};
  const decisions={ledger:'shine-defence/review-decisions-v1',version:'1.0.0',decisions:[]};

  const built=buildRejectionFinalization({
    candidateId:candidate.candidateId,queue,decisions,checklist,checklistBytes:Buffer.from(json(checklist)),registry,registryBytes,readArtefact
  });
  const closed=built.nextQueue.candidates[0];
  const decision=built.nextDecisions.decisions[0];
  if(closed.status!=='dismissed'||closed.decisionReason!==checklist.humanAuthorization.summary)fail('self-test: candidate dismissal mismatch');
  if(decision.outcome!=='dismissed'||decision.authority!=='reviewer-1'||decision.decidedAt!==checklist.humanAuthorization.reviewedAt||decision.summary!==checklist.humanAuthorization.summary)fail('self-test: decision binding mismatch');
  if(decision.reviewChecklistBlobSha!==gitBlobSha(Buffer.from(json(checklist)))||decision.reviewRegistryBlobSha!==checklist.registryBlobSha)fail('self-test: checklist fingerprint mismatch');

  const expectFail=(name,mutate)=>{
    const q=clone(queue),d=clone(decisions),c=clone(checklist);
    mutate(q,d,c);
    let failed=false;
    try{buildRejectionFinalization({candidateId:candidate.candidateId,queue:q,decisions:d,checklist:c,checklistBytes:Buffer.from(json(c)),registry,registryBytes,readArtefact})}catch{failed=true}
    if(!failed)fail('self-test expected failure: '+name);
  };
  expectFail('candidate not pending',(q)=>{q.candidates[0].status='dismissed'});
  expectFail('existing decision',(q,d)=>{d.decisions.push({candidateId:candidate.candidateId})});
  expectFail('checklist not rejected',(q,d,c)=>{c.humanAuthorization={status:'pending'}});
  expectFail('checklist candidate drift',(q,d,c)=>{c.releaseCommitSha='c'.repeat(40)});
  expectFail('rejection without failed control',(q,d,c)=>{c.policyReviews[0].requirements[0].state='satisfied';c.policyReviews[0].requirements[0].reviewerNotes='Reviewed';});

  console.log('SHINE DEFENCE REJECTION FINALIZER SELF-TEST: PASS 1 healthy + 5 fail-closed cases');
}

async function main(){
  const args=parseArgs(process.argv.slice(2));
  if(args.help){usage();return}
  if(args.selfTest){await selfTest();return}
  if(!args.candidate)fail('--candidate is required');

  const queue=readJson(paths.queue);
  const matches=queue.candidates.filter(candidate=>candidate.candidateId===args.candidate);
  if(matches.length!==1)fail('candidate must exist exactly once');
  const candidate=matches[0];

  const checklistRelative=join(paths.checklists,candidate.candidateId+'.json');
  const checklistFull=join(root,checklistRelative);
  if(!existsSync(checklistFull))fail('canonical rejected checklist required: '+checklistRelative);
  const checklistBytes=readFileSync(checklistFull);
  const checklist=JSON.parse(checklistBytes.toString('utf8'));

  const registryBytes=readFileSync(join(root,paths.registry));
  const registry=JSON.parse(registryBytes.toString('utf8'));
  const built=buildRejectionFinalization({
    candidateId:args.candidate,
    queue,
    decisions:readJson(paths.decisions),
    checklist,
    checklistBytes,
    registry,
    registryBytes,
    readArtefact:readCanonical
  });

  console.log('SHINE DEFENCE REJECTION FINALIZATION PLAN');
  console.log('candidate: '+candidate.candidateId);
  console.log('app: '+candidate.appId);
  console.log('reviewer: '+built.authorization.reviewerId);
  console.log('rejected at: '+built.authorization.reviewedAt);
  console.log('outcome: pending_review -> dismissed');
  console.log((args.apply?'WRITE ':'WOULD WRITE ')+paths.queue);
  console.log((args.apply?'WRITE ':'WOULD WRITE ')+paths.decisions);
  console.log('certification state: untouched');

  if(!args.apply){
    console.log('DRY RUN: no files changed.');
    return;
  }

  const queueFull=join(root,paths.queue),decisionsFull=join(root,paths.decisions);
  const originalQueue=readFileSync(queueFull),originalDecisions=readFileSync(decisionsFull);
  try{
    atomicWrite(queueFull,Buffer.from(json(built.nextQueue)));
    atomicWrite(decisionsFull,Buffer.from(json(built.nextDecisions)));
    runVerification();
    console.log('SHINE DEFENCE REJECTION FINALIZATION: APPLIED '+candidate.candidateId);
  }catch(error){
    atomicWrite(queueFull,originalQueue);
    atomicWrite(decisionsFull,originalDecisions);
    console.error('SHINE DEFENCE REJECTION FINALIZATION: ROLLED BACK');
    throw error;
  }
}

main();
