#!/usr/bin/env node
import {pathToFileURL} from 'node:url';
import {
  buildCommandCentre,
  checkpointIntegrity,
  loadLiveCommandCentreCore
} from './command-centre-core-v1.mjs';
import {loadLiveSnapshotPlan} from './timeline-snapshot-planner-v1.mjs';

export {buildCommandCentre,checkpointIntegrity} from './command-centre-core-v1.mjs';
export const SHINE_DEFENCE_COMMAND_CENTRE_VERSION='1.4.0';

const compactChanges=items=>(items||[]).map(item=>({
  appId:item.appId,
  kind:item.kind||'changed',
  status:item.status||null,
  dimensions:(item.changes||[]).map(change=>change.dimension)
}));

export function summarizeTimelinePlanning(plan){
  if(!plan||typeof plan!=='object')throw new Error('timeline plan is required');
  const state=plan.state||'unsupported_change';
  const nextAction=plan.nextAction?{
    id:plan.nextAction.id,
    humanRequired:Boolean(plan.nextAction.humanRequired),
    description:plan.nextAction.description||null
  }:null;
  return {
    state,
    requiresHumanReview:state==='unsupported_change'||Boolean(nextAction?.humanRequired),
    latest:plan.latest||null,
    candidate:plan.candidate||null,
    counts:plan.counts||{materialApps:0,snapshotHashOnlyApps:0,unsupportedApps:0},
    unsupportedChanges:compactChanges(plan.unsupportedChanges),
    materialChanges:compactChanges(plan.materialChanges),
    snapshotHashChanges:(plan.snapshotHashChanges||[]).map(item=>({
      appId:item.appId,
      dimensions:(item.changes||[]).map(change=>change.dimension)
    })),
    nextAction
  };
}

export function loadLiveCommandCentre(asOf=new Date().toISOString()){
  const base=loadLiveCommandCentreCore(asOf);
  const timelinePlanning=summarizeTimelinePlanning(loadLiveSnapshotPlan(asOf));
  return {...base,version:'1.4.0',timelinePlanning};
}

function printHuman(report){
  console.log('SHINE DEFENCE COMMAND CENTRE');
  console.log('reviewed apps: '+report.reviewedApps);
  console.log('intake ready: '+report.counts.intakeReady);
  console.log('coverage: '+JSON.stringify(report.counts.coverage));
  console.log('deployment: '+JSON.stringify(report.counts.deployment));
  console.log('review progress: '+JSON.stringify(report.counts.reviewProgress));
  console.log('timeline planning: '+report.timelinePlanning.state+(report.timelinePlanning.requiresHumanReview?' — HUMAN REVIEW REQUIRED':''));
  if(report.timelinePlanning.state==='unsupported_change'){
    for(const change of report.timelinePlanning.unsupportedChanges){
      console.log('  unsupported: '+change.appId+' / '+change.kind+(change.status?' / '+change.status:'')+(change.dimensions.length?' / '+change.dimensions.join(','):''));
    }
  }
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
    {appId:'a',repository:'o/a',state:'protected',reviewState:'none',certificationState:'canonical_reviewed_release',deployment:{state:'protected',observedReleaseCommitSha:'a'.repeat(40)},nextAction:{id:'none'}}
  ]};
  const report=buildCommandCentre({
    operations,
    coverage:{items:[{appId:'a',state:'observed'}]},
    plan:{items:[]},
    readiness:{items:[]},
    reviewProgressFn:()=>({state:'not_applicable',detail:null})
  });
  if(report.reviewedApps!==1||report.items[0].appId!=='a')throw new Error('base Command Centre projection mismatch');
  const pending=checkpointIntegrity({appId:'definitely-missing-checkpoint-fixture',reviewProgress:{state:'evidence_accepted'},deployment:{releaseCommitSha:'b'.repeat(40)}});
  if(pending.state!=='pending')throw new Error('checkpoint projection mismatch');
  const timeline=summarizeTimelinePlanning({
    state:'unsupported_change',
    counts:{materialApps:0,snapshotHashOnlyApps:0,unsupportedApps:1},
    unsupportedChanges:[{appId:'a',kind:'unsupported_dimension',changes:[{dimension:'futureDimension'}]}],
    materialChanges:[],
    snapshotHashChanges:[],
    nextAction:{id:'review_unsupported_manifest_change',humanRequired:true,description:'Review.'}
  });
  if(timeline.state!=='unsupported_change'||!timeline.requiresHumanReview||timeline.unsupportedChanges[0].dimensions[0]!=='futureDimension')throw new Error('timeline unsupported-change visibility mismatch');
  console.log('SHINE DEFENCE COMMAND CENTRE SELF-TEST: PASS base estate projection, checkpoint visibility and fail-closed timeline-planning visibility');
}

function main(){
  if(process.argv.includes('--self-test'))return selfTest();
  const r=loadLiveCommandCentre();
  if(process.argv.includes('--json'))console.log(JSON.stringify(r,null,2));else printHuman(r);
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)main();
