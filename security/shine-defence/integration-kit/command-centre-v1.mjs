#!/usr/bin/env node
import {existsSync,readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {loadLiveOperations} from './operations-controller-v1.mjs';
import {buildCoverage} from './deployment-coverage-v1.mjs';
import {buildIntakePlan} from './plan-review-intake-v1.mjs';
import {loadLiveDeploymentReport} from './deployment-observations-v1.mjs';
import {loadLiveReadiness} from './candidate-intake-readiness-v1.mjs';
import {buildStaleness} from './staleness-visibility-v1.mjs';
import {verifyCheckpointStore} from './review-integrity-checkpoint-v1.mjs';

export const SHINE_DEFENCE_COMMAND_CENTRE_VERSION='1.3.0';
const root=fileURLToPath(new URL('../../../',import.meta.url));
const P={
  ledger:'security/shine-defence/ecosystem-profile-ledger-v1.json',
  candidates:'security/shine-defence/review-candidates-v1.json',
  sources:'security/shine-defence/deployment-sources-v1.json',
  observations:'security/shine-defence/deployment-observations-v1.json',
  exceptions:'security/shine-defence/deployment-source-exceptions-v1.json',
  reviews:'security/shine-defence/human-diff-reviews',
  decisions:'security/shine-defence/review-decisions-v1.json',
  events:'security/shine-defence/human-review-events',
  checkpoints:'security/shine-defence/human-review-checkpoints'
};
const readJson=p=>JSON.parse(readFileSync(join(root,p),'utf8'));

function reviewProgress({appId,operation,planItem,readyItem}){
  if(operation.reviewState&&operation.reviewState!=='none')return {state:'pending_candidate',detail:operation.reviewState};
  if(readyItem?.state==='candidate_intake_ready')return {state:'candidate_intake_ready',detail:readyItem.candidateId};
  if(planItem?.state==='profile_changed_requires_refresh')return {state:'profile_refresh_required',detail:planItem.reason};
  if(planItem?.state==='needs_review_evidence'){
    const id=appId+'-'+planItem.intakeDraft.releaseCommitSha.slice(0,12);
    const path=join(root,P.reviews,id+'.json');
    if(!existsSync(path))return {state:'not_started',detail:'Human diff review has not been started.'};
    try{
      const review=JSON.parse(readFileSync(path,'utf8'));
      const total=Array.isArray(review.findings)?review.findings.length:0;
      const reviewed=Array.isArray(review.findings)?review.findings.filter(f=>f.state!=='unreviewed').length:0;
      const blockers=Array.isArray(review.findings)?review.findings.filter(f=>f.state==='reviewed_blocker').length:0;
      return {state:review.state==='evidence_accepted'?'evidence_accepted':'in_progress',reviewedFiles:reviewed,totalFiles:total,blockers,lastActivityAt:review.lastActivityAt||null,reviewerId:review.humanAcceptance?.reviewerId||null};
    }catch{return {state:'in_progress',detail:'Human diff review artifact is unreadable; existing Defence validators should investigate.'}}
  }
  return {state:'not_applicable',detail:null};
}

function checkpointIntegrity({appId,reviewProgress,deployment}){
  if(reviewProgress?.state!=='evidence_accepted'&&reviewProgress?.state!=='candidate_intake_ready')return {state:'not_applicable',checkpointCount:0,latestCheckpointAt:null};
  const release=deployment?.releaseCommitSha;
  if(!release)return {state:'invalid',checkpointCount:0,latestCheckpointAt:null,reason:'Accepted review has no observed release identity.'};
  const id=appId+'-'+release.slice(0,12),eventPath=join(root,P.events,id+'.json'),checkpointPath=join(root,P.checkpoints,id+'.json');
  if(!existsSync(checkpointPath))return {state:'pending',checkpointCount:0,latestCheckpointAt:null,reason:'Accepted review has no integrity checkpoint yet.'};
  if(!existsSync(eventPath))return {state:'invalid',checkpointCount:0,latestCheckpointAt:null,reason:'Checkpoint exists but event ledger is missing.'};
  try{
    const store=JSON.parse(readFileSync(checkpointPath,'utf8')),ledger=JSON.parse(readFileSync(eventPath,'utf8'));
    const failures=verifyCheckpointStore({store,ledger});
    if(failures.length)return {state:'invalid',checkpointCount:store.checkpoints?.length||0,latestCheckpointAt:store.checkpoints?.at(-1)?.checkpointAt||null,reason:failures.join('; ')};
    return {state:'verified',checkpointCount:store.checkpoints.length,latestCheckpointAt:store.checkpoints.at(-1)?.checkpointAt||null,latestMilestone:store.checkpoints.at(-1)?.milestone||null};
  }catch(error){return {state:'invalid',checkpointCount:0,latestCheckpointAt:null,reason:error.message}}
}

export function buildCommandCentre({operations,coverage,plan,readiness,reviewProgressFn=reviewProgress}){
  const cov=new Map((coverage.items||[]).map(i=>[i.appId,i]));
  const plans=new Map((plan.items||[]).map(i=>[i.appId,i]));
  const ready=new Map((readiness.items||[]).map(i=>[i.appId,i]));
  const items=[];
  for(const op of (operations.items||[]).filter(i=>i.certificationState!=='uncertified').sort((a,b)=>a.appId.localeCompare(b.appId))){
    const deployment=op.deployment||{state:'unobserved'};
    const coverageItem=cov.get(op.appId);
    const readyItem=ready.get(op.appId);
    items.push({
      appId:op.appId,
      repository:op.repository,
      estateState:op.state,
      certification:op.certificationState,
      coverage:coverageItem?.state||'unmapped',
      deployment:{
        state:deployment.state||'unobserved',
        observationId:deployment.observationId||null,
        observedAt:deployment.observedAt||null,
        releaseCommitSha:deployment.observedReleaseCommitSha||null,
        profileBlobSha:deployment.observedProfileBlobSha||null
      },
      reviewProgress:reviewProgressFn({appId:op.appId,operation:op,planItem:plans.get(op.appId),readyItem}),
      intakeReadiness:readyItem?.state||'not_ready',
      candidateId:readyItem?.candidateId||null,
      nextAction:op.nextAction
    });
  }
  const counts={estate:{},coverage:{},deployment:{},reviewProgress:{},intakeReady:0};
  for(const i of items){
    counts.estate[i.estateState]=(counts.estate[i.estateState]||0)+1;
    counts.coverage[i.coverage]=(counts.coverage[i.coverage]||0)+1;
    counts.deployment[i.deployment.state]=(counts.deployment[i.deployment.state]||0)+1;
    counts.reviewProgress[i.reviewProgress.state]=(counts.reviewProgress[i.reviewProgress.state]||0)+1;
    if(i.intakeReadiness==='candidate_intake_ready')counts.intakeReady++;
  }
  return {report:'shine-defence/command-centre-v1',version:'1.0.0',reviewedApps:items.length,counts,items};
}

export function loadLiveCommandCentre(asOf=new Date().toISOString()){
  const ledger=readJson(P.ledger),candidates=readJson(P.candidates),deployment=loadLiveDeploymentReport();
  const report=buildCommandCentre({
    operations:loadLiveOperations(),
    coverage:buildCoverage({ledger,sources:readJson(P.sources),observations:readJson(P.observations),exceptions:readJson(P.exceptions)}),
    plan:buildIntakePlan({deploymentReport:deployment,ledger,candidates}),
    readiness:loadLiveReadiness()
  });
  const stale=buildStaleness({
    commandCentre:report,ledger,candidates,decisions:readJson(P.decisions),asOf,
    readReview:id=>{const p=join(root,P.reviews,id+'.json');return existsSync(p)?JSON.parse(readFileSync(p,'utf8')):null}
  });
  const ages=new Map(stale.items.map(i=>[i.appId,i]));
  const items=report.items.map(i=>({...i,staleness:ages.get(i.appId),checkpointIntegrity:checkpointIntegrity({appId:i.appId,reviewProgress:i.reviewProgress,deployment:i.deployment})}));
  const checkpointCounts={not_applicable:0,pending:0,verified:0,invalid:0};for(const i of items)checkpointCounts[i.checkpointIntegrity.state]++;
  return {...report,version:'1.3.0',asOf,stalenessCounts:stale.counts,checkpointIntegrityCounts:checkpointCounts,items};
}
function printHuman(report){
  console.log('SHINE DEFENCE COMMAND CENTRE');
  console.log('reviewed apps: '+report.reviewedApps);
  console.log('intake ready: '+report.counts.intakeReady);
  console.log('coverage: '+JSON.stringify(report.counts.coverage));
  console.log('deployment: '+JSON.stringify(report.counts.deployment));
  console.log('review progress: '+JSON.stringify(report.counts.reviewProgress));
  for(const i of report.items){
    console.log('');
    console.log(i.appId+' / '+i.repository);
    console.log('  estate: '+i.estateState);
    console.log('  certification: '+i.certification);
    console.log('  coverage: '+i.coverage);
    console.log('  deployment: '+i.deployment.state+(i.deployment.releaseCommitSha?' '+i.deployment.releaseCommitSha.slice(0,12):''));
    console.log('  review: '+i.reviewProgress.state+(i.reviewProgress.totalFiles!==undefined?' '+i.reviewProgress.reviewedFiles+'/'+i.reviewProgress.totalFiles:''));
    console.log('  intake: '+i.intakeReadiness+(i.candidateId?' '+i.candidateId:''));
    if(i.staleness)console.log('  ages: deploy '+i.staleness.deploymentObservation.band+', review '+i.staleness.humanReview.band+', candidate '+i.staleness.pendingCandidate.band+', certification '+i.staleness.certification.band);
    if(i.checkpointIntegrity)console.log('  checkpoint: '+i.checkpointIntegrity.state+(i.checkpointIntegrity.latestCheckpointAt?' @ '+i.checkpointIntegrity.latestCheckpointAt:''));
    console.log('  next: '+i.nextAction.id);
  }
}
function selfTest(){
  const operations={items:[
    {appId:'a',repository:'o/a',state:'protected',reviewState:'none',certificationState:'canonical_reviewed_release',deployment:{state:'protected',observedReleaseCommitSha:'a'.repeat(40)},nextAction:{id:'none'}},
    {appId:'b',repository:'o/b',state:'deployment_drift',reviewState:'none',certificationState:'canonical_reviewed_release',deployment:{state:'deployment_drift',observedReleaseCommitSha:'b'.repeat(40)},nextAction:{id:'plan_observed_release_review'}},
    {appId:'c',repository:'o/c',state:'candidate_intake_ready',reviewState:'none',certificationState:'canonical_reviewed_release',deployment:{state:'deployment_drift',observedReleaseCommitSha:'c'.repeat(40)},nextAction:{id:'apply_candidate_intake'}},
    {appId:'d',repository:'o/d',state:'human_review_required',reviewState:'review_in_progress',certificationState:'reviewed_with_pending_candidate',deployment:{state:'deployment_drift'},nextAction:{id:'review_requirement',humanRequired:true}},
    {appId:'x',repository:'o/x',state:'uncertified_idle',reviewState:'none',certificationState:'uncertified',deployment:{state:'unobserved'},nextAction:{id:'intake_candidate'}}
  ]};
  const coverage={items:[{appId:'a',state:'observed'},{appId:'b',state:'observed'},{appId:'c',state:'observed'},{appId:'d',state:'observed'}]};
  const plan={items:[{appId:'b',state:'needs_review_evidence',intakeDraft:{releaseCommitSha:'b'.repeat(40)}},{appId:'c',state:'needs_review_evidence',intakeDraft:{releaseCommitSha:'c'.repeat(40)}}]};
  const readiness={items:[{appId:'c',state:'candidate_intake_ready',candidateId:'c-cccccccccccc'}]};
  const report=buildCommandCentre({operations,coverage,plan,readiness,reviewProgressFn:({appId,operation,readyItem})=>operation.reviewState!=='none'?{state:'pending_candidate'}:readyItem?{state:'candidate_intake_ready'}:appId==='b'?{state:'not_started'}:{state:'not_applicable'}});
  if(report.reviewedApps!==4)throw new Error('uncertified app leaked into command centre');
  if(report.items.map(i=>i.appId).join(',')!=='a,b,c,d')throw new Error('command centre ordering mismatch');
  if(report.counts.intakeReady!==1||report.counts.deployment.deployment_drift!==3)throw new Error('command centre counts mismatch');
  if(report.items.find(i=>i.appId==='d').reviewProgress.state!=='pending_candidate')throw new Error('pending candidate progress mismatch');
  console.log('SHINE DEFENCE COMMAND CENTRE SELF-TEST: PASS estate join, reviewed-only scope, deterministic ordering and readiness/progress counts');
}
function main(){if(process.argv.includes('--self-test'))return selfTest();const r=loadLiveCommandCentre();if(process.argv.includes('--json'))console.log(JSON.stringify(r,null,2));else printHuman(r)}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)main();
