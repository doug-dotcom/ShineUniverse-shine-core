#!/usr/bin/env node
import {createHash} from 'node:crypto';
import {existsSync,readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {loadLiveCommandCentre} from './command-centre-v1.mjs';
import {buildReviewSessionSummary} from './review-session-summary-v1.mjs';
import {verifyEventLedger} from './human-review-event-ledger-v1.mjs';
import {verifyCheckpointStore} from './review-integrity-checkpoint-v1.mjs';

export const SHINE_DEFENCE_AUDIT_EXPORT_VERSION='1.0.1';
const root=fileURLToPath(new URL('../../../',import.meta.url));
const P={
  ledger:'security/shine-defence/ecosystem-profile-ledger-v1.json',
  observations:'security/shine-defence/deployment-observations-v1.json',
  reviews:'security/shine-defence/human-diff-reviews',
  events:'security/shine-defence/human-review-events',
  checkpoints:'security/shine-defence/human-review-checkpoints'
};
const readJson=p=>JSON.parse(readFileSync(join(root,p),'utf8'));
const clone=v=>JSON.parse(JSON.stringify(v));
const sha=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
const fail=m=>{throw new Error(m)};

function boundReviewId(row){return row.deployment?.releaseCommitSha?row.appId+'-'+row.deployment.releaseCommitSha.slice(0,12):null}
function readOptional(path){return existsSync(path)?JSON.parse(readFileSync(path,'utf8')):null}
function safeNextAction(action){return action?{id:action.id,humanRequired:Boolean(action.humanRequired),description:action.description||null}:null}

export function buildAuditExport({app,commandRow,observation,review,eventLedger,checkpointStore,asOf}){
  if(!app||!commandRow||app.id!==commandRow.appId||app.repo!==commandRow.repository)fail('audit export app/Command Centre binding mismatch');
  if(!Number.isFinite(Date.parse(asOf)))fail('audit export asOf must be an ISO timestamp');
  const reviewId=boundReviewId(commandRow);
  if(review&&review.reviewId!==reviewId)fail('human review does not bind current observed release');
  if(eventLedger&&eventLedger.reviewId!==reviewId)fail('event ledger does not bind current observed release');
  if(checkpointStore&&checkpointStore.reviewId!==reviewId)fail('checkpoint store does not bind current observed release');

  let eventVerification={state:'not_applicable',failures:[]};
  if(eventLedger){const failures=verifyEventLedger(eventLedger);eventVerification={state:failures.length?'invalid':'verified',failures};}
  let checkpointVerification={state:'not_applicable',failures:[]};
  if(checkpointStore){
    if(!eventLedger)checkpointVerification={state:'invalid',failures:['checkpoint store exists without event ledger']};
    else{const failures=verifyCheckpointStore({store:checkpointStore,ledger:eventLedger});checkpointVerification={state:failures.length?'invalid':'verified',failures};}
  }else if(review?.state==='evidence_accepted')checkpointVerification={state:'pending',failures:[]};

  const sessionSummary=review?buildReviewSessionSummary(review,eventLedger):null;
  const commandCentre={
    estateState:commandRow.estateState,certification:commandRow.certification,coverage:commandRow.coverage,
    deployment:clone(commandRow.deployment),reviewProgress:clone(commandRow.reviewProgress),
    intakeReadiness:commandRow.intakeReadiness,candidateId:commandRow.candidateId||null,
    staleness:clone(commandRow.staleness||null),checkpointIntegrity:clone(commandRow.checkpointIntegrity||null),
    nextAction:safeNextAction(commandRow.nextAction)
  };
  const body={
    artifact:'shine-defence/audit-export-v1',version:'1.0.0',
    exportMetadata:{appId:app.id,repository:app.repo,asOf},
    certificationIdentity:{
      reviewCommitSha:app.reviewCommitSha,profilePath:app.path,profileBlobSha:app.profileBlobSha,
      profileVersion:app.profileVersion,policies:clone(app.policies)
    },
    commandCentre,
    deploymentObservation:observation?clone(observation):null,
    humanReview:review?clone(review):null,
    reviewEventLedger:eventLedger?{...clone(eventLedger),verification:eventVerification}:null,
    reviewSessionSummary:sessionSummary,
    checkpointIntegrity:checkpointStore?{store:clone(checkpointStore),verification:checkpointVerification}:checkpointVerification,
    provenance:{
      reviewedLedger:'security/shine-defence/ecosystem-profile-ledger-v1.json',
      commandCentre:'security/shine-defence/integration-kit/command-centre-v1.mjs',
      deploymentObservations:'security/shine-defence/deployment-observations-v1.json',
      humanReview:review?'security/shine-defence/human-diff-reviews/'+reviewId+'.json':null,
      reviewEvents:eventLedger?'security/shine-defence/human-review-events/'+reviewId+'.json':null,
      checkpoints:checkpointStore?'security/shine-defence/human-review-checkpoints/'+reviewId+'.json':null
    }
  };
  return {...body,exportSha256:sha(body)};
}

export function loadAuditExport({appId,asOf}){
  const ledger=readJson(P.ledger),app=ledger.apps.find(a=>a.id===appId);if(!app)fail('app is not in canonical reviewed ecosystem ledger');
  const cc=loadLiveCommandCentre(asOf),row=cc.items.find(i=>i.appId===appId);if(!row)fail('reviewed app missing from Command Centre');
  const observations=readJson(P.observations).observations||[];
  const observation=row.deployment?.observationId?observations.find(o=>o.observationId===row.deployment.observationId)||null:null;
  const id=boundReviewId(row);
  const review=id?readOptional(join(root,P.reviews,id+'.json')):null;
  const eventLedger=id?readOptional(join(root,P.events,id+'.json')):null;
  const checkpointStore=id?readOptional(join(root,P.checkpoints,id+'.json')):null;
  return buildAuditExport({app,commandRow:row,observation,review,eventLedger,checkpointStore,asOf});
}
function selfTest(){
  const app={id:'app',repo:'owner/app',reviewCommitSha:'a'.repeat(40),path:'security/profile.json',profileBlobSha:'b'.repeat(40),profileVersion:'1.0.0',policies:['baseline']};
  const row={appId:'app',repository:'owner/app',estateState:'protected',certification:'canonical_reviewed_release',coverage:'observed',deployment:{state:'protected',observationId:'obs',observedAt:'2026-09-27T01:00:00.000Z',releaseCommitSha:'a'.repeat(40),profileBlobSha:'b'.repeat(40)},reviewProgress:{state:'not_applicable'},intakeReadiness:'not_ready',candidateId:null,staleness:null,checkpointIntegrity:{state:'not_applicable'},nextAction:{id:'none',humanRequired:false,helper:null,args:[],description:'No action.'}};
  const observation={observationId:'obs',appId:'app',repository:'owner/app',releaseCommitSha:'a'.repeat(40),profileBlobSha:'b'.repeat(40),observedAt:'2026-09-27T01:00:00.000Z',source:'railway',reference:'deployment:1'};
  const a=buildAuditExport({app,commandRow:row,observation,review:null,eventLedger:null,checkpointStore:null,asOf:'2026-09-27T07:00:00.000Z'});
  const b=buildAuditExport({app,commandRow:row,observation,review:null,eventLedger:null,checkpointStore:null,asOf:'2026-09-27T07:00:00.000Z'});
  if(JSON.stringify(a)!==JSON.stringify(b)||a.exportSha256!==b.exportSha256)fail('audit export is not deterministic');
  if(a.commandCentre.nextAction.helper!==undefined||a.commandCentre.nextAction.args!==undefined)fail('audit export leaked executable next-action details');
  if(a.humanReview!==null||a.reviewEventLedger!==null||a.checkpointIntegrity.state!=='not_applicable')fail('empty review audit semantics mismatch');
  console.log('SHINE DEFENCE AUDIT EXPORT SELF-TEST: PASS deterministic bundle, reviewed identity, bounded next action and empty-review semantics');
}
function main(){
  const args=process.argv.slice(2),ai=args.indexOf('--app'),ti=args.indexOf('--as-of');
  if(args.includes('--self-test'))return selfTest();
  if(ai<0||!args[ai+1])fail('--app is required');
  if(ti<0||!args[ti+1])fail('--as-of is required for deterministic audit export');
  console.log(JSON.stringify(loadAuditExport({appId:args[ai+1],asOf:args[ti+1]}),null,2));
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)main();
