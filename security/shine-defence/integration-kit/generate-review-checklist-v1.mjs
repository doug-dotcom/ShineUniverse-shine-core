#!/usr/bin/env node
import {spawnSync} from 'node:child_process';
import {existsSync,mkdirSync,readFileSync,renameSync,rmSync,writeFileSync} from 'node:fs';
import {dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {
  buildReviewChecklist,
  gitBlobSha,
  validateReviewChecklist
} from './review-checklist-lib-v1.mjs';

export const SHINE_DEFENCE_REVIEW_GENERATOR_VERSION='1.0.0';

const root=fileURLToPath(new URL('../../../',import.meta.url));
const queuePath='security/shine-defence/review-candidates-v1.json';
const registryPath='security/shine-defence/canonical-registry-v1.json';
const reviewDir='security/shine-defence/review-checklists';

const json=value=>JSON.stringify(value,null,2)+'\n';
const clone=value=>JSON.parse(JSON.stringify(value));
function fail(message){throw new Error(message)}
function readJson(relativePath){return JSON.parse(readFileSync(join(root,relativePath),'utf8'))}
function atomicWrite(fullPath,bytes){
  mkdirSync(dirname(fullPath),{recursive:true});
  const temp=fullPath+'.tmp-'+process.pid;
  writeFileSync(temp,bytes);
  renameSync(temp,fullPath);
}
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
  console.log(`Shine Defence structured review generator v${SHINE_DEFENCE_REVIEW_GENERATOR_VERSION}

Usage:
  node security/shine-defence/integration-kit/generate-review-checklist-v1.mjs \\
    --candidate <candidateId> [--generated-at <ISO timestamp|now>] [--apply]

The generator works only on pending_review candidates. It derives one checklist item per
canonical policy requirement, copies candidate evidence as reference material and always
creates humanAuthorization.status=pending. It cannot accept or reject a candidate.
`);
}

function runVerification(){
  const result=spawnSync(process.execPath,['security/shine-defence/integration-kit/verify-review-checklists-v1.mjs'],{cwd:root,encoding:'utf8'});
  if(result.stdout)process.stdout.write(result.stdout);
  if(result.stderr)process.stderr.write(result.stderr);
  if(result.status!==0)fail('review checklist verification failed');
}

