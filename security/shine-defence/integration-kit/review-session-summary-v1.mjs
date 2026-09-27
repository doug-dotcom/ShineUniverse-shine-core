#!/usr/bin/env node
import {existsSync,readdirSync,readFileSync} from 'node:fs';
import {verifyEventLedger} from './human-review-event-ledger-v1.mjs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

export const SHINE_DEFENCE_REVIEW_SESSION_SUMMARY_VERSION='1.1.0';
const root=fileURLToPath(new URL('../../../',import.meta.url));
const reviewDir=join(root,'security/shine-defence/human-diff-reviews');
const eventDir=join(root,'security/shine-defence/human-review-events');
const SESSION_GAP_MS=60*60*1000;
const fail=m=>{throw new Error(m)};

function actionList(review){
  if(review?.artifact!=='shine-defence/human-diff-review-v1'||!['1.2.0','1.3.0'].includes(review.version))fail('review session summary requires Human Diff Review v1.2+');
  const actions=[];
  for(const f of review.findings||[])if(f.state!=='unreviewed'){
    if(!f.reviewedAt||!f.reviewerId)fail('reviewed finding missing explicit activity metadata');
    actions.push({type:'finding',at:f.reviewedAt,reviewerId:f.reviewerId,filename:f.filename,reviewFocus:f.reviewFocus,findingState:f.state,notesPresent:Boolean(f.notes)});
  }
  if(review.humanAcceptance?.status==='accepted'){
    actions.push({type:'acceptance',at:review.humanAcceptance.reviewedAt,reviewerId:review.humanAcceptance.reviewerId,summaryPresent:Boolean(review.humanAcceptance.summary)});
  }
  actions.sort((a,b)=>a.at.localeCompare(b.at)||a.type.localeCompare(b.type)||(a.filename||'').localeCompare(b.filename||''));
  for(let i=1;i<actions.length;i++)if(Date.parse(actions[i].at)<Date.parse(actions[i-1].at))fail('review activity ordering invalid');
  return actions;
}
function summariseSession(actions,index){
  const start=actions[0].at,end=actions.at(-1).at;
  const reviewers=[...new Set(actions.map(a=>a.reviewerId))].sort();
  const findings=actions.filter(a=>a.type==='finding'),findingStates={},focus={};
  for(const a of findings){findingStates[a.findingState]=(findingStates[a.findingState]||0)+1;focus[a.reviewFocus]=(focus[a.reviewFocus]||0)+1}
  return {
    session:index+1,startAt:start,endAt:end,spanMinutes:Number(((Date.parse(end)-Date.parse(start))/60000).toFixed(2)),
    reviewers,actions:actions.length,fileActions:findings.length,acceptanceActions:actions.filter(a=>a.type==='acceptance').length,
    findingStates,reviewFocus:focus
  };
}
export function buildReviewSessionSummary(review,eventLedger=null){
  let actions=actionList(review),historySource='latest_projection';
  if(eventLedger){
    const failures=verifyEventLedger(eventLedger);if(failures.length)fail(failures.join('; '));
    actions=eventLedger.events.slice(1).map(e=>e.type==='finding_recorded'?{type:'finding',at:e.at,reviewerId:e.action.reviewerId,filename:e.action.filename,reviewFocus:review.findings.find(f=>f.filename===e.action.filename)?.reviewFocus||'other',findingState:e.action.state,notesPresent:Boolean(e.action.notes)}:{type:'acceptance',at:e.at,reviewerId:e.action.reviewerId,summaryPresent:Boolean(e.action.summary)});
    historySource='event_ledger';
  }
  const groups=[];
  for(const action of actions){
    const current=groups.at(-1);
    if(!current||Date.parse(action.at)-Date.parse(current.at(-1).at)>=SESSION_GAP_MS)groups.push([action]);
    else current.push(action);
  }
  const sessions=groups.map(summariseSession),gaps=[];
  for(let i=1;i<sessions.length;i++){
    const start=sessions[i-1].endAt,end=sessions[i].startAt;
    gaps.push({afterSession:i,beforeSession:i+1,startAt:start,endAt:end,minutes:Number(((Date.parse(end)-Date.parse(start))/60000).toFixed(2))});
  }
  const reviewers={};
  for(const a of actions){
    if(!reviewers[a.reviewerId])reviewers[a.reviewerId]={reviewerId:a.reviewerId,actions:0,fileActions:0,acceptanceActions:0,firstActivityAt:a.at,lastActivityAt:a.at};
    const r=reviewers[a.reviewerId];r.actions++;if(a.type==='finding')r.fileActions++;else r.acceptanceActions++;
    if(a.at<r.firstActivityAt)r.firstActivityAt=a.at;if(a.at>r.lastActivityAt)r.lastActivityAt=a.at;
  }
  return {
    artifact:'shine-defence/review-session-summary-v1',version:'1.1.0',
    reviewId:review.reviewId,appId:review.appId,repository:review.repository,state:review.state,
    reviewedCommitSha:review.reviewedCommitSha,observedCommitSha:review.observedCommitSha,
    firstActivityAt:actions[0]?.at||null,lastActivityAt:actions.at(-1)?.at||null,
    explicitActions:actions.length,reviewedFiles:(review.findings||[]).filter(f=>f.state!=='unreviewed').length,totalFiles:(review.findings||[]).length,
    attentionFindings:(review.findings||[]).filter(f=>f.state==='reviewed_attention').length,
    blockerFindings:(review.findings||[]).filter(f=>f.state==='reviewed_blocker').length,
    reviewers:Object.values(reviewers).sort((a,b)=>a.reviewerId.localeCompare(b.reviewerId)),
    sessions,gaps,historySource,
    limitation:historySource==='event_ledger'?'Full v1.3 event-ledger action history is represented.':'Legacy/projection-only review: superseded earlier finding edits cannot be reconstructed.'
  };
}
export function buildEstateReviewSessionReport(reviews,eventLedgers=new Map()){
  const items=reviews.map(review=>buildReviewSessionSummary(review,eventLedgers.get(review.reviewId)||null)).sort((a,b)=>a.appId.localeCompare(b.appId)||a.reviewId.localeCompare(b.reviewId));
  return {report:'shine-defence/review-session-summaries-v1',version:'1.1.0',reviews:items.length,sessions:items.reduce((n,i)=>n+i.sessions.length,0),items};
}
function loadLive(){
  if(!existsSync(reviewDir))return buildEstateReviewSessionReport([]);
  const files=readdirSync(reviewDir).filter(x=>x.endsWith('.json')).sort(),ledgers=new Map();
  if(existsSync(eventDir))for(const f of readdirSync(eventDir).filter(x=>x.endsWith('.json')).sort()){const l=JSON.parse(readFileSync(join(eventDir,f),'utf8'));ledgers.set(l.reviewId,l)}
  return buildEstateReviewSessionReport(files.map(f=>JSON.parse(readFileSync(join(reviewDir,f),'utf8'))),ledgers);
}
function selfTest(){
  const review={artifact:'shine-defence/human-diff-review-v1',version:'1.3.0',reviewId:'app-bbbbbbbbbbbb',appId:'app',repository:'owner/app',state:'evidence_accepted',reviewedCommitSha:'a'.repeat(40),observedCommitSha:'b'.repeat(40),findings:[
    {filename:'a.ts',reviewFocus:'security_or_auth',state:'reviewed_attention',notes:'Check.',reviewerId:'alice',reviewedAt:'2026-09-27T01:00:00.000Z'},
    {filename:'b.ts',reviewFocus:'tests',state:'reviewed_no_issue',notes:null,reviewerId:'alice',reviewedAt:'2026-09-27T01:20:00.000Z'},
    {filename:'c.sql',reviewFocus:'database_or_migration',state:'reviewed_no_issue',notes:null,reviewerId:'bob',reviewedAt:'2026-09-27T03:00:00.000Z'}
  ],humanAcceptance:{status:'accepted',reviewerId:'bob',reviewedAt:'2026-09-27T03:15:00.000Z',summary:'Accepted.'}};
  const r=buildReviewSessionSummary(review);
  if(r.sessions.length!==2||r.gaps.length!==1||r.gaps[0].minutes!==100)fail('session/gap clustering mismatch');
  if(r.reviewers.length!==2||r.reviewers.find(x=>x.reviewerId==='alice').fileActions!==2)fail('reviewer summary mismatch');
  if(r.attentionFindings!==1||r.blockerFindings!==0||r.sessions[1].acceptanceActions!==1)fail('finding/acceptance summary mismatch');
  if(r.sessions[0].spanMinutes!==20||r.sessions[1].spanMinutes!==15)fail('session span mismatch');
  console.log('SHINE DEFENCE REVIEW SESSION SUMMARY SELF-TEST: PASS reviewer activity, 60-minute session boundary, inactivity gaps and acceptance audit');
}
function main(){if(process.argv.includes('--self-test'))return selfTest();console.log(JSON.stringify(loadLive(),null,2))}
main();
