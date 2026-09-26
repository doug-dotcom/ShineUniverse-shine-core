#!/usr/bin/env node
import {readFileSync} from 'node:fs';

const root=new URL('../../../',import.meta.url);
const queue=JSON.parse(readFileSync(new URL('security/shine-defence/review-candidates-v1.json',root),'utf8'));
const ledger=JSON.parse(readFileSync(new URL('security/shine-defence/ecosystem-profile-ledger-v1.json',root),'utf8'));
const registry=JSON.parse(readFileSync(new URL('security/shine-defence/canonical-registry-v1.json',root),'utf8'));

const SHA=/^[a-f0-9]{40}$/;
const SEMVER=/^\d+\.\d+\.\d+$/;
const ID=/^[a-z0-9][a-z0-9._-]{0,127}$/;
const REPO=/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const ISO=/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/;
const secretLike=/(?:bearer\s+[a-z0-9._-]{12,}|sk-[a-z0-9_-]{12,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(?:token|secret|password)\s*[=:]\s*[^\s]{8,})/i;
const statuses=new Set(['pending_review','accepted','superseded','dismissed']);
const canonical=new Set(registry.entries.map(e=>e.id));
const apps=new Map(ledger.apps.map(a=>[a.id,a]));
const candidates=new Map();
const pending=new Map();
const failures=[];

const sameArray=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const cleanText=(value,max)=>typeof value==='string'&&value.length>0&&value.length<=max&&!secretLike.test(value);
const validPath=value=>typeof value==='string'&&value.length>0&&value.length<=256&&!value.startsWith('/')&&!value.split('/').includes('..');
const matchesCurrent=(c,app)=>c.repository===app.repo&&c.profilePath===app.path&&c.releaseCommitSha===app.reviewCommitSha&&c.profileBlobSha===app.profileBlobSha&&c.profileVersion===app.profileVersion&&sameArray(c.policies,app.policies);

if(queue.ledger!=='shine-defence/review-candidates-v1'||queue.version!=='1.0.0'||!Array.isArray(queue.candidates)){
  failures.push('unsupported review candidate queue');
}

for(const c of queue.candidates||[]){
  if(!ID.test(c.candidateId||'')||candidates.has(c.candidateId))failures.push((c.candidateId||'<missing>')+': invalid or duplicate candidate id');
  else candidates.set(c.candidateId,c);
  const app=apps.get(c.appId);
  if(!app){failures.push(c.candidateId+': app not in reviewed ecosystem ledger');continue}
  if(!REPO.test(c.repository||'')||!validPath(c.profilePath))failures.push(c.candidateId+': invalid repository/profile path');
  if(!SHA.test(c.releaseCommitSha||'')||!SHA.test(c.profileBlobSha||''))failures.push(c.candidateId+': invalid release/profile SHA');
  if(!SEMVER.test(c.profileVersion||''))failures.push(c.candidateId+': invalid profile version');
  if(!statuses.has(c.status))failures.push(c.candidateId+': invalid status');
  if(!ISO.test(c.observedAt||'')||!Number.isFinite(Date.parse(c.observedAt)))failures.push(c.candidateId+': invalid observedAt');
  if(!Array.isArray(c.policies)||!c.policies.length||new Set(c.policies).size!==c.policies.length)failures.push(c.candidateId+': invalid policies');
  else for(const id of c.policies)if(!canonical.has(id))failures.push(c.candidateId+': unknown canonical policy '+id);
  if(!Array.isArray(c.evidence)||!c.evidence.length||c.evidence.length>16)failures.push(c.candidateId+': invalid evidence');
  else for(const [i,e] of c.evidence.entries()){
    if(!cleanText(e.source,64)||!cleanText(e.kind,64)||!cleanText(e.reference,256)||!cleanText(e.summary,500))failures.push(c.candidateId+': invalid or secret-like evidence '+i);
    if(!ISO.test(e.checkedAt||'')||!Number.isFinite(Date.parse(e.checkedAt)))failures.push(c.candidateId+': invalid evidence checkedAt '+i);
  }
  if(c.status==='pending_review'){
    if(pending.has(c.appId))failures.push(c.candidateId+': multiple pending candidates for '+c.appId);
    pending.set(c.appId,c.candidateId);
    if(matchesCurrent(c,app))failures.push(c.candidateId+': pending candidate is already the reviewed release');
  }
  if(c.status==='superseded'){
    if(!ID.test(c.supersededByCandidateId||''))failures.push(c.candidateId+': superseded candidate missing successor');
  }
  if(c.status==='dismissed'&&c.decisionReason!==undefined&&!cleanText(c.decisionReason,500))failures.push(c.candidateId+': invalid decision reason');
}

for(const c of queue.candidates||[]){
  if(c.status==='superseded'){
    const next=candidates.get(c.supersededByCandidateId);
    if(!next||next.appId!==c.appId)failures.push(c.candidateId+': successor missing or belongs to another app');
  }
}

if(failures.length){for(const failure of failures)console.error('FAIL '+failure);process.exit(1)}
console.log('SHINE DEFENCE REVIEW CANDIDATES: PASS '+queue.candidates.length+' records; '+pending.size+' pending review');
