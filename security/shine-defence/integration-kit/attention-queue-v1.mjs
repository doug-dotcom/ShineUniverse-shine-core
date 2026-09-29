#!/usr/bin/env node
import {pathToFileURL} from 'node:url';
import {loadLiveCommandCentre} from './command-centre-v1.mjs';

export const SHINE_DEFENCE_ATTENTION_QUEUE_VERSION='1.2.0';
const BUCKET_ORDER={human_attention:0,blocked:1,machine_action_available:2,healthy_no_action:3};
const STAGE_ORDER={
  review_unsupported_manifest_change:-20,append_timeline_snapshot:-10,
  review_requirement:0,authorize_approve:1,authorize_reject:1,
  refresh_observed_profile_claims:2,investigate_deployment_proof:3,repair_canonical_receipt_state:3,
  apply_candidate_intake:4,generate_checklist:5,run_first_certification:6,run_recertification:6,
  finalize_rejection:7,record_deployment_observation:8,plan_observed_release_review:9,
  intake_replacement_release:10,intake_candidate:10,none:99
};
const SCOPE_ORDER={estate:0,app:1};

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

const compactTimelineChanges=changes=>(changes||[]).map(change=>({
  appId:change.appId||null,
  kind:change.kind||'changed',
  status:change.status||null,
  dimensions:Array.isArray(change.dimensions)?[...change.dimensions]:[]
}));

export function buildEstateAttention(timelinePlanning){
  if(!timelinePlanning||typeof timelinePlanning!=='object')return [];
  const action=timelinePlanning.nextAction||{id:'none',humanRequired:false,description:null};
  const requiresHuman=timelinePlanning.state==='unsupported_change'||Boolean(timelinePlanning.requiresHumanReview)||Boolean(action.humanRequired);
  if(!requiresHuman||action.id==='none')return [];

  const unsupported=compactTimelineChanges(timelinePlanning.unsupportedChanges);
  const material=compactTimelineChanges(timelinePlanning.materialChanges);
  const relevant=timelinePlanning.state==='unsupported_change'?unsupported:material;
  const affectedApps=[...new Set(relevant.map(change=>change.appId).filter(Boolean))].sort();
  const reason=timelinePlanning.state==='unsupported_change'
    ?'Estate timeline planning contains semantics the current contract cannot safely classify. Explicit human review is required before any timeline action.'
    :'Estate timeline planning has an explicit human-required action. The decision remains separate from every app workflow.';

  return [{
    scope:'estate',
    itemId:'estate:timeline-planning',
    bucket:'human_attention',
    reason,
    estateState:timelinePlanning.state,
    affectedApps,
    unsupportedChanges:unsupported,
    materialChanges:material,
    nextAction:{
      id:action.id||'review_unsupported_manifest_change',
      humanRequired:true,
      description:action.description||null
    }
  }];
}

function sortQueueItems(items){
  return items.sort((a,b)=>
    BUCKET_ORDER[a.bucket]-BUCKET_ORDER[b.bucket]||
    (STAGE_ORDER[a.nextAction?.id]??50)-(STAGE_ORDER[b.nextAction?.id]??50)||
    (SCOPE_ORDER[a.scope]??9)-(SCOPE_ORDER[b.scope]??9)||
    (a.appId||a.itemId||'').localeCompare(b.appId||b.itemId||'')
  );
}

export function buildAttentionQueue(commandCentre){
  const items=(commandCentre.items||[]).map(item=>{
    const attention=classifyAttention(item);
    return {
      scope:'app',
      appId:item.appId,repository:item.repository,bucket:attention.bucket,reason:attention.reason,
      estateState:item.estateState,coverage:item.coverage,deploymentState:item.deployment.state,
      reviewProgress:item.reviewProgress,intakeReadiness:item.intakeReadiness,staleness:item.staleness||null,nextAction:item.nextAction
    };
  });
  sortQueueItems(items);

  const estateItems=buildEstateAttention(commandCentre.timelinePlanning);
  const queueItems=sortQueueItems([...estateItems,...items]);

  const counts={human_attention:0,blocked:0,machine_action_available:0,healthy_no_action:0};
  for(const i of items)counts[i.bucket]++;
  const queueCounts={human_attention:0,blocked:0,machine_action_available:0,healthy_no_action:0};
  for(const i of queueItems)queueCounts[i.bucket]++;

  return {
    report:'shine-defence/attention-queue-v1',version:'1.1.0',
    apps:items.length,estateSignals:estateItems.length,counts,queueCounts,
    estateItems,items,queueItems
  };
}

