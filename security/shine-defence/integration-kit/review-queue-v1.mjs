#!/usr/bin/env node
import {existsSync,readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {validateReviewChecklist} from './review-checklist-lib-v1.mjs';
import {validateEvidenceSuggestions} from './review-evidence-assistant-lib-v1.mjs';

export const SHINE_DEFENCE_REVIEW_QUEUE_VERSION='1.2.0';

const root=fileURLToPath(new URL('../../../',import.meta.url));
const queuePath='security/shine-defence/review-candidates-v1.json';
const ledgerPath='security/shine-defence/ecosystem-profile-ledger-v1.json';
const registryPath='security/shine-defence/canonical-registry-v1.json';
const checklistDir='security/shine-defence/review-checklists';
const suggestionDir='security/shine-defence/review-evidence-suggestions';

function fail(message){throw new Error(message)}
function readJson(relativePath){return JSON.parse(readFileSync(join(root,relativePath),'utf8'))}
function readCanonical(path){return readFileSync(join(root,path))}
function clone(value){return JSON.parse(JSON.stringify(value))}

function checklistItems(checklist){
  return (checklist?.policyReviews||[]).flatMap(policy=>
    (policy.requirements||[]).map(item=>({...item,policyId:policy.policyId}))
  );
}

function checklistSummary(checklist){
  if(!checklist)return {
    status:'missing',
    authorization:null,
    total:0,
    satisfied:0,
    notSatisfied:0,
    unreviewed:0,
    nextItem:null
  };
  const items=checklistItems(checklist);
  const next=items.find(item=>item.state==='unreviewed')||null;
  return {
    status:'valid',
    authorization:checklist.humanAuthorization?.status||'invalid',
    total:items.length,
    satisfied:items.filter(item=>item.state==='satisfied').length,
    notSatisfied:items.filter(item=>item.state==='not_satisfied').length,
    unreviewed:items.filter(item=>item.state==='unreviewed').length,
    nextItem:next?{
      itemId:next.itemId,
      policyId:next.policyId,
      requirement:next.requirement
    }:null
  };
}

function suggestionSummary(artifact){
  if(!artifact)return {status:'missing',evidenceGapCount:null,suggestedMappingCount:0,nextItemSuggestions:[]};
  return {
    status:'valid',
    evidenceGapCount:(artifact.items||[]).filter(item=>item.evidenceGap).length,
    suggestedMappingCount:(artifact.items||[]).reduce((sum,item)=>sum+(item.suggestions||[]).length,0),
    nextItemSuggestions:[]
  };
}

export function deriveReviewQueueItem({
  candidate,
  reviewedBefore,
  checklist=null,
  checklistFailures=[],
  suggestions=null,
  suggestionFailures=[]
}){
  const reviewType=reviewedBefore?'re_certification':'first_certification';
  const checklistInfo=checklistSummary(checklist);
  let state,nextAction;

  if(checklistFailures.length){
    checklistInfo.status='invalid';
    checklistInfo.errors=clone(checklistFailures);
    state='blocked_invalid_checklist';
    nextAction={
      id:'repair_checklist',
      humanRequired:false,
      description:'Repair or regenerate the canonical checklist before review can continue.'
    };
  }else if(!checklist){
    state='needs_checklist';
    nextAction={
      id:'generate_checklist',
      humanRequired:false,
      description:'Generate the policy-derived structured review checklist.'
    };
  }else{
    const auth=checklist.humanAuthorization?.status;
    if(auth==='approved'){
      state=reviewedBefore?'approved_ready_for_recertification':'approved_ready_for_first_certification';
      nextAction={
        id:reviewedBefore?'run_recertification':'run_first_certification',
        humanRequired:false,
        description:reviewedBefore
          ?'Run the guarded re-certification helper using the approved checklist.'
          :'Run the guarded first-certification helper using the approved checklist.'
      };
    }else if(auth==='rejected'){
      state='rejected_needs_close';
      nextAction={
        id:'finalize_rejection',
        humanRequired:false,
        automationAvailable:true,
        helper:'security/shine-defence/integration-kit/finalize-rejection-v1.mjs',
        description:'Run the guarded rejection finalizer to atomically dismiss the rejected candidate and append its matching decision.'
      };
    }else if(checklistInfo.unreviewed>0){
      state='review_in_progress';
      nextAction={
        id:'review_requirement',
        humanRequired:true,
        itemId:checklistInfo.nextItem.itemId,
        policyId:checklistInfo.nextItem.policyId,
        description:'Review the next outstanding requirement and explicitly record the finding.'
      };
    }else if(checklistInfo.notSatisfied>0){
      state='ready_for_rejection';
      nextAction={
        id:'authorize_reject',
        humanRequired:true,
        description:'Explicitly reject the completed checklist with reviewer identity, timestamp and summary.'
      };
    }else{
      state='ready_for_approval';
      nextAction={
        id:'authorize_approve',
        humanRequired:true,
        description:'Explicitly approve the completed checklist with reviewer identity, timestamp and summary.'
      };
    }
  }

  let evidenceAssistance=suggestionSummary(suggestions);
  if(suggestionFailures.length){
    evidenceAssistance={
      status:'invalid',
      evidenceGapCount:null,
      suggestedMappingCount:0,
      nextItemSuggestions:[],
      errors:clone(suggestionFailures)
    };
  }else if(suggestions&&checklistInfo.nextItem){
    const advisory=(suggestions.items||[]).find(item=>item.itemId===checklistInfo.nextItem.itemId);
    evidenceAssistance.nextItemSuggestions=clone(advisory?.suggestions||[]);
    evidenceAssistance.nextItemEvidenceGap=advisory?.evidenceGap??null;
  }

  return {
    candidateId:candidate.candidateId,
    appId:candidate.appId,
    repository:candidate.repository,
    releaseCommitSha:candidate.releaseCommitSha,
    observedAt:candidate.observedAt,
    reviewType,
    state,
    checklist:checklistInfo,
    evidenceAssistance,
    nextAction
  };
}

export function buildReviewQueueReport(items){
  const sorted=[...items].sort((a,b)=>
    String(a.observedAt).localeCompare(String(b.observedAt))||
    String(a.candidateId).localeCompare(String(b.candidateId))
  );
  const states={};
  let evidenceGaps=0,humanAttention=0;
  for(const item of sorted){
    states[item.state]=(states[item.state]||0)+1;
    if(Number.isInteger(item.evidenceAssistance?.evidenceGapCount))evidenceGaps+=item.evidenceAssistance.evidenceGapCount;
    if(item.nextAction?.humanRequired)humanAttention++;
  }
  return {
    queue:'shine-defence/review-queue-v1',
    version:'1.0.0',
    pendingCandidates:sorted.length,
    humanAttentionRequired:humanAttention,
    knownEvidenceGaps:evidenceGaps,
    states,
    items:sorted
  };
}

export function loadLiveQueue(){
  const queue=readJson(queuePath);
  const ledger=readJson(ledgerPath);
  const registryBytes=readFileSync(join(root,registryPath));
  const registry=JSON.parse(registryBytes.toString('utf8'));
  const reviewedIds=new Set(ledger.apps.map(app=>app.id));
  const pending=(queue.candidates||[]).filter(candidate=>candidate.status==='pending_review');
  const items=[];

  for(const candidate of pending){
    const checklistRelative=join(checklistDir,candidate.candidateId+'.json');
    const checklistFull=join(root,checklistRelative);
    let checklist=null,checklistFailures=[];
    if(existsSync(checklistFull)){
      try{
        checklist=JSON.parse(readFileSync(checklistFull,'utf8'));
        checklistFailures=validateReviewChecklist({
          checklist,candidate,registry,registryBytes,readArtefact:readCanonical
        });
      }catch(error){
        checklistFailures=['invalid checklist: '+String(error.message||error)];
      }
    }

    const suggestionRelative=join(suggestionDir,candidate.candidateId+'.json');
    const suggestionFull=join(root,suggestionRelative);
    let suggestions=null,suggestionFailures=[];
    if(existsSync(suggestionFull)){
      if(!checklist||checklistFailures.length){
        suggestionFailures=['suggestion artifact cannot be trusted until canonical checklist is valid'];
      }else{
        try{
          suggestions=JSON.parse(readFileSync(suggestionFull,'utf8'));
          suggestionFailures=validateEvidenceSuggestions({
            artifact:suggestions,candidate,checklist,registry,registryBytes,readArtefact:readCanonical
          });
        }catch(error){
          suggestionFailures=['invalid suggestion artifact: '+String(error.message||error)];
        }
      }
    }

    items.push(deriveReviewQueueItem({
      candidate,
      reviewedBefore:reviewedIds.has(candidate.appId),
      checklist,
      checklistFailures,
      suggestions,
      suggestionFailures
    }));
  }

  return buildReviewQueueReport(items);
}

function printHuman(report){
  console.log('SHINE DEFENCE REVIEW QUEUE');
  console.log('pending candidates: '+report.pendingCandidates);
  console.log('human attention required: '+report.humanAttentionRequired);
  console.log('known evidence gaps: '+report.knownEvidenceGaps);
  if(!report.items.length){
    console.log('queue: clear');
    return;
  }

  for(const item of report.items){
    console.log('');
    console.log(item.appId+' / '+item.candidateId);
    console.log('  release: '+item.releaseCommitSha);
    console.log('  review type: '+item.reviewType);
    console.log('  state: '+item.state);
    if(item.checklist.status==='valid'){
      console.log('  checklist: '+item.checklist.satisfied+'/'+item.checklist.total+' satisfied; '+item.checklist.notSatisfied+' not satisfied; '+item.checklist.unreviewed+' unreviewed; authorization '+item.checklist.authorization);
    }else{
      console.log('  checklist: '+item.checklist.status);
    }
    console.log('  evidence assistance: '+item.evidenceAssistance.status);
    if(Number.isInteger(item.evidenceAssistance.evidenceGapCount))console.log('  evidence gaps: '+item.evidenceAssistance.evidenceGapCount);
    console.log('  next: '+item.nextAction.id+(item.nextAction.itemId?' '+item.nextAction.itemId:''));
    console.log('  '+item.nextAction.description);
    if(item.evidenceAssistance.nextItemSuggestions?.length){
      console.log('  advisory leads for next requirement:');
      for(const suggestion of item.evidenceAssistance.nextItemSuggestions){
        console.log('    '+suggestion.evidenceId+' ['+suggestion.confidence+'; '+suggestion.score+'] '+suggestion.reason);
      }
    }
  }
}

function parseArgs(argv){
  const result={json:false};
  for(const arg of argv){
    if(arg==='--json'){result.json=true;continue}
    if(arg==='--self-test'){result.selfTest=true;continue}
    if(arg==='--help'||arg==='-h'){result.help=true;continue}
    fail('unknown argument '+arg);
  }
  return result;
}

function usage(){
  console.log(`Shine Defence review queue v${SHINE_DEFENCE_REVIEW_QUEUE_VERSION}

Usage:
  node security/shine-defence/integration-kit/review-queue-v1.mjs [--json]

The queue is read-only. It consolidates pending candidates, checklist progress, advisory
evidence gaps, review readiness and the next required action. --json emits deterministic
machine-readable output.
`);
}

function fakeCandidate(id,appId,observedAt){
  return {
    candidateId:id,
    appId,
    repository:'owner/'+appId,
    releaseCommitSha:(appId[0]||'a').repeat(40),
    observedAt
  };
}

function fakeChecklist(states,authorization='pending'){
  return {
    humanAuthorization:{status:authorization},
    policyReviews:[{
      policyId:'baseline',
      requirements:states.map((state,index)=>({
        itemId:'baseline:R'+String(index+1).padStart(3,'0'),
        requirement:'Requirement '+String(index+1),
        state
      }))
    }]
  };
}

function selfTest(){
  const items=[
    deriveReviewQueueItem({
      candidate:fakeCandidate('new-no-checklist','newapp','2026-09-27T00:01:00.000Z'),
      reviewedBefore:false
    }),
    deriveReviewQueueItem({
      candidate:fakeCandidate('reviewing','reviewing','2026-09-27T00:02:00.000Z'),
      reviewedBefore:true,
      checklist:fakeChecklist(['satisfied','unreviewed']),
      suggestions:{items:[{itemId:'baseline:R002',evidenceGap:false,suggestions:[{evidenceId:'E1',score:0.5,confidence:'high',matchedTerms:['test'],reason:'Matched.'}]}]}
    }),
    deriveReviewQueueItem({
      candidate:fakeCandidate('approve','approve','2026-09-27T00:03:00.000Z'),
      reviewedBefore:true,
      checklist:fakeChecklist(['satisfied','satisfied'])
    }),
    deriveReviewQueueItem({
      candidate:fakeCandidate('reject','reject','2026-09-27T00:04:00.000Z'),
      reviewedBefore:true,
      checklist:fakeChecklist(['satisfied','not_satisfied'])
    }),
    deriveReviewQueueItem({
      candidate:fakeCandidate('approved-first','first','2026-09-27T00:05:00.000Z'),
      reviewedBefore:false,
      checklist:fakeChecklist(['satisfied'],'approved')
    }),
    deriveReviewQueueItem({
      candidate:fakeCandidate('approved-re','existing','2026-09-27T00:06:00.000Z'),
      reviewedBefore:true,
      checklist:fakeChecklist(['satisfied'],'approved')
    }),
    deriveReviewQueueItem({
      candidate:fakeCandidate('rejected','rejected','2026-09-27T00:07:00.000Z'),
      reviewedBefore:true,
      checklist:fakeChecklist(['not_satisfied'],'rejected')
    }),
    deriveReviewQueueItem({
      candidate:fakeCandidate('invalid','invalid','2026-09-27T00:08:00.000Z'),
      reviewedBefore:true,
      checklist:fakeChecklist(['unreviewed']),
      checklistFailures:['registry binding drift'],
      suggestions:{items:[]},
      suggestionFailures:['suggestion drift']
    })
  ];

  const expected=[
    'needs_checklist',
    'review_in_progress',
    'ready_for_approval',
    'ready_for_rejection',
    'approved_ready_for_first_certification',
    'approved_ready_for_recertification',
    'rejected_needs_close',
    'blocked_invalid_checklist'
  ];
  if(JSON.stringify(items.map(item=>item.state))!==JSON.stringify(expected))fail('self-test: queue state derivation mismatch');
  if(items[1].nextAction.itemId!=='baseline:R002'||!items[1].nextAction.humanRequired)fail('self-test: next human review action mismatch');
  if(items[1].evidenceAssistance.nextItemSuggestions[0]?.evidenceId!=='E1')fail('self-test: next evidence lead missing');
  if(items[7].evidenceAssistance.status!=='invalid')fail('self-test: invalid advisory artifact was not surfaced');
  if(items[4].nextAction.id!=='run_first_certification'||items[5].nextAction.id!=='run_recertification')fail('self-test: certification routing mismatch');
  if(items[6].nextAction.id!=='finalize_rejection'||items[6].nextAction.automationAvailable!==true)fail('self-test: rejection finalizer routing mismatch');

  const report=buildReviewQueueReport([...items].reverse());
  if(report.items[0].candidateId!=='new-no-checklist'||report.pendingCandidates!==8)fail('self-test: deterministic queue ordering/count mismatch');
  if(report.humanAttentionRequired!==3)fail('self-test: human attention count mismatch');

  console.log('SHINE DEFENCE REVIEW QUEUE SELF-TEST: PASS 8 workflow states, deterministic ordering, advisory health and next-action routing');
}

function main(){
  const args=parseArgs(process.argv.slice(2));
  if(args.help){usage();return}
  if(args.selfTest){selfTest();return}
  const report=loadLiveQueue();
  if(args.json)console.log(JSON.stringify(report,null,2));
  else printHuman(report);
}


if(process.argv[1]&&join(process.cwd(),process.argv[1])===fileURLToPath(import.meta.url))main();
