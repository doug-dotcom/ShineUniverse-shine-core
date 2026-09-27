#!/usr/bin/env node
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {existsSync,readFileSync,renameSync,statSync,writeFileSync} from 'node:fs';
import {isAbsolute,join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildCandidateIntake} from './intake-review-v1.mjs';
import {buildReviewChecklist,validateReviewChecklist} from './review-checklist-lib-v1.mjs';

export const SHINE_DEFENCE_SUPERSESSION_VERSION='1.0.0';
const root=fileURLToPath(new URL('../../../',import.meta.url));
const P={queue:'security/shine-defence/review-candidates-v1.json',decisions:'security/shine-defence/review-decisions-v1.json',ledger:'security/shine-defence/ecosystem-profile-ledger-v1.json',registry:'security/shine-defence/canonical-registry-v1.json',checklists:'security/shine-defence/review-checklists'};
const ID=/^[a-z0-9][a-z0-9._-]{0,127}$/;
const ISO=/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/;
const secretLike=/(?:bearer\s+[a-z0-9._-]{12,}|sk-[a-z0-9_-]{12,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(?:token|secret|password)\s*[=:]\s*[^\s]{8,})/i;
const json=v=>JSON.stringify(v,null,2)+'\n';
const clone=v=>JSON.parse(JSON.stringify(v));
const gitBlobSha=b=>createHash('sha1').update(Buffer.from('blob '+b.length+'\0')).update(b).digest('hex');
const fail=m=>{throw new Error(m)};
const clean=(v,n)=>typeof v==='string'&&v.trim().length>0&&v.length<=n&&!secretLike.test(v);
const readJson=p=>JSON.parse(readFileSync(join(root,p),'utf8'));
const readCanonical=p=>readFileSync(join(root,p));
function atomicWrite(path,bytes){const t=path+'.tmp-'+process.pid;writeFileSync(t,bytes);renameSync(t,path)}

export function buildCandidateSupersession({transaction,queue,decisions,ledger,registry,registryBytes,oldChecklist=null,oldChecklistBytes=null,readArtefact}){
  if(!transaction||typeof transaction!=='object'||Array.isArray(transaction))fail('supersession transaction must be an object');
  const allowed=new Set(['supersedeCandidateId','supersededAt','authority','summary','successor']);
  for(const k of Object.keys(transaction))if(!allowed.has(k))fail('unknown supersession field '+k);
  if(!ID.test(transaction.supersedeCandidateId||''))fail('invalid supersedeCandidateId');
  if(!ISO.test(transaction.supersededAt||'')||!Number.isFinite(Date.parse(transaction.supersededAt)))fail('invalid supersededAt');
  if(!ID.test(transaction.authority||''))fail('invalid supersession authority');
  if(!clean(transaction.summary,500))fail('invalid or secret-like supersession summary');
  if(!transaction.successor||typeof transaction.successor!=='object'||Array.isArray(transaction.successor))fail('successor intake payload is required');
  if(queue.ledger!=='shine-defence/review-candidates-v1'||!Array.isArray(queue.candidates))fail('unsupported review candidate queue');
  if(decisions.ledger!=='shine-defence/review-decisions-v1'||!Array.isArray(decisions.decisions))fail('unsupported review decision ledger');
  if(!Buffer.isBuffer(registryBytes))fail('registry bytes are required');

  const found=queue.candidates.filter(c=>c.candidateId===transaction.supersedeCandidateId);
  if(found.length!==1)fail('superseded candidate must exist exactly once');
  const old=found[0];
  if(old.status!=='pending_review')fail('superseded candidate must be pending_review');
  if(decisions.decisions.some(d=>d.candidateId===old.candidateId))fail('superseded candidate already has a final decision');
  if(transaction.successor.appId!==old.appId)fail('successor must belong to the same app');
  if(transaction.successor.repository!==old.repository)fail('successor repository must match old candidate');
  if(transaction.successor.profilePath!==old.profilePath)fail('successor profile path must match old candidate');
  if(Date.parse(transaction.successor.observedAt)<Date.parse(old.observedAt))fail('successor observation predates old candidate');
  if(Date.parse(transaction.supersededAt)<Date.parse(old.observedAt)||Date.parse(transaction.supersededAt)<Date.parse(transaction.successor.observedAt))fail('supersededAt predates candidate observation');

  let fingerprint=null;
  if(oldChecklist!==null||oldChecklistBytes!==null){
    if(!oldChecklist||!Buffer.isBuffer(oldChecklistBytes))fail('old checklist and exact bytes must be supplied together');
    const fs=validateReviewChecklist({checklist:oldChecklist,candidate:old,registry,registryBytes,readArtefact});
    if(fs.length)fail('old checklist invalid: '+fs.join('; '));
    if(oldChecklist.humanAuthorization?.status!=='pending')fail('human-finalized checklist cannot be superseded');
    fingerprint={reviewChecklistBlobSha:gitBlobSha(oldChecklistBytes),reviewRegistryBlobSha:oldChecklist.registryBlobSha};
  }

  const staged=clone(queue);
  staged.candidates.find(c=>c.candidateId===old.candidateId).status='superseded';
  const intake=buildCandidateIntake({input:transaction.successor,queue:staged,ledger,registry});
  const successor=intake.candidate;
  if(successor.candidateId===old.candidateId)fail('successor candidate id must differ from old candidate');
  const nextQueue=intake.queue;
  nextQueue.candidates.find(c=>c.candidateId===old.candidateId).supersededByCandidateId=successor.candidateId;

  const decision={decisionId:old.candidateId+'-superseded',candidateId:old.candidateId,appId:old.appId,outcome:'superseded',decidedAt:transaction.supersededAt,authority:transaction.authority,successorCandidateId:successor.candidateId,summary:transaction.summary};
  if(fingerprint)Object.assign(decision,fingerprint);
  const nextDecisions=clone(decisions);nextDecisions.decisions.push(decision);
  return {oldCandidate:old,successor,nextQueue,nextDecisions,decision};
}

function parseArgs(argv){
  const r={apply:false};
  for(let i=0;i<argv.length;i++){
    const a=argv[i];
    if(a==='--apply'){r.apply=true;continue}
    if(a==='--self-test'){r.selfTest=true;continue}
    if(a==='--help'||a==='-h'){r.help=true;continue}
    if(a==='--input'){if(i+1>=argv.length)fail('--input requires a path');r.input=argv[++i];continue}
    fail('unknown argument '+a);
  }
  return r;
}
function usage(){console.log(`Shine Defence candidate supersession v${SHINE_DEFENCE_SUPERSESSION_VERSION}

Usage:
  node security/shine-defence/integration-kit/supersede-candidate-v1.mjs --input <supersession.json> [--apply]

The transaction contains the current pending candidate id, supersession authority/time/reason,
and a complete successor candidate-intake payload. Without --apply this is a dry-run.`)}
function readInput(path){
  if(!path)fail('--input is required');
  const full=isAbsolute(path)?path:resolve(process.cwd(),path),s=statSync(full);
  if(!s.isFile()||s.size>96*1024)fail('input must be a JSON file no larger than 96 KiB');
  try{return JSON.parse(readFileSync(full,'utf8'))}catch{fail('input is not valid JSON')}
}
function verify(){
  const cmds=[
    ['verify-registry-v1.mjs'],['verify-review-candidates-v1.mjs'],['verify-review-decisions-v1.mjs'],
    ['verify-review-checklists-v1.mjs'],['verify-review-evidence-suggestions-v1.mjs'],['verify-review-rejections-v1.mjs'],
    ['verify-review-promotions-v1.mjs'],['review-queue-v1.mjs','--json']
  ];
  for(const [name,...args] of cmds){
    const script='security/shine-defence/integration-kit/'+name;
    const r=spawnSync(process.execPath,[script,...args],{cwd:root,encoding:'utf8'});
    if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);
    if(r.status!==0)fail('verification failed: '+[script,...args].join(' '));
  }
}

