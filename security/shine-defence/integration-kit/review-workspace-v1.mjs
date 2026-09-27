#!/usr/bin/env node
import {spawnSync} from 'node:child_process';
import {existsSync,readFileSync,renameSync,statSync,writeFileSync} from 'node:fs';
import {isAbsolute,join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {
  buildReviewChecklist,
  gitBlobSha,
  validateReviewChecklist
} from './review-checklist-lib-v1.mjs';
import {validateEvidenceSuggestions} from './review-evidence-assistant-lib-v1.mjs';

export const SHINE_DEFENCE_REVIEW_WORKSPACE_VERSION='1.1.0';

const root=fileURLToPath(new URL('../../../',import.meta.url));
const queuePath='security/shine-defence/review-candidates-v1.json';
const registryPath='security/shine-defence/canonical-registry-v1.json';
const reviewDir='security/shine-defence/review-checklists';
const suggestionDir='security/shine-defence/review-evidence-suggestions';

const json=value=>JSON.stringify(value,null,2)+'\n';
const clone=value=>JSON.parse(JSON.stringify(value));

function fail(message){throw new Error(message)}
function readJson(relativePath){return JSON.parse(readFileSync(join(root,relativePath),'utf8'))}
function atomicWrite(fullPath,bytes){
  const temp=fullPath+'.tmp-'+process.pid;
  writeFileSync(temp,bytes);
  renameSync(temp,fullPath);
}
function readCanonical(path){return readFileSync(join(root,path))}

function allItems(checklist){
  return (checklist.policyReviews||[]).flatMap(policy=>
    (policy.requirements||[]).map(item=>({...item,policyId:policy.policyId}))
  );
}

export function summariseWorkspace(checklist){
  const items=allItems(checklist);
  const counts={unreviewed:0,satisfied:0,not_satisfied:0};
  for(const item of items)if(item.state in counts)counts[item.state]++;
  return {
    candidateId:checklist.candidateId,
    appId:checklist.appId,
    authorization:checklist.humanAuthorization?.status||'invalid',
    total:items.length,
    counts,
    next:items.find(item=>item.state==='unreviewed')||null
  };
}

function findItem(checklist,itemId){
  for(const policy of checklist.policyReviews||[]){
    const index=(policy.requirements||[]).findIndex(item=>item.itemId===itemId);
    if(index>=0)return {policy,index,item:policy.requirements[index]};
  }
  return null;
}

function validateActionShape(action){
  if(!action||typeof action!=='object'||Array.isArray(action))fail('workspace action must be a JSON object');

  if(action.action==='record'){
    const allowed=new Set(['action','itemId','state','evidenceRefs','reviewerNotes']);
    for(const key of Object.keys(action))if(!allowed.has(key))fail('unknown record action field '+key);
    if(typeof action.itemId!=='string'||!action.itemId)fail('record action requires itemId');
    if(!['unreviewed','satisfied','not_satisfied'].includes(action.state))fail('record action requires valid state');
    if(action.evidenceRefs!==undefined&&(!Array.isArray(action.evidenceRefs)||action.evidenceRefs.some(ref=>typeof ref!=='string')))fail('record evidenceRefs must be an array of strings');
    if(action.reviewerNotes!==undefined&&typeof action.reviewerNotes!=='string')fail('record reviewerNotes must be a string');
    return;
  }

  if(action.action==='authorize'){
    const allowed=new Set(['action','decision','confirm','reviewerId','reviewedAt','summary']);
    for(const key of Object.keys(action))if(!allowed.has(key))fail('unknown authorize action field '+key);
    if(!['approved','rejected'].includes(action.decision))fail('authorize decision must be approved or rejected');
    const expected=action.decision==='approved'?'APPROVE':'REJECT';
    if(action.confirm!==expected)fail('authorize action requires literal confirmation '+expected);
    if(typeof action.reviewerId!=='string'||!action.reviewerId)fail('authorize action requires reviewerId');
    if(typeof action.reviewedAt!=='string'||!action.reviewedAt)fail('authorize action requires explicit reviewedAt');
    if(typeof action.summary!=='string'||!action.summary)fail('authorize action requires summary');
    return;
  }

  fail('unsupported workspace action');
}

export function applyWorkspaceAction({checklist,action,candidate,registry,registryBytes,readArtefact}){
  validateActionShape(action);

  const beforeFailures=validateReviewChecklist({checklist,candidate,registry,registryBytes,readArtefact});
  if(beforeFailures.length)fail('current checklist is invalid: '+beforeFailures.join('; '));
  if(checklist.humanAuthorization.status!=='pending')fail('finalized checklist is locked in workspace v1');

  const next=clone(checklist);

  if(action.action==='record'){
    const found=findItem(next,action.itemId);
    if(!found)fail('unknown checklist item '+action.itemId);
    found.item.state=action.state;
    if(action.evidenceRefs!==undefined)found.item.evidenceRefs=clone(action.evidenceRefs);
    if(action.reviewerNotes!==undefined)found.item.reviewerNotes=action.reviewerNotes;
  }else{
    next.humanAuthorization={
      status:action.decision,
      reviewerId:action.reviewerId,
      reviewedAt:action.reviewedAt,
      summary:action.summary
    };
  }

  const failures=validateReviewChecklist({checklist:next,candidate,registry,registryBytes,readArtefact});
  if(failures.length)fail('workspace action invalid: '+failures.join('; '));
  return next;
}

function parseArgs(argv){
  const result={apply:false};
  for(let i=0;i<argv.length;i++){
    const arg=argv[i];
    if(arg==='--apply'){result.apply=true;continue}
    if(arg==='--self-test'){result.selfTest=true;continue}
    if(arg==='--help'||arg==='-h'){result.help=true;continue}
    if(arg==='--candidate'||arg==='--action-file'){
      if(i+1>=argv.length)fail(arg+' requires a value');
      result[arg.slice(2).replace(/-([a-z])/g,(_,c)=>c.toUpperCase())]=argv[++i];
      continue;
    }
    fail('unknown argument '+arg);
  }
  return result;
}

function usage(){
  console.log(`Shine Defence review workspace v${SHINE_DEFENCE_REVIEW_WORKSPACE_VERSION}

Read-only status:
  node security/shine-defence/integration-kit/review-workspace-v1.mjs \\
    --candidate <candidateId>

Propose/apply one review action:
  node security/shine-defence/integration-kit/review-workspace-v1.mjs \\
    --candidate <candidateId> --action-file <action.json> [--apply]

record action:
  {"action":"record","itemId":"baseline:SD-001","state":"satisfied",
   "evidenceRefs":["E1"],"reviewerNotes":"Reviewed the exact release boundary."}

authorize action:
  {"action":"authorize","decision":"approved","confirm":"APPROVE",
   "reviewerId":"reviewer-id","reviewedAt":"2026-09-27T01:00:00.000Z",
   "summary":"All requirements reviewed and satisfied."}

Without --apply, mutations are dry-runs. Authorization is always a separate explicit action.
`);
}

function readAction(path){
  const full=isAbsolute(path)?path:resolve(process.cwd(),path);
  const info=statSync(full);
  if(!info.isFile()||info.size>32*1024)fail('action file must be JSON no larger than 32 KiB');
  try{return JSON.parse(readFileSync(full,'utf8'))}catch{fail('action file is not valid JSON')}
}

function printEvidence(checklist){
  console.log('EVIDENCE');
  for(const evidence of checklist.candidateEvidence||[]){
    console.log('  '+evidence.evidenceId+' ['+evidence.source+'/'+evidence.kind+'] '+evidence.reference);
    console.log('    '+evidence.summary);
  }
}

function printStatus(checklist,suggestionArtifact=null){
  const status=summariseWorkspace(checklist);
  console.log('SHINE DEFENCE REVIEW WORKSPACE');
  console.log('candidate: '+status.candidateId);
  console.log('app: '+status.appId);
  console.log('authorization: '+status.authorization);
  console.log('progress: '+status.counts.satisfied+'/'+status.total+' satisfied; '+status.counts.not_satisfied+' not satisfied; '+status.counts.unreviewed+' unreviewed');
  printEvidence(checklist);
  console.log('NEXT REQUIREMENT');
  if(status.next){
    console.log('  '+status.next.itemId+' ['+status.next.policyId+']');
    console.log('  '+status.next.requirement);
    const advisory=(suggestionArtifact?.items||[]).find(item=>item.itemId===status.next.itemId);
    if(advisory){
      console.log('ADVISORY EVIDENCE SUGGESTIONS');
      if(advisory.evidenceGap){
        console.log('  evidence gap: no deterministic match found');
      }else{
        for(const suggestion of advisory.suggestions){
          console.log('  '+suggestion.evidenceId+' ['+suggestion.confidence+'; score '+suggestion.score+'] '+suggestion.reason);
        }
      }
      console.log('  reviewer confirmation required before any mapping is recorded');
    }
  }else{
    console.log('  none');
    if(status.authorization==='pending'){
      if(status.counts.not_satisfied)console.log('  ready for an explicit human REJECT decision');
      else console.log('  ready for an explicit human APPROVE decision');
    }
  }
}

function runVerification(){
  const result=spawnSync(process.execPath,['security/shine-defence/integration-kit/verify-review-checklists-v1.mjs'],{cwd:root,encoding:'utf8'});
  if(result.stdout)process.stdout.write(result.stdout);
  if(result.stderr)process.stderr.write(result.stderr);
  if(result.status!==0)fail('review checklist verification failed');
}

function selfTest(){
  const policyBytes=Buffer.from(json({
    policy:'shine-defence/example-v1',
    version:'1.0.0',
    requirements:['First requirement','Second requirement']
  }));
  const registry={
    registry:'shine-defence/canonical-registry-v1',
    version:'1.0.0',
    entries:[{
      id:'example',
      path:'example.json',
      version:'1.0.0',
      blobSha:gitBlobSha(policyBytes)
    }]
  };
  const registryBytes=Buffer.from(json(registry));
  const readArtefact=path=>path==='example.json'?policyBytes:null;
  const candidate={
    candidateId:'app-'+ 'a'.repeat(12),
    appId:'app',
    repository:'owner/app',
    releaseCommitSha:'a'.repeat(40),
    profilePath:'security/profile.json',
    profileBlobSha:'b'.repeat(40),
    profileVersion:'1.0.0',
    policies:['example'],
    status:'pending_review',
    observedAt:'2026-09-27T00:00:00.000Z',
    evidence:[{
      source:'github',
      kind:'security_review',
      reference:'owner/app@release',
      checkedAt:'2026-09-27T00:00:00.000Z',
      summary:'Exact release review evidence.'
    }]
  };

  const original=buildReviewChecklist({
    candidate,
    generatedAt:'2026-09-27T00:05:00.000Z',
    registry,
    registryBytes,
    readArtefact
  });

  const initial=summariseWorkspace(original);
  if(initial.total!==2||initial.counts.unreviewed!==2||initial.next?.itemId!=='example:R001')fail('self-test: initial workspace status mismatch');

  const first=applyWorkspaceAction({
    checklist:original,
    action:{action:'record',itemId:'example:R001',state:'satisfied',evidenceRefs:['E1'],reviewerNotes:''},
    candidate,registry,registryBytes,readArtefact
  });
  if(summariseWorkspace(first).next?.itemId!=='example:R002')fail('self-test: next requirement did not advance');

  let approvalBlocked=false;
  try{
    applyWorkspaceAction({
      checklist:first,
      action:{action:'authorize',decision:'approved',confirm:'APPROVE',reviewerId:'reviewer-1',reviewedAt:'2026-09-27T00:10:00.000Z',summary:'Approved.'},
      candidate,registry,registryBytes,readArtefact
    });
  }catch{approvalBlocked=true}
  if(!approvalBlocked)fail('self-test: incomplete checklist was approved');

  const completed=applyWorkspaceAction({
    checklist:first,
    action:{action:'record',itemId:'example:R002',state:'satisfied',evidenceRefs:[],reviewerNotes:'Human reviewer inspected the exact release implementation.'},
    candidate,registry,registryBytes,readArtefact
  });
  const approved=applyWorkspaceAction({
    checklist:completed,
    action:{action:'authorize',decision:'approved',confirm:'APPROVE',reviewerId:'reviewer-1',reviewedAt:'2026-09-27T00:10:00.000Z',summary:'All requirements reviewed and satisfied.'},
    candidate,registry,registryBytes,readArtefact
  });
  if(approved.humanAuthorization.status!=='approved')fail('self-test: approval was not recorded');

  let locked=false;
  try{
    applyWorkspaceAction({
      checklist:approved,
      action:{action:'record',itemId:'example:R001',state:'unreviewed'},
      candidate,registry,registryBytes,readArtefact
    });
  }catch{locked=true}
  if(!locked)fail('self-test: finalized checklist was editable');

  const failed=applyWorkspaceAction({
    checklist:original,
    action:{action:'record',itemId:'example:R001',state:'not_satisfied',evidenceRefs:['E1'],reviewerNotes:'Requirement is not met by the reviewed release.'},
    candidate,registry,registryBytes,readArtefact
  });
  const rejected=applyWorkspaceAction({
    checklist:failed,
    action:{action:'authorize',decision:'rejected',confirm:'REJECT',reviewerId:'reviewer-2',reviewedAt:'2026-09-27T00:11:00.000Z',summary:'Review rejected because a required control is not satisfied.'},
    candidate,registry,registryBytes,readArtefact
  });
  if(rejected.humanAuthorization.status!=='rejected')fail('self-test: rejection was not recorded');

  const expectFail=(name,checklist,action)=>{
    let failedAction=false;
    try{applyWorkspaceAction({checklist,action,candidate,registry,registryBytes,readArtefact})}catch{failedAction=true}
    if(!failedAction)fail('self-test expected failure: '+name);
  };

  expectFail('unknown evidence',original,{action:'record',itemId:'example:R001',state:'satisfied',evidenceRefs:['E99'],reviewerNotes:''});
  expectFail('satisfied without support',original,{action:'record',itemId:'example:R001',state:'satisfied',evidenceRefs:[],reviewerNotes:''});
  expectFail('wrong approval confirmation',completed,{action:'authorize',decision:'approved',confirm:'YES',reviewerId:'reviewer-1',reviewedAt:'2026-09-27T00:10:00.000Z',summary:'Approved.'});
  expectFail('reject without failed item',completed,{action:'authorize',decision:'rejected',confirm:'REJECT',reviewerId:'reviewer-1',reviewedAt:'2026-09-27T00:10:00.000Z',summary:'Rejected.'});
  expectFail('secret-like notes',original,{action:'record',itemId:'example:R001',state:'not_satisfied',evidenceRefs:['E1'],reviewerNotes:'token=abcdefghijklmnop'});

  console.log('SHINE DEFENCE REVIEW WORKSPACE SELF-TEST: PASS 4 healthy transitions + 7 fail-closed cases');
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

  const registryBytes=readFileSync(join(root,registryPath));
  const registry=JSON.parse(registryBytes.toString('utf8'));
  const relativePath=join(reviewDir,candidate.candidateId+'.json');
  const fullPath=join(root,relativePath);
  if(!existsSync(fullPath))fail('review checklist missing; generate it first with generate-review-checklist-v1.mjs');

  const checklist=JSON.parse(readFileSync(fullPath,'utf8'));
  const currentFailures=validateReviewChecklist({checklist,candidate,registry,registryBytes,readArtefact:readCanonical});
  if(currentFailures.length)fail('current checklist is invalid: '+currentFailures.join('; '));

  let suggestionArtifact=null;
  const suggestionPath=join(suggestionDir,candidate.candidateId+'.json');
  const suggestionFull=join(root,suggestionPath);
  if(existsSync(suggestionFull)){
    suggestionArtifact=JSON.parse(readFileSync(suggestionFull,'utf8'));
    const suggestionFailures=validateEvidenceSuggestions({
      artifact:suggestionArtifact,candidate,checklist,registry,registryBytes,readArtefact:readCanonical
    });
    if(suggestionFailures.length)fail('evidence suggestion artifact invalid: '+suggestionFailures.join('; '));
  }

  if(!args.actionFile){
    printStatus(checklist,suggestionArtifact);
    return;
  }

  const action=readAction(args.actionFile);
  const next=applyWorkspaceAction({
    checklist,
    action,
    candidate,
    registry,
    registryBytes,
    readArtefact:readCanonical
  });

  console.log('SHINE DEFENCE REVIEW WORKSPACE PLAN');
  console.log('candidate: '+candidate.candidateId);
  console.log('action: '+action.action+(action.action==='record'?' '+action.itemId+' -> '+action.state:' -> '+action.decision));
  console.log((args.apply?'WRITE ':'WOULD WRITE ')+relativePath);
  printStatus(next,suggestionArtifact);

  if(!args.apply){
    console.log('DRY RUN: no files changed.');
    return;
  }

  const original=readFileSync(fullPath);
  try{
    atomicWrite(fullPath,Buffer.from(json(next)));
    runVerification();
    console.log('SHINE DEFENCE REVIEW WORKSPACE: APPLIED '+candidate.candidateId);
  }catch(error){
    atomicWrite(fullPath,original);
    console.error('SHINE DEFENCE REVIEW WORKSPACE: ROLLED BACK');
    throw error;
  }
}

main();
