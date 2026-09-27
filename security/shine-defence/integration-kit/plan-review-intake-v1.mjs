#!/usr/bin/env node
import {readFileSync,statSync} from 'node:fs';
import {isAbsolute,join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {loadLiveDeploymentReport} from './deployment-observations-v1.mjs';
import {buildCandidateIntake} from './intake-review-v1.mjs';

export const SHINE_DEFENCE_REVIEW_INTAKE_PLANNER_VERSION='1.0.0';
const root=fileURLToPath(new URL('../../../',import.meta.url));
const P={
  ledger:'security/shine-defence/ecosystem-profile-ledger-v1.json',
  candidates:'security/shine-defence/review-candidates-v1.json',
  registry:'security/shine-defence/canonical-registry-v1.json'
};
const json=v=>JSON.stringify(v,null,2)+'\n';
const fail=m=>{throw new Error(m)};
const readJson=p=>JSON.parse(readFileSync(join(root,p),'utf8'));

export function buildIntakePlan({deploymentReport,ledger,candidates}){
  const reviewed=new Map((ledger.apps||[]).map(app=>[app.id,app]));
  const pending=new Set((candidates.candidates||[]).filter(c=>c.status==='pending_review').map(c=>c.appId));
  const items=[];

  for(const deployment of [...(deploymentReport.items||[])].sort((a,b)=>a.appId.localeCompare(b.appId))){
    if(deployment.state!=='deployment_drift')continue;
    const app=reviewed.get(deployment.appId);
    if(!app)continue;

    if(pending.has(app.id)){
      items.push({
        appId:app.id,
        repository:app.repo,
        state:'pending_candidate_exists',
        deploymentObservationId:deployment.observationId,
        reason:'The app already has a pending_review candidate; a second candidate must not be planned.'
      });
      continue;
    }

    if(deployment.observedProfileBlobSha!==app.profileBlobSha){
      items.push({
        appId:app.id,
        repository:app.repo,
        state:'profile_changed_requires_refresh',
        deploymentObservationId:deployment.observationId,
        observedReleaseCommitSha:deployment.observedReleaseCommitSha,
        observedProfileBlobSha:deployment.observedProfileBlobSha,
        reviewedProfileBlobSha:app.profileBlobSha,
        reason:'The deployed Defence profile changed, so profileVersion and policy claims cannot be inherited from the reviewed release.'
      });
      continue;
    }

    items.push({
      appId:app.id,
      repository:app.repo,
      state:'needs_review_evidence',
      deploymentObservationId:deployment.observationId,
      deploymentObservedAt:deployment.observedAt,
      intakeDraft:{
        appId:app.id,
        repository:app.repo,
        releaseCommitSha:deployment.observedReleaseCommitSha,
        profilePath:app.path,
        profileBlobSha:deployment.observedProfileBlobSha,
        profileVersion:app.profileVersion,
        policies:JSON.parse(JSON.stringify(app.policies)),
        candidateObservedAt:null,
        evidence:[]
      },
      missing:['candidateObservedAt','reviewEvidence'],
      note:'Deployment identity is prefilled. Add bounded review evidence and an explicit candidateObservedAt before materialization.'
    });
  }

  const states={};for(const item of items)states[item.state]=(states[item.state]||0)+1;
  return {
    planner:'shine-defence/review-intake-planner-v1',
    version:'1.0.0',
    deploymentDriftApps:items.length,
    draftable:states.needs_review_evidence||0,
    blockedProfileRefresh:states.profile_changed_requires_refresh||0,
    blockedExistingPending:states.pending_candidate_exists||0,
    states,
    items
  };
}

export function materializeDraft({planItem,candidateObservedAt,evidence,queue,ledger,registry}){
  if(!planItem||planItem.state!=='needs_review_evidence'||!planItem.intakeDraft)fail('app does not have a materializable deployment-drift draft');
  if(typeof candidateObservedAt!=='string'||!Number.isFinite(Date.parse(candidateObservedAt)))fail('candidateObservedAt must be an ISO timestamp');
  if(Date.parse(candidateObservedAt)<Date.parse(planItem.deploymentObservedAt))fail('candidateObservedAt cannot predate the deployment observation');
  if(!Array.isArray(evidence)||!evidence.length)fail('at least one bounded review-evidence record is required');

  const input={
    appId:planItem.intakeDraft.appId,
    repository:planItem.intakeDraft.repository,
    releaseCommitSha:planItem.intakeDraft.releaseCommitSha,
    profilePath:planItem.intakeDraft.profilePath,
    profileBlobSha:planItem.intakeDraft.profileBlobSha,
    profileVersion:planItem.intakeDraft.profileVersion,
    policies:JSON.parse(JSON.stringify(planItem.intakeDraft.policies)),
    observedAt:candidateObservedAt,
    evidence:JSON.parse(JSON.stringify(evidence))
  };

  buildCandidateIntake({input,queue,ledger,registry});
  return input;
}

function parseArgs(argv){
  const r={json:false};
  for(let i=0;i<argv.length;i++){
    const a=argv[i];
    if(a==='--json'){r.json=true;continue}
    if(a==='--self-test'){r.selfTest=true;continue}
    if(a==='--help'||a==='-h'){r.help=true;continue}
    if(a==='--app'){if(i+1>=argv.length)fail('--app requires a value');r.app=argv[++i];continue}
    if(a==='--materialize'){if(i+1>=argv.length)fail('--materialize requires a bundle path');r.materialize=argv[++i];continue}
    fail('unknown argument '+a);
  }
  return r;
}
function usage(){console.log(`Shine Defence review intake planner v${SHINE_DEFENCE_REVIEW_INTAKE_PLANNER_VERSION}

Plan current deployment drift:
  node security/shine-defence/integration-kit/plan-review-intake-v1.mjs [--app <appId>] [--json]

Materialize one current draft after review evidence exists:
  node security/shine-defence/integration-kit/plan-review-intake-v1.mjs \
    --materialize <bundle.json>

bundle.json:
  {"appId":"shine-daash","candidateObservedAt":"2026-09-27T06:00:00.000Z",
   "evidence":[{"source":"github","kind":"security_diff_review","reference":"...","checkedAt":"...","summary":"..."}]}

Materialization prints ordinary candidate-intake-v1 JSON only. It never writes review-candidates-v1.`)}
function readBundle(path){
  const full=isAbsolute(path)?path:resolve(process.cwd(),path),s=statSync(full);
  if(!s.isFile()||s.size>64*1024)fail('materialization bundle must be JSON no larger than 64 KiB');
  try{return JSON.parse(readFileSync(full,'utf8'))}catch{fail('materialization bundle is not valid JSON')}
}
function livePlan(){
  return buildIntakePlan({
    deploymentReport:loadLiveDeploymentReport(),
    ledger:readJson(P.ledger),
    candidates:readJson(P.candidates)
  });
}
function selfTest(){
  const ledger={ledger:'shine-defence/ecosystem-profile-ledger-v1',version:'1.1.0',apps:[
    {id:'drift',repo:'owner/drift',path:'security/profile.json',profileBlobSha:'b'.repeat(40),profileVersion:'1.2.0',policies:['baseline'],reviewCommitSha:'a'.repeat(40)},
    {id:'profile',repo:'owner/profile',path:'security/profile.json',profileBlobSha:'c'.repeat(40),profileVersion:'1.0.0',policies:['baseline'],reviewCommitSha:'d'.repeat(40)},
    {id:'pending',repo:'owner/pending',path:'security/profile.json',profileBlobSha:'e'.repeat(40),profileVersion:'1.0.0',policies:['baseline'],reviewCommitSha:'f'.repeat(40)}
  ]};
  const report={items:[
    {appId:'drift',state:'deployment_drift',observationId:'obs-1',observedAt:'2026-09-27T01:00:00.000Z',observedReleaseCommitSha:'1'.repeat(40),observedProfileBlobSha:'b'.repeat(40)},
    {appId:'profile',state:'deployment_drift',observationId:'obs-2',observedAt:'2026-09-27T01:00:00.000Z',observedReleaseCommitSha:'2'.repeat(40),observedProfileBlobSha:'9'.repeat(40)},
    {appId:'pending',state:'deployment_drift',observationId:'obs-3',observedAt:'2026-09-27T01:00:00.000Z',observedReleaseCommitSha:'3'.repeat(40),observedProfileBlobSha:'e'.repeat(40)},
    {appId:'protected',state:'protected'}
  ]};
  const candidates={ledger:'shine-defence/review-candidates-v1',version:'1.0.0',candidates:[{appId:'pending',status:'pending_review'}]};
  const plan=buildIntakePlan({deploymentReport:report,ledger,candidates});
  if(plan.draftable!==1||plan.blockedProfileRefresh!==1||plan.blockedExistingPending!==1)fail('planner state counts mismatch');

  const item=plan.items.find(x=>x.appId==='drift');
  const registry={registry:'shine-defence/canonical-registry-v1',version:'1.0.0',entries:[{id:'baseline'}]};
  const evidence=[{source:'github',kind:'security_diff_review',reference:'owner/drift@review',checkedAt:'2026-09-27T01:05:00.000Z',summary:'Human-reviewed security diff evidence.'}];
  const input=materializeDraft({planItem:item,candidateObservedAt:'2026-09-27T01:06:00.000Z',evidence,queue:{ledger:'shine-defence/review-candidates-v1',version:'1.0.0',candidates:[]},ledger,registry});
  if(input.evidence.length!==1||input.releaseCommitSha!=='1'.repeat(40))fail('materialized intake mismatch');

  let blocked=false;try{materializeDraft({planItem:item,candidateObservedAt:'2026-09-27T01:06:00.000Z',evidence:[],queue:{ledger:'shine-defence/review-candidates-v1',version:'1.0.0',candidates:[]},ledger,registry})}catch{blocked=true}
  if(!blocked)fail('empty review evidence was materialized');

  console.log('SHINE DEFENCE REVIEW INTAKE PLANNER SELF-TEST: PASS draft, profile-refresh block, pending block and review-evidence gate');
}
function main(){
  const a=parseArgs(process.argv.slice(2));if(a.help){usage();return}if(a.selfTest){selfTest();return}
  const plan=livePlan();
  if(a.materialize){
    const bundle=readBundle(a.materialize),item=plan.items.find(x=>x.appId===bundle.appId);
    const input=materializeDraft({planItem:item,candidateObservedAt:bundle.candidateObservedAt,evidence:bundle.evidence,queue:readJson(P.candidates),ledger:readJson(P.ledger),registry:readJson(P.registry)});
    console.log(json(input));return
  }
  const output=a.app?{...plan,items:plan.items.filter(x=>x.appId===a.app)}:plan;
  console.log(a.json?JSON.stringify(output,null,2):JSON.stringify(output,null,2));
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)main();