function selfTest(){
  const baselineBytes=Buffer.from(json({
    contract:'shine-defence/baseline-v1',
    version:'1.0.0',
    requirements:[
      {id:'SD-001',name:'Boundary explicit',required:true},
      {id:'SD-002',name:'Runtime declared',required:true}
    ]
  }));
  const policyBytes=Buffer.from(json({
    policy:'shine-defence/example-policy-v1',
    version:'1.0.0',
    requirements:['First policy requirement','Second policy requirement']
  }));
  const helperBytes=Buffer.from('export const x=1;\n');
  const registry={
    registry:'shine-defence/canonical-registry-v1',
    version:'1.0.0',
    entries:[
      {id:'baseline',path:'baseline.json',version:'1.0.0',blobSha:gitBlobSha(baselineBytes)},
      {id:'example-policy',path:'example.json',version:'1.0.0',blobSha:gitBlobSha(policyBytes)},
      {id:'certifier',path:'certifier.mjs',version:'1.0.0',blobSha:gitBlobSha(helperBytes)}
    ]
  };
  const registryBytes=Buffer.from(json(registry));
  const artefacts=new Map([['baseline.json',baselineBytes],['example.json',policyBytes],['certifier.mjs',helperBytes]]);
  const readArtefact=path=>artefacts.get(path);
  const candidate={
    candidateId:'app-'+ 'a'.repeat(12),appId:'app',repository:'owner/app',
    releaseCommitSha:'a'.repeat(40),profilePath:'security/profile.json',profileBlobSha:'b'.repeat(40),
    profileVersion:'1.0.0',policies:['baseline','example-policy','certifier'],status:'pending_review',
    observedAt:'2026-09-27T00:00:00.000Z',
    evidence:[{source:'github',kind:'review',reference:'owner/app@release',checkedAt:'2026-09-27T00:00:00.000Z',summary:'Reviewed release evidence.'}]
  };
  const checklist=buildReviewChecklist({
    candidate,generatedAt:'2026-09-27T00:05:00.000Z',registry,registryBytes,readArtefact
  });
  if(checklist.humanAuthorization.status!=='pending')fail('self-test: generator made authoritative decision');
  if(checklist.policyReviews[0].requirements.length!==2||checklist.policyReviews[1].requirements.length!==2||checklist.policyReviews[2].requirements.length!==1)fail('self-test: requirement derivation mismatch');
  const clean=validateReviewChecklist({checklist,candidate,registry,registryBytes,readArtefact});
  if(clean.length)fail('self-test: clean checklist invalid: '+clean.join('; '));

  const approved=clone(checklist);
  for(const policy of approved.policyReviews)for(const item of policy.requirements){
    item.state='satisfied';
    item.reviewerNotes='Human reviewer inspected the exact release evidence for this requirement.';
  }
  approved.humanAuthorization={status:'approved',reviewerId:'reviewer-1',reviewedAt:'2026-09-27T00:10:00.000Z',summary:'All checklist requirements were reviewed and satisfied.'};
  const approvedFailures=validateReviewChecklist({checklist:approved,candidate,registry,registryBytes,readArtefact,requireApproved:true});
  if(approvedFailures.length)fail('self-test: approved checklist invalid: '+approvedFailures.join('; '));

  const expectFail=(name,mutate,requireApproved=false)=>{
    const value=clone(checklist);mutate(value);
    const failures=validateReviewChecklist({checklist:value,candidate,registry,registryBytes,readArtefact,requireApproved});
    if(!failures.length)fail('self-test expected failure: '+name);
  };
  expectFail('candidate binding drift',value=>{value.releaseCommitSha='c'.repeat(40)});
  expectFail('registry binding drift',value=>{value.registryBlobSha='d'.repeat(40)});
  expectFail('requirement text drift',value=>{value.policyReviews[0].requirements[0].requirement='changed'});
  expectFail('unknown evidence reference',value=>{value.policyReviews[0].requirements[0].state='satisfied';value.policyReviews[0].requirements[0].evidenceRefs=['E99']});
  expectFail('satisfied without evidence or note',value=>{value.policyReviews[0].requirements[0].state='satisfied'});
  expectFail('pending with reviewer identity',value=>{value.humanAuthorization.reviewerId='reviewer-1'});
  expectFail('approval with unreviewed items',value=>{value.humanAuthorization={status:'approved',reviewerId:'reviewer-1',reviewedAt:'2026-09-27T00:10:00.000Z',summary:'Approved.'}});
  expectFail('rejection without failed item',value=>{value.humanAuthorization={status:'rejected',reviewerId:'reviewer-1',reviewedAt:'2026-09-27T00:10:00.000Z',summary:'Rejected.'}});
  expectFail('explicit approval required',value=>{},true);

  console.log('SHINE DEFENCE REVIEW CHECKLIST SELF-TEST: PASS 2 healthy states + 9 fail-closed cases');
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

  const registryBytes=readFileSync(join(root,registryPath));
  const registry=JSON.parse(registryBytes.toString('utf8'));
  const generatedAt=args.generatedAt==='now'||!args.generatedAt?new Date().toISOString():args.generatedAt;
  const checklist=buildReviewChecklist({candidate,generatedAt,registry,registryBytes,readArtefact:readCanonical});
  const failures=validateReviewChecklist({checklist,candidate,registry,registryBytes,readArtefact:readCanonical});
  if(failures.length)fail('generated checklist failed validation: '+failures.join('; '));

  const relativePath=join(reviewDir,candidate.candidateId+'.json');
  const fullPath=join(root,relativePath);
  if(existsSync(fullPath))fail('review checklist already exists: '+relativePath);

  console.log('SHINE DEFENCE REVIEW CHECKLIST PLAN');
  console.log('candidate: '+candidate.candidateId);
  console.log('policies: '+candidate.policies.length);
  console.log('requirements: '+checklist.policyReviews.reduce((sum,policy)=>sum+policy.requirements.length,0));
  console.log((args.apply?'WRITE ':'WOULD WRITE ')+relativePath);
  console.log('authorization: pending (human review required)');

  if(!args.apply){
    console.log('DRY RUN: no files changed. No candidate decision was made.');
    return;
  }

  try{
    atomicWrite(fullPath,Buffer.from(json(checklist)));
    runVerification();
    console.log('SHINE DEFENCE REVIEW CHECKLIST: GENERATED '+candidate.candidateId);
  }catch(error){
    if(existsSync(fullPath))rmSync(fullPath);
    console.error('SHINE DEFENCE REVIEW CHECKLIST: ROLLED BACK');
    throw error;
  }
}

main();