function fixture(){
  const oldSha='a'.repeat(40),nextSha='b'.repeat(40),profile='c'.repeat(40);
  const policyBytes=Buffer.from(json({policy:'shine-defence/example-v1',version:'1.0.0',requirements:['Control must be reviewed.']}));
  const registry={registry:'shine-defence/canonical-registry-v1',version:'1.0.0',entries:[{id:'example',path:'example.json',version:'1.0.0',blobSha:gitBlobSha(policyBytes)}]};
  const registryBytes=Buffer.from(json(registry)),readArtefact=p=>p==='example.json'?policyBytes:null;
  const evidence=[{source:'github',kind:'review',reference:'owner/app@old',checkedAt:'2026-09-27T00:00:00.000Z',summary:'Release evidence.'}];
  const old={candidateId:'app-'+oldSha.slice(0,12),appId:'app',repository:'owner/app',releaseCommitSha:oldSha,profilePath:'security/profile.json',profileBlobSha:profile,profileVersion:'1.0.0',policies:['example'],status:'pending_review',observedAt:'2026-09-27T00:00:00.000Z',evidence};
  const successor={appId:'app',repository:'owner/app',releaseCommitSha:nextSha,profilePath:'security/profile.json',profileBlobSha:profile,profileVersion:'1.0.0',policies:['example'],observedAt:'2026-09-27T00:20:00.000Z',evidence:[{...evidence[0],reference:'owner/app@next',checkedAt:'2026-09-27T00:20:00.000Z'}]};
  return {registry,registryBytes,readArtefact,queue:{ledger:'shine-defence/review-candidates-v1',version:'1.0.0',candidates:[old]},decisions:{ledger:'shine-defence/review-decisions-v1',version:'1.0.0',decisions:[]},ledger:{ledger:'shine-defence/ecosystem-profile-ledger-v1',version:'1.1.0',apps:[]},transaction:{supersedeCandidateId:old.candidateId,supersededAt:'2026-09-27T00:21:00.000Z',authority:'shine-defence-core',summary:'A newer release replaced this candidate before review was finalized.',successor},old};
}
function selfTest(){
  const b=fixture();
  const built=buildCandidateSupersession(b);
  if(built.nextQueue.candidates[0].status!=='superseded'||built.nextQueue.candidates[1].status!=='pending_review')fail('self-test: atomic state mismatch');
  if(built.decision.successorCandidateId!==built.successor.candidateId)fail('self-test: successor decision mismatch');
  const checklist=buildReviewChecklist({candidate:b.old,generatedAt:'2026-09-27T00:05:00.000Z',registry:b.registry,registryBytes:b.registryBytes,readArtefact:b.readArtefact});
  const bytes=Buffer.from(json(checklist));
  const locked=buildCandidateSupersession({...b,oldChecklist:checklist,oldChecklistBytes:bytes});
  if(locked.decision.reviewChecklistBlobSha!==gitBlobSha(bytes))fail('self-test: checklist fingerprint missing');

  const expectFail=(name,mutate,withChecklist=false)=>{
    const x=fixture(),cl=buildReviewChecklist({candidate:x.old,generatedAt:'2026-09-27T00:05:00.000Z',registry:x.registry,registryBytes:x.registryBytes,readArtefact:x.readArtefact});
    mutate(x,cl);let failed=false;
    try{buildCandidateSupersession({...x,oldChecklist:withChecklist?cl:null,oldChecklistBytes:withChecklist?Buffer.from(json(cl)):null})}catch{failed=true}
    if(!failed)fail('self-test expected failure: '+name);
  };
  expectFail('old not pending',x=>{x.queue.candidates[0].status='dismissed'});
  expectFail('existing decision',x=>{x.decisions.decisions.push({candidateId:x.old.candidateId})});
  expectFail('different app',x=>{x.transaction.successor.appId='other'});
  expectFail('different repository',x=>{x.transaction.successor.repository='owner/other'});
  expectFail('older successor',x=>{x.transaction.successor.observedAt='2026-09-26T23:59:00.000Z'});
  expectFail('early supersession time',x=>{x.transaction.supersededAt='2026-09-27T00:10:00.000Z'});
  expectFail('human-finalized checklist',(x,cl)=>{cl.policyReviews[0].requirements[0].state='satisfied';cl.policyReviews[0].requirements[0].reviewerNotes='Reviewed.';cl.humanAuthorization={status:'approved',reviewerId:'reviewer-1',reviewedAt:'2026-09-27T00:10:00.000Z',summary:'Approved.'}},true);
  expectFail('duplicate successor identity',x=>{x.queue.candidates.push({...x.old,candidateId:'history',releaseCommitSha:x.transaction.successor.releaseCommitSha,status:'dismissed',observedAt:'2026-09-26T23:00:00.000Z'})});
  console.log('SHINE DEFENCE CANDIDATE SUPERSESSION SELF-TEST: PASS 2 healthy + 8 fail-closed cases');
}

