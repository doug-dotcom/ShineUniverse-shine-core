#!/usr/bin/env node
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {existsSync,mkdirSync,readFileSync,renameSync,rmSync,writeFileSync} from 'node:fs';
import {dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {assertApprovedReviewChecklist} from './review-checklist-lib-v1.mjs';

export const SHINE_DEFENCE_ONBOARDER_VERSION='2.0.0';

const root=fileURLToPath(new URL('../../../',import.meta.url));
const paths={
  queue:'security/shine-defence/review-candidates-v1.json',
  decisions:'security/shine-defence/review-decisions-v1.json',
  ledger:'security/shine-defence/ecosystem-profile-ledger-v1.json',
  registry:'security/shine-defence/canonical-registry-v1.json',
  receipts:'security/shine-defence/receipts',
  snapshots:'security/shine-defence/registry-snapshots',
  reviewChecklists:'security/shine-defence/review-checklists'
};

const ID=/^[a-z0-9][a-z0-9._-]{0,127}$/;
const ISO=/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/;
const secretLike=/(?:bearer\s+[a-z0-9._-]{12,}|sk-[a-z0-9_-]{12,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(?:token|secret|password)\s*[=:]\s*[^\s]{8,})/i;

const json=value=>JSON.stringify(value,null,2)+'\n';
const clone=value=>JSON.parse(JSON.stringify(value));
const gitBlobSha=bytes=>createHash('sha1').update(Buffer.from('blob '+bytes.length+'\0')).update(bytes).digest('hex');

function fail(message){throw new Error(message)}
function cleanText(value,max){return typeof value==='string'&&value.trim().length>0&&value.length<=max&&!secretLike.test(value)}
function readJson(relativePath){return JSON.parse(readFileSync(join(root,relativePath),'utf8'))}
function atomicWrite(fullPath,bytes){
  mkdirSync(dirname(fullPath),{recursive:true});
  const temp=fullPath+'.tmp-'+process.pid;
  writeFileSync(temp,bytes);
  renameSync(temp,fullPath);
}
function restoreFile(fullPath,original){
  if(original===null){if(existsSync(fullPath))rmSync(fullPath);return}
  atomicWrite(fullPath,original);
}

export function buildFirstCertification({candidateId,decidedAt,authority,summary,queue,decisions,ledger,registry,registryBytes,receiptExists=false}){
  if(!ID.test(candidateId||''))fail('invalid candidate id');
  if(!ISO.test(decidedAt||'')||!Number.isFinite(Date.parse(decidedAt)))fail('decidedAt must be an ISO UTC timestamp');
  if(!ID.test(authority||''))fail('invalid decision authority');
  if(!cleanText(summary,500))fail('decision summary is empty, too long or looks secret-like');
  if(queue.ledger!=='shine-defence/review-candidates-v1'||!Array.isArray(queue.candidates))fail('unsupported review candidate queue');
  if(decisions.ledger!=='shine-defence/review-decisions-v1'||!Array.isArray(decisions.decisions))fail('unsupported review decision ledger');
  if(ledger.ledger!=='shine-defence/ecosystem-profile-ledger-v1'||!Array.isArray(ledger.apps))fail('unsupported ecosystem profile ledger');
  if(registry.registry!=='shine-defence/canonical-registry-v1'||!Array.isArray(registry.entries))fail('unsupported canonical registry');
  if(!Buffer.isBuffer(registryBytes))fail('registry bytes are required');

  const matches=queue.candidates.filter(candidate=>candidate.candidateId===candidateId);
  if(matches.length!==1)fail('candidate must exist exactly once');
  const candidate=matches[0];
  if(candidate.status!=='pending_review')fail('candidate must be pending_review');
  if(Date.parse(decidedAt)<Date.parse(candidate.observedAt))fail('decision cannot predate candidate observation');

  const appCandidates=queue.candidates.filter(item=>item.appId===candidate.appId);
  if(appCandidates.some(item=>item.status==='accepted'))fail('app already has an accepted review candidate');
  if(ledger.apps.some(app=>app.id===candidate.appId))fail('app already exists in the reviewed ecosystem ledger; use promote-review-v1 for re-certification');
  if(receiptExists)fail('app already has a certification receipt');
  if(decisions.decisions.some(decision=>decision.candidateId===candidateId))fail('candidate already has a review decision');
  if(decisions.decisions.some(decision=>decision.appId===candidate.appId&&decision.outcome==='accepted'))fail('app already has an accepted review decision');

  const canonical=new Map(registry.entries.map(entry=>[entry.id,entry]));
  if(!Array.isArray(candidate.policies)||!candidate.policies.length)fail('candidate has no canonical policies');
  for(const policy of candidate.policies)if(!canonical.has(policy))fail('candidate claims unknown canonical policy '+policy);
  const releaseClaim=canonical.get('release-claim');
  if(!releaseClaim)fail('canonical registry has no release-claim contract');

  const registryBlobSha=gitBlobSha(registryBytes);
  const nextQueue=clone(queue);
  nextQueue.candidates.find(item=>item.candidateId===candidateId).status='accepted';

  const nextLedger=clone(ledger);
  nextLedger.apps.push({
    id:candidate.appId,
    repo:candidate.repository,
    path:candidate.profilePath,
    profileBlobSha:candidate.profileBlobSha,
    policies:clone(candidate.policies),
    reviewCommitSha:candidate.releaseCommitSha,
    profileVersion:candidate.profileVersion
  });

  const nextDecisions=clone(decisions);
  nextDecisions.decisions.push({
    decisionId:candidateId+'-accepted',
    candidateId,
    appId:candidate.appId,
    outcome:'accepted',
    decidedAt,
    authority,
    summary
  });

  const receipt={
    receipt:'shine-defence/certification-receipt-v1',
    version:'1.0.0',
    appId:candidate.appId,
    repository:candidate.repository,
    reviewCommitSha:candidate.releaseCommitSha,
    profilePath:candidate.profilePath,
    profileBlobSha:candidate.profileBlobSha,
    profileVersion:candidate.profileVersion,
    policies:clone(candidate.policies),
    registryVersion:registry.version,
    registryBlobSha,
    releaseClaimContractVersion:releaseClaim.version,
    releaseClaimContractBlobSha:releaseClaim.blobSha
  };

  return {
    candidate,
    queue:nextQueue,
    decisions:nextDecisions,
    ledger:nextLedger,
    receipt,
    registryBlobSha,
    registrySnapshot:Buffer.from(registryBytes)
  };
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
  console.log(`Shine Defence first-certification onboarder v${SHINE_DEFENCE_ONBOARDER_VERSION}

Usage:
  node security/shine-defence/integration-kit/onboard-review-v1.mjs \\
    --candidate <candidateId> [--apply]

The candidate must already exist as pending_review and its canonical review checklist must
contain an explicit approved humanAuthorization. Reviewer identity, reviewedAt and decision
summary are taken only from that validated checklist. Without --apply this is a dry-run.
`);
}

function runVerification(){
  const scripts=[
    'security/shine-defence/integration-kit/verify-registry-v1.mjs',
    'security/shine-defence/integration-kit/verify-ecosystem-ledger-v1.mjs',
    'security/shine-defence/integration-kit/verify-certification-receipts-v1.mjs',
    'security/shine-defence/integration-kit/verify-review-candidates-v1.mjs',
    'security/shine-defence/integration-kit/verify-review-decisions-v1.mjs',
    'security/shine-defence/integration-kit/verify-review-checklists-v1.mjs',
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
  const release='a'.repeat(40),profile='b'.repeat(40),claim='c'.repeat(40);
  const registry={
    registry:'shine-defence/canonical-registry-v1',
    version:'1.0.0',
    entries:[
      {id:'baseline',version:'1.0.0',blobSha:'d'.repeat(40)},
      {id:'release-claim',version:'1.1.0',blobSha:claim}
    ]
  };
  const registryBytes=Buffer.from(json(registry));
  const base={
    candidateId:'new-app-release',
    decidedAt:'2026-09-27T01:00:00.000Z',
    authority:'shine-defence-core',
    summary:'Reviewed the first release and accepted it for initial certification.',
    queue:{ledger:'shine-defence/review-candidates-v1',version:'1.0.0',candidates:[{
      candidateId:'new-app-release',appId:'new-app',repository:'owner/new-app',
      releaseCommitSha:release,profilePath:'security/shine-defence/profile.json',
      profileBlobSha:profile,profileVersion:'1.0.0',policies:['baseline'],
      status:'pending_review',observedAt:'2026-09-27T00:30:00.000Z',evidence:[{}]
    }]},
    decisions:{ledger:'shine-defence/review-decisions-v1',version:'1.0.0',decisions:[]},
    ledger:{ledger:'shine-defence/ecosystem-profile-ledger-v1',version:'1.1.0',apps:[]},
    registry,registryBytes,receiptExists:false
  };

  const built=buildFirstCertification(base);
  if(built.queue.candidates[0].status!=='accepted')fail('self-test: candidate not accepted');
  if(built.ledger.apps.length!==1||built.ledger.apps[0].id!=='new-app')fail('self-test: ledger entry missing');
  if(built.receipt.appId!=='new-app'||built.receipt.reviewCommitSha!==release)fail('self-test: receipt mismatch');
  if(built.decisions.decisions[0].decisionId!=='new-app-release-accepted')fail('self-test: decision missing');

  const expectFail=(name,mutate)=>{
    const state=clone(base);state.registryBytes=Buffer.from(base.registryBytes);
    mutate(state);
    let failed=false;try{buildFirstCertification(state)}catch{failed=true}
    if(!failed)fail('self-test expected failure: '+name);
  };
  expectFail('already reviewed',state=>{state.ledger.apps.push({id:'new-app'})});
  expectFail('existing receipt',state=>{state.receiptExists=true});
  expectFail('candidate already final',state=>{state.queue.candidates[0].status='accepted'});
  expectFail('accepted candidate history',state=>{state.queue.candidates.push({...state.queue.candidates[0],candidateId:'old',status:'accepted'})});
  expectFail('accepted decision history',state=>{state.decisions.decisions.push({candidateId:'old',appId:'new-app',outcome:'accepted'})});
  expectFail('unknown policy',state=>{state.queue.candidates[0].policies=['unknown']});
  expectFail('decision before observation',state=>{state.decidedAt='2026-09-27T00:00:00.000Z'});

  console.log('SHINE DEFENCE FIRST CERTIFICATION SELF-TEST: PASS 1 healthy + 7 fail-closed cases');
}

function main(){
  const args=parseArgs(process.argv.slice(2));
  if(args.help){usage();return}
  if(args.selfTest){selfTest();return}
  if(!args.candidate)fail('--candidate is required');

  const registryPath=join(root,paths.registry);
  const registryBytes=readFileSync(registryPath);
  const registry=JSON.parse(registryBytes.toString('utf8'));
  const queue=readJson(paths.queue);
  const matches=queue.candidates.filter(item=>item.candidateId===args.candidate);
  if(matches.length!==1)fail('candidate must exist exactly once');
  const candidate=matches[0];
  if(candidate.status!=='pending_review')fail('candidate must be pending_review');

  const checklistRelative=join(paths.reviewChecklists,candidate.candidateId+'.json');
  const checklistFull=join(root,checklistRelative);
  if(!existsSync(checklistFull))fail('approved review checklist required: '+checklistRelative);
  const checklist=JSON.parse(readFileSync(checklistFull,'utf8'));
  const approval=assertApprovedReviewChecklist({
    checklist,
    candidate,
    registry,
    registryBytes,
    readArtefact:path=>readFileSync(join(root,path))
  });

  const receiptPath=join(paths.receipts,candidate.appId+'.json');
  const built=buildFirstCertification({
    candidateId:args.candidate,
    decidedAt:approval.reviewedAt,
    authority:approval.reviewerId,
    summary:approval.summary,
    queue,
    decisions:readJson(paths.decisions),
    ledger:readJson(paths.ledger),
    registry,
    registryBytes,
    receiptExists:existsSync(join(root,receiptPath))
  });

  const snapshotPath=join(paths.snapshots,built.registryBlobSha+'.json');
  const planned=[
    [paths.queue,Buffer.from(json(built.queue))],
    [paths.ledger,Buffer.from(json(built.ledger))],
    [receiptPath,Buffer.from(json(built.receipt))],
    [paths.decisions,Buffer.from(json(built.decisions))]
  ];
  const snapshotFull=join(root,snapshotPath);
  if(existsSync(snapshotFull)){
    const existing=readFileSync(snapshotFull);
    if(gitBlobSha(existing)!==built.registryBlobSha||!existing.equals(built.registrySnapshot))fail('existing registry snapshot does not exactly match current canonical registry');
  }else{
    planned.push([snapshotPath,built.registrySnapshot]);
  }

  console.log('SHINE DEFENCE FIRST CERTIFICATION PLAN');
  console.log('candidate: '+built.candidate.candidateId);
  console.log('app: '+built.candidate.appId);
  console.log('release: '+built.candidate.releaseCommitSha);
  console.log('human reviewer: '+approval.reviewerId);
  console.log('human reviewedAt: '+approval.reviewedAt);
  console.log('checklist: '+checklistRelative);
  console.log('registry snapshot: '+built.registryBlobSha+(existsSync(snapshotFull)?' (existing)':' (new)'));
  for(const [relativePath] of planned)console.log('  '+(args.apply?'WRITE ':'WOULD WRITE ')+relativePath);

  if(!args.apply){
    console.log('DRY RUN: no files changed. Human approval was validated but not applied.');
    return;
  }

  const originals=new Map();
  try{
    for(const [relativePath,bytes] of planned){
      const full=join(root,relativePath);
      originals.set(full,existsSync(full)?readFileSync(full):null);
      atomicWrite(full,bytes);
    }
    runVerification();
    console.log('SHINE DEFENCE FIRST CERTIFICATION: APPLIED '+built.candidate.candidateId);
  }catch(error){
    for(const [full,original] of [...originals.entries()].reverse())restoreFile(full,original);
    console.error('SHINE DEFENCE FIRST CERTIFICATION: ROLLED BACK');
    throw error;
  }
}

main();
