#!/usr/bin/env node
import {loadLiveCommandCentre} from './command-centre-v1.mjs';

export const SHINE_DEFENCE_ATTENTION_QUEUE_VERSION='1.1.0';
const BUCKET_ORDER={human_attention:0,blocked:1,machine_action_available:2,healthy_no_action:3};
const STAGE_ORDER={
  review_requirement:0,authorize_approve:1,authorize_reject:1,
  refresh_observed_profile_claims:2,investigate_deployment_proof:3,repair_canonical_receipt_state:3,
  apply_candidate_intake:4,generate_checklist:5,run_first_certification:6,run_recertification:6,
  finalize_rejection:7,record_deployment_observation:8,plan_observed_release_review:9,
  intake_replacement_release:10,intake_candidate:10,none:99
};

export function classifyAttention(item){
  const action=item.nextAction||{id:'none',humanRequired:false,helper:null};
  const progress=item.reviewProgress?.state||'not_applicable';

  if(action.humanRequired||progress==='in_progress'||progress==='not_started'){
    return {bucket:'human_attention',reason:action.humanRequired?'Current workflow action explicitly requires human judgement.':'Pre-candidate human diff review requires human judgement.'};
  }

  if(
    item.estateState==='blocked_canonical_state'||
    progress==='profile_refresh_required'||
    (item.estateState==='needs_review'&&!action.helper)||
    (!action.helper&&action.id!=='none')
  ){
    return {bucket:'blocked',reason:'Workflow cannot continue through an authorised helper from the current state.'};
  }

  if(action.id!=='none'&&action.helper&&!action.humanRequired){
    return {bucket:'machine_action_available',reason:'An existing guarded helper is available; explicit execution is still required.'};
  }

  return {bucket:'healthy_no_action',reason:'No current Defence action is required.'};
}

export function buildAttentionQueue(commandCentre){
  const items=(commandCentre.items||[]).map(item=>{
    const attention=classifyAttention(item);
    return {
      appId:item.appId,repository:item.repository,bucket:attention.bucket,reason:attention.reason,
      estateState:item.estateState,coverage:item.coverage,deploymentState:item.deployment.state,
      reviewProgress:item.reviewProgress,intakeReadiness:item.intakeReadiness,staleness:item.staleness||null,nextAction:item.nextAction
    };
  });
  items.sort((a,b)=>
    BUCKET_ORDER[a.bucket]-BUCKET_ORDER[b.bucket]||
    (STAGE_ORDER[a.nextAction.id]??50)-(STAGE_ORDER[b.nextAction.id]??50)||
    a.appId.localeCompare(b.appId)
  );
  const counts={human_attention:0,blocked:0,machine_action_available:0,healthy_no_action:0};
  for(const i of items)counts[i.bucket]++;
  return {report:'shine-defence/attention-queue-v1',version:'1.0.0',apps:items.length,counts,items};
}
function printHuman(report){
  console.log('SHINE DEFENCE ATTENTION QUEUE');
  console.log('apps: '+report.apps);
  console.log('human attention: '+report.counts.human_attention);
  console.log('blocked: '+report.counts.blocked);
  console.log('machine action available: '+report.counts.machine_action_available);
  console.log('healthy/no action: '+report.counts.healthy_no_action);
  let last=null;
  for(const i of report.items){
    if(i.bucket!==last){console.log('');console.log(i.bucket.toUpperCase().replaceAll('_',' '));last=i.bucket}
    console.log('  '+i.appId+' — '+i.estateState+' — next '+i.nextAction.id);
  }
}
function selfTest(){
  const cc={items:[
    {appId:'human-explicit',estateState:'human_review_required',coverage:'observed',deployment:{state:'deployment_drift'},reviewProgress:{state:'pending_candidate'},intakeReadiness:'not_ready',nextAction:{id:'review_requirement',humanRequired:true,helper:'review.mjs'}},
    {appId:'human-pre',estateState:'deployment_drift',coverage:'observed',deployment:{state:'deployment_drift'},reviewProgress:{state:'not_started'},intakeReadiness:'not_ready',nextAction:{id:'plan_observed_release_review',humanRequired:false,helper:'plan.mjs'}},
    {appId:'blocked-profile',estateState:'profile_drift',coverage:'observed',deployment:{state:'profile_drift'},reviewProgress:{state:'profile_refresh_required'},intakeReadiness:'not_ready',nextAction:{id:'refresh_observed_profile_claims',humanRequired:false,helper:null}},
    {appId:'machine',estateState:'candidate_intake_ready',coverage:'observed',deployment:{state:'deployment_drift'},reviewProgress:{state:'candidate_intake_ready'},intakeReadiness:'candidate_intake_ready',nextAction:{id:'apply_candidate_intake',humanRequired:false,helper:'intake.mjs'}},
    {appId:'healthy',estateState:'protected',coverage:'observed',deployment:{state:'protected'},reviewProgress:{state:'not_applicable'},intakeReadiness:'not_ready',nextAction:{id:'none',humanRequired:false,helper:null}}
  ]};
  const r=buildAttentionQueue(cc);
  if(JSON.stringify(r.counts)!==JSON.stringify({human_attention:2,blocked:1,machine_action_available:1,healthy_no_action:1}))throw new Error('attention counts mismatch');
  if(r.items.map(i=>i.appId).join(',')!=='human-explicit,human-pre,blocked-profile,machine,healthy')throw new Error('attention ordering mismatch');
  console.log('SHINE DEFENCE ATTENTION QUEUE SELF-TEST: PASS four buckets, human precedence and deterministic workflow ordering');
}
function main(){if(process.argv.includes('--self-test'))return selfTest();const r=buildAttentionQueue(loadLiveCommandCentre());if(process.argv.includes('--json'))console.log(JSON.stringify(r,null,2));else printHuman(r)}
main();
