#!/usr/bin/env node
import {readFileSync,renameSync,statSync,writeFileSync} from 'node:fs';
import {dirname,isAbsolute,join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

export const SHINE_DEFENCE_INTAKE_VERSION='1.0.0';

const root=fileURLToPath(new URL('../../../',import.meta.url));
const queuePath='security/shine-defence/review-candidates-v1.json';
const ledgerPath='security/shine-defence/ecosystem-profile-ledger-v1.json';
const registryPath='security/shine-defence/canonical-registry-v1.json';

const SHA=/^[a-f0-9]{40}$/;
const SEMVER=/^\d+\.\d+\.\d+$/;
const ID=/^[a-z0-9][a-z0-9._-]{0,127}$/;
const REPO=/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const ISO=/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/;
const secretLike=/(?:bearer\s+[a-z0-9._-]{12,}|sk-[a-z0-9_-]{12,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(?:token|secret|password)\s*[=:]\s*[^\s]{8,})/i;

const json=value=>JSON.stringify(value,null,2)+'\n';
const clone=value=>JSON.parse(JSON.stringify(value));

function fail(message){throw new Error(message)}
function cleanText(value,max){return typeof value==='string'&&value.trim().length>0&&value.length<=max&&!secretLike.test(value)}
function validPath(value){return typeof value==='string'&&value.length>0&&value.length<=256&&!value.startsWith('/')&&!value.split('/').includes('..')}
function sameArray(a,b){return JSON.stringify(a)===JSON.stringify(b)}
function sameIdentity(a,b){
  return a.appId===b.appId&&
    a.repository===b.repository&&
    a.releaseCommitSha===b.releaseCommitSha&&
    a.profilePath===b.profilePath&&
    a.profileBlobSha===b.profileBlobSha&&
    a.profileVersion===b.profileVersion&&
    sameArray(a.policies,b.policies);
}
function candidateIdFor(input){return input.appId+'-'+input.releaseCommitSha.slice(0,12)}
function readJson(relativePath){return JSON.parse(readFileSync(join(root,relativePath),'utf8'))}
function atomicWrite(fullPath,bytes){
  const temp=fullPath+'.tmp-'+process.pid;
  writeFileSync(temp,bytes);
  renameSync(temp,fullPath);
}

export function buildCandidateIntake({input,queue,ledger,registry}){
  if(!input||typeof input!=='object'||Array.isArray(input))fail('intake input must be a JSON object');
  const allowed=new Set(['appId','repository','releaseCommitSha','profilePath','profileBlobSha','profileVersion','policies','observedAt','evidence']);
  for(const key of Object.keys(input))if(!allowed.has(key))fail('unknown intake field '+key);

  if(!ID.test(input.appId||''))fail('invalid appId');
  if(!REPO.test(input.repository||''))fail('invalid repository');
  if(!SHA.test(input.releaseCommitSha||''))fail('invalid releaseCommitSha');
  if(!validPath(input.profilePath))fail('invalid profilePath');
  if(!SHA.test(input.profileBlobSha||''))fail('invalid profileBlobSha');
  if(!SEMVER.test(input.profileVersion||''))fail('invalid profileVersion');
  if(!ISO.test(input.observedAt||'')||!Number.isFinite(Date.parse(input.observedAt)))fail('invalid observedAt');
  if(!Array.isArray(input.policies)||!input.policies.length||new Set(input.policies).size!==input.policies.length)fail('invalid policies');
  if(!Array.isArray(input.evidence)||!input.evidence.length||input.evidence.length>16)fail('evidence must contain 1 to 16 records');

  if(queue.ledger!=='shine-defence/review-candidates-v1'||queue.version!=='1.0.0'||!Array.isArray(queue.candidates))fail('unsupported review candidate queue');
  if(ledger.ledger!=='shine-defence/ecosystem-profile-ledger-v1'||!Array.isArray(ledger.apps))fail('unsupported ecosystem profile ledger');
  if(registry.registry!=='shine-defence/canonical-registry-v1'||!Array.isArray(registry.entries))fail('unsupported canonical registry');

  const canonical=new Set(registry.entries.map(entry=>entry.id));
  for(const policy of input.policies){
    if(!ID.test(policy))fail('invalid policy id '+String(policy));
    if(!canonical.has(policy))fail('unknown canonical policy '+policy);
  }

  for(const [index,evidence] of input.evidence.entries()){
    if(!evidence||typeof evidence!=='object'||Array.isArray(evidence))fail('invalid evidence '+index);
    const keys=Object.keys(evidence);
    const allowedEvidence=new Set(['source','kind','reference','checkedAt','summary']);
    for(const key of keys)if(!allowedEvidence.has(key))fail('unknown evidence field '+key+' at '+index);
    for(const required of allowedEvidence)if(!(required in evidence))fail('missing evidence '+required+' at '+index);
    if(!cleanText(evidence.source,64)||!cleanText(evidence.kind,64)||!cleanText(evidence.reference,256)||!cleanText(evidence.summary,500))fail('invalid or secret-like evidence '+index);
    if(!ISO.test(evidence.checkedAt||'')||!Number.isFinite(Date.parse(evidence.checkedAt)))fail('invalid evidence checkedAt '+index);
    if(Date.parse(evidence.checkedAt)>Date.parse(input.observedAt))fail('evidence '+index+' was checked after observedAt');
  }

  const candidateId=candidateIdFor(input);
  const candidate={
    candidateId,
    appId:input.appId,
    repository:input.repository,
    releaseCommitSha:input.releaseCommitSha,
    profilePath:input.profilePath,
    profileBlobSha:input.profileBlobSha,
    profileVersion:input.profileVersion,
    policies:clone(input.policies),
    status:'pending_review',
    observedAt:input.observedAt,
    evidence:clone(input.evidence)
  };

  const app=ledger.apps.find(entry=>entry.id===input.appId);
  const appHistory=queue.candidates.filter(item=>item.appId===input.appId);

  if(queue.candidates.some(item=>item.status==='pending_review'&&item.appId===input.appId))fail('app already has a pending_review candidate');
  if(queue.candidates.some(item=>sameIdentity(item,candidate)))fail('exact release/profile/policy identity already exists in candidate history');

  const collision=queue.candidates.find(item=>item.candidateId===candidateId);
  if(collision)fail('deterministic candidateId collision: '+candidateId);

  if(app){
    if(input.repository!==app.repo||input.profilePath!==app.path)fail('reviewed app repository/profile path mismatch');
    const sameCurrent=
      input.releaseCommitSha===app.reviewCommitSha&&
      input.profileBlobSha===app.profileBlobSha&&
      input.profileVersion===app.profileVersion&&
      sameArray(input.policies,app.policies);
    if(sameCurrent)fail('candidate is already the current reviewed release');
  }else{
    for(const prior of appHistory){
      if(prior.repository!==input.repository||prior.profilePath!==input.profilePath)fail('pre-certification app history has conflicting repository/profile path');
    }
  }

  const nextQueue=clone(queue);
  nextQueue.candidates.push(candidate);
  return {candidate,queue:nextQueue};
}

function parseArgs(argv){
  const result={apply:false};
  for(let i=0;i<argv.length;i++){
    const arg=argv[i];
    if(arg==='--apply'){result.apply=true;continue}
    if(arg==='--self-test'){result.selfTest=true;continue}
    if(arg==='--help'||arg==='-h'){result.help=true;continue}
    if(arg==='--input'){
      if(i+1>=argv.length)fail('--input requires a path');
      result.input=argv[++i];
      continue;
    }
    fail('unknown argument '+arg);
  }
  return result;
}

function usage(){
  console.log(`Shine Defence candidate intake v${SHINE_DEFENCE_INTAKE_VERSION}

Usage:
  node security/shine-defence/integration-kit/intake-review-v1.mjs \\
    --input <candidate-intake.json> [--apply]

The input JSON contains app/release/profile identity, canonical policy ids, observedAt and
1-16 evidence records. Without --apply the helper is a dry-run. Intake writes only the
review-candidate queue and never grants certification.
`);
}

function readInput(inputPath){
  if(!inputPath)fail('--input is required');
  const full=isAbsolute(inputPath)?inputPath:resolve(process.cwd(),inputPath);
  const info=statSync(full);
  if(!info.isFile()||info.size>64*1024)fail('input must be a JSON file no larger than 64 KiB');
  let value;
  try{value=JSON.parse(readFileSync(full,'utf8'))}catch{fail('input is not valid JSON')}
  return value;
}

function verifyQueueFile(){
  const scripts=[
    'security/shine-defence/integration-kit/verify-registry-v1.mjs',
    'security/shine-defence/integration-kit/verify-review-candidates-v1.mjs',
    'security/shine-defence/integration-kit/verify-review-promotions-v1.mjs'
  ];
  for(const script of scripts){
    const result=spawnSync(process.execPath,[script],{cwd:root,encoding:'utf8'});
    if(result.stdout)process.stdout.write(result.stdout);
    if(result.stderr)process.stderr.write(result.stderr);
    if(result.status!==0)fail('verification failed: '+script);
  }
}

function selfTest(){
  const sha='a'.repeat(40),profile='b'.repeat(40),reviewed='c'.repeat(40);
  const evidence=[{source:'github',kind:'security_review',reference:'owner/app@'+sha,checkedAt:'2026-09-27T01:00:00.000Z',summary:'Reviewed release evidence.'}];
  const registry={registry:'shine-defence/canonical-registry-v1',version:'1.0.0',entries:[{id:'baseline'}]};
  const newApp={
    appId:'new-app',repository:'owner/new-app',releaseCommitSha:sha,
    profilePath:'security/shine-defence/profile.json',profileBlobSha:profile,
    profileVersion:'1.0.0',policies:['baseline'],observedAt:'2026-09-27T01:01:00.000Z',evidence
  };
  const baseQueue={ledger:'shine-defence/review-candidates-v1',version:'1.0.0',candidates:[]};
  const baseLedger={ledger:'shine-defence/ecosystem-profile-ledger-v1',version:'1.1.0',apps:[]};

  const built=buildCandidateIntake({input:newApp,queue:baseQueue,ledger:baseLedger,registry});
  if(built.candidate.candidateId!=='new-app-'+sha.slice(0,12)||built.candidate.status!=='pending_review')fail('self-test: candidate construction failed');
  if(built.queue.candidates.length!==1)fail('self-test: queue append failed');

  const reviewedInput={...newApp,appId:'app',repository:'owner/app',releaseCommitSha:sha};
  const reviewedLedger={...baseLedger,apps:[{
    id:'app',repo:'owner/app',path:'security/shine-defence/profile.json',
    profileBlobSha:profile,policies:['baseline'],reviewCommitSha:reviewed,profileVersion:'1.0.0'
  }]};
  const recheck=buildCandidateIntake({input:reviewedInput,queue:baseQueue,ledger:reviewedLedger,registry});
  if(recheck.candidate.appId!=='app')fail('self-test: reviewed app intake failed');

  const expectFail=(name,mutate,{queue=baseQueue,ledger=baseLedger}={})=>{
    const input=clone(newApp);const q=clone(queue);const l=clone(ledger);
    mutate(input,q,l);
    let failed=false;try{buildCandidateIntake({input,queue:q,ledger:l,registry})}catch{failed=true}
    if(!failed)fail('self-test expected failure: '+name);
  };
  expectFail('unknown policy',input=>{input.policies=['unknown']});
  expectFail('evidence after observedAt',input=>{input.evidence[0].checkedAt='2026-09-27T02:00:00.000Z'});
  expectFail('secret-like evidence',input=>{input.evidence[0].summary='token=abcdefghijklmnop'});
  expectFail('duplicate identity',(input,q)=>{q.candidates.push({...buildCandidateIntake({input,queue:baseQueue,ledger:baseLedger,registry}).candidate,status:'dismissed'})});
  expectFail('existing pending',(input,q)=>{q.candidates.push({...buildCandidateIntake({input,queue:baseQueue,ledger:baseLedger,registry}).candidate})});
  expectFail('conflicting pre-cert repo',(input,q)=>{q.candidates.push({...buildCandidateIntake({input,queue:baseQueue,ledger:baseLedger,registry}).candidate,status:'dismissed',repository:'other/repo'})});
  expectFail('same reviewed release',(input,q,l)=>{
    l.apps.push({id:'new-app',repo:'owner/new-app',path:'security/shine-defence/profile.json',profileBlobSha:profile,policies:['baseline'],reviewCommitSha:sha,profileVersion:'1.0.0'});
  });
  expectFail('reviewed app path drift',(input,q,l)=>{
    l.apps.push({id:'new-app',repo:'owner/new-app',path:'security/other.json',profileBlobSha:profile,policies:['baseline'],reviewCommitSha:reviewed,profileVersion:'1.0.0'});
  });

  console.log('SHINE DEFENCE CANDIDATE INTAKE SELF-TEST: PASS 2 healthy + 8 fail-closed cases');
}

function main(){
  const args=parseArgs(process.argv.slice(2));
  if(args.help){usage();return}
  if(args.selfTest){selfTest();return}

  const input=readInput(args.input);
  const built=buildCandidateIntake({
    input,
    queue:readJson(queuePath),
    ledger:readJson(ledgerPath),
    registry:readJson(registryPath)
  });

  console.log('SHINE DEFENCE CANDIDATE INTAKE PLAN');
  console.log('candidate: '+built.candidate.candidateId);
  console.log('app: '+built.candidate.appId);
  console.log('release: '+built.candidate.releaseCommitSha);
  console.log('evidence records: '+built.candidate.evidence.length);
  console.log((args.apply?'WRITE ':'WOULD WRITE ')+queuePath);

  if(!args.apply){
    console.log('DRY RUN: no files changed. Intake does not certify the release.');
    return;
  }

  const full=join(root,queuePath);
  const original=readFileSync(full);
  try{
    atomicWrite(full,Buffer.from(json(built.queue)));
    verifyQueueFile();
    console.log('SHINE DEFENCE CANDIDATE INTAKE: APPLIED '+built.candidate.candidateId);
  }catch(error){
    atomicWrite(full,original);
    console.error('SHINE DEFENCE CANDIDATE INTAKE: ROLLED BACK');
    throw error;
  }
}

main();
