#!/usr/bin/env node
import {existsSync,readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';

export const SHINE_DEFENCE_STALENESS_VISIBILITY_VERSION='1.1.0';
const root=fileURLToPath(new URL('../../../',import.meta.url));
const P={ledger:'security/shine-defence/ecosystem-profile-ledger-v1.json',candidates:'security/shine-defence/review-candidates-v1.json',decisions:'security/shine-defence/review-decisions-v1.json',reviews:'security/shine-defence/human-diff-reviews'};
const readJson=p=>JSON.parse(readFileSync(join(root,p),'utf8'));
const fail=m=>{throw new Error(m)};
const DAY=86400000;

export function ageAt(timestamp,asOf){
  if(!timestamp)return {timestamp:null,ageHours:null,ageDays:null,band:'unknown'};
  const t=Date.parse(timestamp),n=Date.parse(asOf);
  if(!Number.isFinite(t)||!Number.isFinite(n))fail('invalid staleness timestamp');
  if(t>n)fail('future timestamp in staleness report');
  const ms=n-t,hours=ms/3600000,days=ms/DAY;
  return {timestamp,ageHours:Number(hours.toFixed(2)),ageDays:Number(days.toFixed(2)),band:hours<24?'current':days<7?'ageing':'stale'};
}
const na=()=>({timestamp:null,ageHours:null,ageDays:null,band:'not_applicable'});
const unknown=()=>({timestamp:null,ageHours:null,ageDays:null,band:'unknown'});

export function buildStaleness({commandCentre,ledger,candidates,decisions,asOf,readReview}){
  const apps=new Map((ledger.apps||[]).map(a=>[a.id,a]));
  const pending=new Map((candidates.candidates||[]).filter(c=>c.status==='pending_review').map(c=>[c.appId,c]));
  const acceptedByApp=new Map();
  for(const d of decisions.decisions||[]){
    if(d.outcome!=='accepted')continue;
    const old=acceptedByApp.get(d.appId);
    if(!old||d.decidedAt>old.decidedAt)acceptedByApp.set(d.appId,d);
  }
  const items=[];
  for(const item of commandCentre.items||[]){
    const app=apps.get(item.appId);
    const candidate=pending.get(item.appId);
    const decision=acceptedByApp.get(item.appId);
    const deployment=item.deployment?.observedAt?ageAt(item.deployment.observedAt,asOf):unknown();
    const candidateAge=candidate?ageAt(candidate.observedAt,asOf):na();

    let reviewAge=na();
    if(item.reviewProgress?.state==='not_started')reviewAge=unknown();
    else if(item.reviewProgress?.state==='in_progress'){
      const release=item.deployment?.releaseCommitSha;
      const id=release?item.appId+'-'+release.slice(0,12):null;
      const review=id?readReview(id):null;
      reviewAge=review?.lastActivityAt?ageAt(review.lastActivityAt,asOf):unknown();
    }
    else if(item.reviewProgress?.state==='evidence_accepted'||item.reviewProgress?.state==='candidate_intake_ready'){
      const release=item.deployment?.releaseCommitSha;
      const id=release?item.appId+'-'+release.slice(0,12):null;
      const review=id?readReview(id):null;
      reviewAge=review?.humanAcceptance?.reviewedAt?ageAt(review.humanAcceptance.reviewedAt,asOf):unknown();
    }

    let certification=unknown();
    if(decision&&app&&candidateMatch(decision,candidates,app))certification=ageAt(decision.decidedAt,asOf);

    items.push({appId:item.appId,repository:item.repository,deploymentObservation:deployment,humanReview:reviewAge,pendingCandidate:candidateAge,certification});
  }
  const counts={deploymentObservation:{},humanReview:{},pendingCandidate:{},certification:{}};
  for(const i of items)for(const k of Object.keys(counts)){const b=i[k].band;counts[k][b]=(counts[k][b]||0)+1}
  return {report:'shine-defence/staleness-visibility-v1',version:'1.1.0',asOf,apps:items.length,counts,items};
}
function candidateMatch(decision,candidates,app){
  const c=(candidates.candidates||[]).find(x=>x.candidateId===decision.candidateId);
  return Boolean(c&&c.releaseCommitSha===app.reviewCommitSha&&c.profileBlobSha===app.profileBlobSha);
}
function selfTest(){
  const cc={items:[
    {appId:'a',repository:'o/a',deployment:{observedAt:'2026-09-27T00:00:00.000Z',releaseCommitSha:'b'.repeat(40)},reviewProgress:{state:'not_started'}},
    {appId:'b',repository:'o/b',deployment:{observedAt:'2026-09-20T00:00:00.000Z',releaseCommitSha:'d'.repeat(40)},reviewProgress:{state:'in_progress'}}
  ]};
  const ledger={apps:[{id:'a',reviewCommitSha:'a'.repeat(40),profileBlobSha:'1'.repeat(40)},{id:'b',reviewCommitSha:'c'.repeat(40),profileBlobSha:'2'.repeat(40)}]};
  const candidates={candidates:[
    {candidateId:'a-old',appId:'a',releaseCommitSha:'a'.repeat(40),profileBlobSha:'1'.repeat(40),status:'accepted',observedAt:'2026-09-26T00:00:00.000Z'},
    {candidateId:'b-pending',appId:'b',releaseCommitSha:'e'.repeat(40),profileBlobSha:'2'.repeat(40),status:'pending_review',observedAt:'2026-09-26T12:00:00.000Z'}
  ]};
  const decisions={decisions:[{candidateId:'a-old',appId:'a',outcome:'accepted',decidedAt:'2026-09-26T01:00:00.000Z'}]};
  const r=buildStaleness({commandCentre:cc,ledger,candidates,decisions,asOf:'2026-09-27T12:00:00.000Z',readReview:id=>id.startsWith('b-')?{lastActivityAt:'2026-09-24T12:00:00.000Z'}:null});
  const a=r.items.find(x=>x.appId==='a'),b=r.items.find(x=>x.appId==='b');
  if(a.deploymentObservation.band!=='current'||a.certification.band!=='ageing'||a.humanReview.band!=='unknown')fail('self-test: app a ages');
  if(b.deploymentObservation.band!=='stale'||b.pendingCandidate.band!=='ageing'||b.humanReview.band!=='ageing'||b.humanReview.ageDays!==3||b.certification.band!=='unknown')fail('self-test: app b ages');
  let blocked=false;try{ageAt('2026-09-28T00:00:00.000Z','2026-09-27T00:00:00.000Z')}catch{blocked=true}if(!blocked)fail('self-test: future timestamp accepted');
  console.log('SHINE DEFENCE STALENESS VISIBILITY SELF-TEST: PASS current/ageing/stale/unknown/not-applicable semantics, explicit review activity and future fail-closed');
}
async function main(){
  if(process.argv.includes('--self-test'))return selfTest();
  const idx=process.argv.indexOf('--as-of'),asOf=idx>=0?process.argv[idx+1]:new Date().toISOString();
  const {loadLiveCommandCentre}=await import('./command-centre-v1.mjs');
  const r=buildStaleness({
    commandCentre:loadLiveCommandCentre(),ledger:readJson(P.ledger),candidates:readJson(P.candidates),decisions:readJson(P.decisions),asOf,
    readReview:id=>{const p=join(root,P.reviews,id+'.json');return existsSync(p)?JSON.parse(readFileSync(p,'utf8')):null}
  });
  console.log(JSON.stringify(r,null,2));
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)main();