function printHuman(report){
  console.log('SHINE DEFENCE ATTENTION QUEUE');
  console.log('apps: '+report.apps);
  console.log('estate signals: '+report.estateSignals);
  console.log('human attention: '+report.queueCounts.human_attention);
  console.log('blocked: '+report.queueCounts.blocked);
  console.log('machine action available: '+report.queueCounts.machine_action_available);
  console.log('healthy/no action: '+report.queueCounts.healthy_no_action);
  let last=null;
  for(const i of report.queueItems){
    if(i.bucket!==last){console.log('');console.log(i.bucket.toUpperCase().replaceAll('_',' '));last=i.bucket}
    if(i.scope==='estate'){
      console.log('  ESTATE — timeline planning '+i.estateState+' — next '+i.nextAction.id+(i.affectedApps.length?' — apps '+i.affectedApps.join(', '):''));
    }else{
      console.log('  '+i.appId+' — '+i.estateState+' — next '+i.nextAction.id);
    }
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
  if(JSON.stringify(r.counts)!==JSON.stringify({human_attention:2,blocked:1,machine_action_available:1,healthy_no_action:1}))throw new Error('app attention counts mismatch');
  if(JSON.stringify(r.queueCounts)!==JSON.stringify(r.counts)||r.estateSignals!==0)throw new Error('empty estate attention mismatch');
  if(r.items.map(i=>i.appId).join(',')!=='human-explicit,human-pre,blocked-profile,machine,healthy')throw new Error('app attention ordering mismatch');

  const unsupported=buildAttentionQueue({...cc,timelinePlanning:{
    state:'unsupported_change',requiresHumanReview:true,
    unsupportedChanges:[{appId:'z-app',kind:'unsupported_dimension',status:null,dimensions:['futureDimension']}],
    materialChanges:[],
    nextAction:{id:'review_unsupported_manifest_change',humanRequired:true,description:'Review future semantics.'}
  }});
  if(unsupported.estateSignals!==1||unsupported.queueItems[0].scope!=='estate'||unsupported.queueItems[0].estateState!=='unsupported_change')throw new Error('unsupported estate signal did not rise to queue head');
  if(unsupported.queueCounts.human_attention!==3||unsupported.counts.human_attention!==2)throw new Error('estate/app count separation mismatch');
  if(unsupported.queueItems[0].affectedApps.join(',')!=='z-app'||unsupported.queueItems[0].unsupportedChanges[0].dimensions[0]!=='futureDimension')throw new Error('unsupported estate details mismatch');
  if(unsupported.items.find(i=>i.appId==='human-explicit').nextAction.id!=='review_requirement')throw new Error('estate alert overwrote app workflow authority');

  const material=buildEstateAttention({
    state:'material_change',requiresHumanReview:true,
    materialChanges:[{appId:'a',kind:'changed',dimensions:['deploymentState']}],
    unsupportedChanges:[],
    nextAction:{id:'append_timeline_snapshot',humanRequired:true,description:'Review and append if appropriate.'}
  });
  if(material.length!==1||material[0].nextAction.id!=='append_timeline_snapshot'||material[0].affectedApps[0]!=='a')throw new Error('material estate human action mismatch');

  console.log('SHINE DEFENCE ATTENTION QUEUE SELF-TEST: PASS app buckets, estate timeline escalation, unsupported-change first priority, count separation and app-authority isolation');
}

function main(){
  if(process.argv.includes('--self-test'))return selfTest();
  const r=buildAttentionQueue(loadLiveCommandCentre());
  if(process.argv.includes('--json'))console.log(JSON.stringify(r,null,2));else printHuman(r);
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)main();
