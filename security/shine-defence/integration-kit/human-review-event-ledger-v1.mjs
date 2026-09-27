#!/usr/bin/env node
import {createHash} from 'node:crypto';
import {existsSync,readdirSync,readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {applyAction,createReview} from './human-diff-review-v1.mjs';

export const SHINE_DEFENCE_HUMAN_REVIEW_EVENT_LEDGER_VERSION='1.0.0';
const root=fileURLToPath(new URL('../../../',import.meta.url));
const ledgerDir=join(root,'security/shine-defence/human-review-events');
const fail=m=>{throw new Error(m)};
const canonical=v=>JSON.stringify(v);
const hashEventBody=body=>createHash('sha256').update(canonical(body)).digest('hex');
const clone=v=>JSON.parse(JSON.stringify(v));

export function createEventLedger(pack){
  const body={
    sequence:1,type:'review_started',at:pack.deploymentObservedAt||null,previousEventHash:null,
    reviewId:pack.appId+'-'+pack.observedCommitSha.slice(0,12),appId:pack.appId,repository:pack.repository,
    reviewedCommitSha:pack.reviewedCommitSha,observedCommitSha:pack.observedCommitSha,deploymentObservationId:pack.deploymentObservationId,
    pack:{
      deploymentObservedAt:pack.deploymentObservedAt||null,
      compare:clone(pack.compare),
      reviewFocus:{files:clone(pack.reviewFocus.files)}
    }
  };
  return {ledger:'shine-defence/human-review-events-v1',version:'1.0.0',reviewId:body.reviewId,events:[{...body,eventHash:hashEventBody(body)}]};
}
export function appendActionEvent({ledger,action}){
  const failures=verifyEventLedger(ledger);if(failures.length)fail(failures.join('; '));
  const last=ledger.events.at(-1);
  const type=action.action==='record_finding'?'finding_recorded':action.action==='accept_evidence'?'evidence_accepted':null;
  if(!type)fail('unsupported human review event action');
  const body={sequence:last.sequence+1,type,at:action.reviewedAt,previousEventHash:last.eventHash,action:clone(action)};
  return {...clone(ledger),events:[...clone(ledger.events),{...body,eventHash:hashEventBody(body)}]};
}
export function verifyEventLedger(ledger){
  const failures=[];
  if(ledger?.ledger!=='shine-defence/human-review-events-v1'||ledger.version!=='1.0.0'||!Array.isArray(ledger.events)||!ledger.events.length)return ['unsupported or empty human review event ledger'];
  for(let i=0;i<ledger.events.length;i++){
    const e=ledger.events[i],body=clone(e);delete body.eventHash;
    if(e.sequence!==i+1)failures.push('event '+(i+1)+' sequence mismatch');
    if(i===0){
      if(e.type!=='review_started'||e.previousEventHash!==null)failures.push('first event must be review_started with null previous hash');
      if(e.reviewId!==ledger.reviewId)failures.push('review id mismatch');
    }else{
      if(e.previousEventHash!==ledger.events[i-1].eventHash)failures.push('event '+(i+1)+' previous hash mismatch');
      if(Date.parse(e.at)<Date.parse(ledger.events[i-1].at))failures.push('event '+(i+1)+' timestamp moved backwards');
    }
    if(e.eventHash!==hashEventBody(body))failures.push('event '+(i+1)+' hash mismatch');
  }
  return failures;
}
export function packFromLedger(ledger){
  const first=ledger.events[0];
  return {
    appId:first.appId,repository:first.repository,reviewedCommitSha:first.reviewedCommitSha,observedCommitSha:first.observedCommitSha,
    deploymentObservationId:first.deploymentObservationId,deploymentObservedAt:first.pack.deploymentObservedAt,
    compare:clone(first.pack.compare),reviewFocus:{files:clone(first.pack.reviewFocus.files)}
  };
}
export function replayEventLedger(ledger){
  const failures=verifyEventLedger(ledger);if(failures.length)fail(failures.join('; '));
  const pack=packFromLedger(ledger);let review=createReview(pack);
  for(const event of ledger.events.slice(1))review=applyAction({review,pack,action:event.action});
  return {pack,review};
}
export function verifyProjection({ledger,review}){
  const replayed=replayEventLedger(ledger).review;
  return canonical(replayed)===canonical(review)?[]:['stored human review projection differs from event-ledger replay'];
}
function loadLive(){
  if(!existsSync(ledgerDir))return {report:'shine-defence/human-review-event-ledgers-v1',version:'1.0.0',ledgers:0,events:0,failures:[]};
  const files=readdirSync(ledgerDir).filter(x=>x.endsWith('.json')).sort(),failures=[];let events=0;
  for(const file of files){const ledger=JSON.parse(readFileSync(join(ledgerDir,file),'utf8'));events+=ledger.events?.length||0;for(const f of verifyEventLedger(ledger))failures.push(file+': '+f)}
  return {report:'shine-defence/human-review-event-ledgers-v1',version:'1.0.0',ledgers:files.length,events,failures};
}
function selfTest(){
  const pack={appId:'app',repository:'owner/app',reviewedCommitSha:'a'.repeat(40),observedCommitSha:'b'.repeat(40),deploymentObservationId:'obs',deploymentObservedAt:'2026-09-27T06:00:00.000Z',compare:{totalCommits:2,changedFiles:1,additions:1,deletions:0},reviewFocus:{files:[{filename:'a.ts',reviewFocus:'security_or_auth'}]}};
  let ledger=createEventLedger(pack);
  ledger=appendActionEvent({ledger,action:{action:'record_finding',filename:'a.ts',state:'reviewed_attention',notes:'First pass.',reviewerId:'alice',reviewedAt:'2026-09-27T06:10:00.000Z'}});
  ledger=appendActionEvent({ledger,action:{action:'record_finding',filename:'a.ts',state:'reviewed_no_issue',notes:'Resolved after deeper review.',reviewerId:'alice',reviewedAt:'2026-09-27T06:20:00.000Z'}});
  ledger=appendActionEvent({ledger,action:{action:'accept_evidence',confirmation:'ACCEPT EVIDENCE',reviewerId:'alice',reviewedAt:'2026-09-27T06:30:00.000Z',summary:'Reviewed and resolved attention item.'}});
  const {review}=replayEventLedger(ledger);
  if(review.findings[0].state!=='reviewed_no_issue'||review.findings[0].notes!=='Resolved after deeper review.')fail('replay did not derive latest finding');
  if(ledger.events.length!==4||verifyEventLedger(ledger).length)fail('ledger verification mismatch');
  const tampered=clone(ledger);tampered.events[1].action.notes='tampered';if(!verifyEventLedger(tampered).some(x=>x.includes('hash mismatch')))fail('tamper was not detected');
  if(verifyProjection({ledger,review}).length)fail('valid replay projection mismatch');
  console.log('SHINE DEFENCE HUMAN REVIEW EVENT LEDGER SELF-TEST: PASS append-only hash chain, superseded finding history, replay projection and tamper detection');
}
function main(){if(process.argv.includes('--self-test'))return selfTest();const r=loadLive();console.log(JSON.stringify(r,null,2));if(r.failures.length)process.exitCode=1}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)main();
