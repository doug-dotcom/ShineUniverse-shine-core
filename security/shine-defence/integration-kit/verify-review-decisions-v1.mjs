#!/usr/bin/env node
import {readFileSync} from 'node:fs';

const root=new URL('../../../',import.meta.url);
const queue=JSON.parse(readFileSync(new URL('security/shine-defence/review-candidates-v1.json',root),'utf8'));
const ledger=JSON.parse(readFileSync(new URL('security/shine-defence/review-decisions-v1.json',root),'utf8'));

const ID=/^[a-z0-9][a-z0-9._-]{0,127}$/;
const ISO=/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/;
const secretLike=/(?:bearer\s+[a-z0-9._-]{12,}|sk-[a-z0-9_-]{12,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(?:token|secret|password)\s*[=:]\s*[^\s]{8,})/i;
const finals=new Set(['accepted','superseded','dismissed']);
const candidates=new Map((queue.candidates||[]).map(c=>[c.candidateId,c]));
const decisions=new Map();
const failures=[];

const cleanText=(value,max)=>typeof value==='string'&&value.length>0&&value.length<=max&&!secretLike.test(value);

if(queue.ledger!=='shine-defence/review-candidates-v1'||queue.version!=='1.0.0'||!Array.isArray(queue.candidates)){
  failures.push('unsupported review candidate queue');
}
if(ledger.ledger!=='shine-defence/review-decisions-v1'||ledger.version!=='1.0.0'||!Array.isArray(ledger.decisions)){
  failures.push('unsupported review decision ledger');
}

for(const d of ledger.decisions||[]){
  if(!ID.test(d.decisionId||''))failures.push((d.decisionId||'<missing>')+': invalid decision id');
  if(!ID.test(d.candidateId||''))failures.push((d.decisionId||'<missing>')+': invalid candidate id');
  if(!ID.test(d.appId||''))failures.push((d.decisionId||'<missing>')+': invalid app id');
  if(!finals.has(d.outcome))failures.push((d.decisionId||'<missing>')+': invalid outcome');
  if(!ISO.test(d.decidedAt||'')||!Number.isFinite(Date.parse(d.decidedAt)))failures.push((d.decisionId||'<missing>')+': invalid decidedAt');
  if(!ID.test(d.authority||''))failures.push((d.decisionId||'<missing>')+': invalid authority');
  if(!cleanText(d.summary,500))failures.push((d.decisionId||'<missing>')+': invalid or secret-like summary');
  if(decisions.has(d.candidateId))failures.push(d.candidateId+': multiple decision records');
  else decisions.set(d.candidateId,d);

  const c=candidates.get(d.candidateId);
  if(!c){failures.push((d.decisionId||'<missing>')+': candidate missing from queue');continue}
  if(d.decisionId!==d.candidateId+'-'+d.outcome)failures.push(d.decisionId+': non-deterministic decision id');
  if(d.appId!==c.appId)failures.push(d.decisionId+': app id mismatch');
  if(d.outcome!==c.status)failures.push(d.decisionId+': outcome does not match candidate status');
  if(Number.isFinite(Date.parse(d.decidedAt))&&Number.isFinite(Date.parse(c.observedAt))&&Date.parse(d.decidedAt)<Date.parse(c.observedAt)){
    failures.push(d.decisionId+': decision predates candidate observation');
  }

  if(d.outcome==='superseded'){
    if(!ID.test(d.successorCandidateId||''))failures.push(d.decisionId+': successor candidate missing');
    if(d.successorCandidateId!==c.supersededByCandidateId)failures.push(d.decisionId+': successor does not match queue');
    const next=candidates.get(d.successorCandidateId);
    if(!next||next.appId!==d.appId)failures.push(d.decisionId+': successor missing or belongs to another app');
  }else if(d.successorCandidateId!==undefined){
    failures.push(d.decisionId+': successor is only valid for superseded outcomes');
  }
}

for(const c of queue.candidates||[]){
  const d=decisions.get(c.candidateId);
  if(c.status==='pending_review'&&d)failures.push(c.candidateId+': pending candidate must not have a decision');
  if(finals.has(c.status)&&!d)failures.push(c.candidateId+': finalized candidate missing decision record');
}

if(failures.length){for(const failure of failures)console.error('FAIL '+failure);process.exit(1)}
console.log('SHINE DEFENCE REVIEW DECISIONS: PASS '+ledger.decisions.length+' finalized decisions; '+(queue.candidates.length-ledger.decisions.length)+' pending candidates');