function main(){
  const args=parseArgs(process.argv.slice(2));if(args.help){usage();return}if(args.selfTest){selfTest();return}
  const transaction=readInput(args.input),queue=readJson(P.queue);
  const old=queue.candidates.find(c=>c.candidateId===transaction.supersedeCandidateId);if(!old)fail('superseded candidate not found');
  const checklistFull=join(root,P.checklists,old.candidateId+'.json');
  let oldChecklist=null,oldChecklistBytes=null;
  if(existsSync(checklistFull)){oldChecklistBytes=readFileSync(checklistFull);oldChecklist=JSON.parse(oldChecklistBytes.toString('utf8'))}
  const registryBytes=readFileSync(join(root,P.registry)),registry=JSON.parse(registryBytes.toString('utf8'));
  const built=buildCandidateSupersession({transaction,queue,decisions:readJson(P.decisions),ledger:readJson(P.ledger),registry,registryBytes,oldChecklist,oldChecklistBytes,readArtefact:readCanonical});
  console.log('SHINE DEFENCE CANDIDATE SUPERSESSION PLAN');
  console.log('old: '+built.oldCandidate.candidateId+' -> superseded');
  console.log('successor: '+built.successor.candidateId+' -> pending_review');
  console.log('release: '+built.successor.releaseCommitSha);
  console.log((args.apply?'WRITE ':'WOULD WRITE ')+P.queue);
  console.log((args.apply?'WRITE ':'WOULD WRITE ')+P.decisions);
  console.log('certification state: untouched');
  if(!args.apply){console.log('DRY RUN: no files changed.');return}
  const qf=join(root,P.queue),df=join(root,P.decisions),oq=readFileSync(qf),od=readFileSync(df);
  try{atomicWrite(qf,Buffer.from(json(built.nextQueue)));atomicWrite(df,Buffer.from(json(built.nextDecisions)));verify();console.log('SHINE DEFENCE CANDIDATE SUPERSESSION: APPLIED '+built.successor.candidateId)}
  catch(e){atomicWrite(qf,oq);atomicWrite(df,od);console.error('SHINE DEFENCE CANDIDATE SUPERSESSION: ROLLED BACK');throw e}
}
main();
