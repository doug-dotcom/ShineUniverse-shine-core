#!/usr/bin/env node
import {createHash} from 'node:crypto';
import {existsSync,readdirSync,readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {replayEventLedger,verifyEventLedger,verifyProjection} from './human-review-event-ledger-v1.mjs';

export const SHINE_DEFENCE_REVIEW_INTEGRITY_CHECKPOINT_VERSION='1.0.0';
const root=fileURLToPath(new URL('../../../',import.meta.url));
const checkpointDir=join(root,'security/shine-defence/human-review-checkpoints');
const clone=v=>JSON.parse(JSON.stringify(v));
const canonical=v=>JSON.stringify(v);
const sha=v=>createHash('sha256').update(typeof v==='string'?v:canonical(v)).digest('hex');
const fail=m=>{throw new Error(m)};

export function createCheckpoint({ledger,review,milestone,checkpointAt}){
  const failures=verifyEventLedger(ledger);if(failures.length)fail(failures.join('; '));
  const projectionFailures=verifyProjection({ledger,review});if(projectionFailures.length)fail(projectionFailures.join('; '));
  if(!['evidence_accepted','manual'].includes(milestone))fail('unsupported checkpoint milestone');
  if(!Number.isFinite(Date.parse(checkpointAt)))fail('invalid checkpointAt');
  const last=ledger.events.at(-1);
  if(Date.parse(checkpointAt)<Date.parse(last.at))fail('checkpointAt cannot predate ledger tip');
  if(milestone==='evidence_accepted'&&last.type!=='evidence_accepted')fail('evidence_accepted checkpoint requires accepted ledger tip');
  const binding={
    reviewId:ledger.reviewId,milestone,checkpointAt,eventCount:ledger.events.length,
    ledgerTipHash:last.eventHash,fullLedgerSha256:sha(ledger),projectionSha256:sha(review)
  };
  return {...binding,combinedIntegritySha256:sha(binding)};
}
export function appendCheckpoint({store,checkpoint}){
  const next=store?clone(store):{ledger:'shine-defence/review-integrity-checkpoints-v1',version:'1.0.0',reviewId:checkpoint.reviewId,checkpoints:[]};
  if(next.ledger!=='shine-defence/review-integrity-checkpoints-v1'||next.version!=='1.0.0'||next.reviewId!==checkpoint.reviewId)fail('checkpoint store binding mismatch');
  if(next.checkpoints.some(c=>c.combinedIntegritySha256===checkpoint.combinedIntegritySha256))return next;
  const sequence=next.checkpoints.length+1;
  next.checkpoints.push({sequence,...clone(checkpoint)});
  return next;
}
export function verifyCheckpoint({checkpoint,ledger}){
  const failures=[];
  if(!checkpoint||checkpoint.eventCount<1||checkpoint.eventCount>ledger.events.length)return ['checkpoint event count outside ledger'];
  const prefix={...clone(ledger),events:clone(ledger.events.slice(0,checkpoint.eventCount))};
  const ledgerFailures=verifyEventLedger(prefix);if(ledgerFailures.length)return ledgerFailures.map(x=>'ledger prefix: '+x);
  let replay;try{replay=replayEventLedger(prefix)}catch(e){return ['checkpoint replay failed: '+e.message]}
  const expected=createCheckpoint({ledger:prefix,review:replay.review,milestone:checkpoint.milestone,checkpointAt:checkpoint.checkpointAt});
  for(const k of ['reviewId','milestone','checkpointAt','eventCount','ledgerTipHash','fullLedgerSha256','projectionSha256','combinedIntegritySha256'])if(checkpoint[k]!==expected[k])failures.push(k+' mismatch');
  return failures;
}
export function verifyCheckpointStore({store,ledger}){
  const failures=[];
  if(store?.ledger!=='shine-defence/review-integrity-checkpoints-v1'||store.version!=='1.0.0'||store.reviewId!==ledger.reviewId)return ['checkpoint store binding mismatch'];
  for(let i=0;i<(store.checkpoints||[]).length;i++){
    const c=store.checkpoints[i];if(c.sequence!==i+1)failures.push('checkpoint '+(i+1)+' sequence mismatch');
    for(const f of verifyCheckpoint({checkpoint:c,ledger}))failures.push('checkpoint '+(i+1)+': '+f);
  }
  return failures;
}
function loadLive(){
  if(!existsSync(checkpointDir))return {report:'shine-defence/review-integrity-checkpoints-v1',version:'1.0.0',stores:0,checkpoints:0,failures:[]};
  const files=readdirSync(checkpointDir).filter(x=>x.endsWith('.json')).sort(),failures=[];let checkpoints=0;
  for(const file of files){
    const store=JSON.parse(readFileSync(join(checkpointDir,file),'utf8'));checkpoints+=store.checkpoints?.length||0;
    const eventPath=join(root,'security/shine-defence/human-review-events',store.reviewId+'.json');
    if(!existsSync(eventPath)){failures.push(file+': event ledger missing');continue}
    const ledger=JSON.parse(readFileSync(eventPath,'utf8'));
    for(const f of verifyCheckpointStore({store,ledger}))failures.push(file+': '+f);
  }
  return {report:'shine-defence/review-integrity-checkpoints-v1',version:'1.0.0',stores:files.length,checkpoints,failures};
}
function selfTest(){
  const pack={appId:'app',repository:'owner/app',reviewedCommitSha:'a'.repeat(40),observedCommitSha:'b'.repeat(40),deploymentObservationId:'obs',deploymentObservedAt:'2026-09-27T06:00:00.000Z',compare:{totalCommits:1,changedFiles:1,additions:1,deletions:0},reviewFocus:{files:[{filename:'a.ts',reviewFocus:'tests'}]}};
  const {createEventLedger,appendActionEvent}=globalThis.__eventHelpers||{};
  if(!createEventLedger||!appendActionEvent)fail('self-test event helpers not injected');
}
async function asyncSelfTest(){
  const events=await import('./human-review-event-ledger-v1.mjs');
  const pack={appId:'app',repository:'owner/app',reviewedCommitSha:'a'.repeat(40),observedCommitSha:'b'.repeat(40),deploymentObservationId:'obs',deploymentObservedAt:'2026-09-27T06:00:00.000Z',compare:{totalCommits:1,changedFiles:1,additions:1,deletions:0},reviewFocus:{files:[{filename:'a.ts',reviewFocus:'tests'}]}};
  let ledger=events.createEventLedger(pack);
  ledger=events.appendActionEvent({ledger,action:{action:'record_finding',filename:'a.ts',state:'reviewed_no_issue',notes:'Reviewed.',reviewerId:'alice',reviewedAt:'2026-09-27T06:10:00.000Z'}});
  ledger=events.appendActionEvent({ledger,action:{action:'accept_evidence',confirmation:'ACCEPT EVIDENCE',reviewerId:'alice',reviewedAt:'2026-09-27T06:20:00.000Z',summary:'Accepted.'}});
  const review=events.replayEventLedger(ledger).review;
  const cp=createCheckpoint({ledger,review,milestone:'evidence_accepted',checkpointAt:'2026-09-27T06:20:00.000Z'});
  const store=appendCheckpoint({store:null,checkpoint:cp});
  if(store.checkpoints.length!==1||verifyCheckpointStore({store,ledger}).length)fail('checkpoint verification mismatch');
  const tampered=clone(store);tampered.checkpoints[0].projectionSha256='0'.repeat(64);if(!verifyCheckpointStore({store:tampered,ledger}).length)fail('checkpoint tamper not detected');
  const later=events.appendActionEvent;
  let blocked=false;try{createCheckpoint({ledger:{...ledger,events:ledger.events.slice(0,-1)},review:events.replayEventLedger({...ledger,events:ledger.events.slice(0,-1)}).review,milestone:'evidence_accepted',checkpointAt:'2026-09-27T06:20:00.000Z'})}catch{blocked=true}if(!blocked)fail('acceptance checkpoint allowed without accepted tip');
  console.log('SHINE DEFENCE REVIEW INTEGRITY CHECKPOINT SELF-TEST: PASS ledger/projection binding, historical-prefix verification, tamper detection and acceptance milestone gate');
}
async function main(){if(process.argv.includes('--self-test'))return asyncSelfTest();const r=loadLive();console.log(JSON.stringify(r,null,2));if(r.failures.length)process.exitCode=1}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)main();
