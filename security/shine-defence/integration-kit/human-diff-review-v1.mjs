#!/usr/bin/env node
import {existsSync,mkdirSync,readFileSync,renameSync,statSync,writeFileSync} from 'node:fs';
import {isAbsolute,join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {buildLiveEvidencePacks} from './generate-review-evidence-pack-v1.mjs';

export const SHINE_DEFENCE_HUMAN_DIFF_REVIEW_VERSION='1.1.0';
const root=fileURLToPath(new URL('../../../',import.meta.url));
const reviewDir=join(root,'security/shine-defence/human-diff-reviews');
const evidenceDir=join(root,'security/shine-defence/review-evidence-records');
const secretLike=/(?:bearer\s+[a-z0-9._-]{12,}|sk-[a-z0-9_-]{12,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(?:token|secret|password)\s*[=:]\s*[^\s]{8,})/i;
const ISO=/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/;
const ID=/^[a-z0-9][a-z0-9._-]{0,127}$/;
const json=v=>JSON.stringify(v,null,2)+'\n';
const clone=v=>JSON.parse(JSON.stringify(v));
const fail=m=>{throw new Error(m)};
const clean=(v,n)=>typeof v==='string'&&v.trim().length>0&&v.length<=n&&!secretLike.test(v);
function atomicWrite(path,bytes){const t=path+'.tmp-'+process.pid;writeFileSync(t,bytes);renameSync(t,path)}
export function reviewKey(pack){return pack.appId+'-'+pack.observedCommitSha.slice(0,12)}
export function reviewPath(pack){return join(reviewDir,reviewKey(pack)+'.json')}
export function evidencePath(pack){return join(evidenceDir,reviewKey(pack)+'.json')}

function orderedFiles(pack){
  const rank={security_or_auth:0,api_or_server:1,database_or_migration:2,dependency_or_build:3,ci_or_deployment:4,tests:5,other:6};
  return [...pack.reviewFocus.files].sort((a,b)=>(rank[a.reviewFocus]??99)-(rank[b.reviewFocus]??99)||a.filename.localeCompare(b.filename));
}
export function createReview(pack){
  return {
    artifact:'shine-defence/human-diff-review-v1',version:'1.0.0',
    reviewId:reviewKey(pack),appId:pack.appId,repository:pack.repository,
    reviewedCommitSha:pack.reviewedCommitSha,observedCommitSha:pack.observedCommitSha,
    deploymentObservationId:pack.deploymentObservationId,state:'in_progress',
    packSummary:clone(pack.compare),
    findings:orderedFiles(pack).map(f=>({filename:f.filename,reviewFocus:f.reviewFocus,state:'unreviewed',notes:null})),
    humanAcceptance:{status:'pending'}
  };
}
export function validateReview({review,pack}){
  const failures=[];
  if(review?.artifact!=='shine-defence/human-diff-review-v1'||review.version!=='1.0.0')return ['unsupported human diff review'];
  for(const [k,v] of Object.entries({appId:pack.appId,repository:pack.repository,reviewedCommitSha:pack.reviewedCommitSha,observedCommitSha:pack.observedCommitSha,deploymentObservationId:pack.deploymentObservationId}))if(review[k]!==v)failures.push(k+' binding mismatch');
  const expected=orderedFiles(pack);
  if(!Array.isArray(review.findings)||review.findings.length!==expected.length)failures.push('finding count mismatch');
  else for(let i=0;i<expected.length;i++){
    const f=review.findings[i],e=expected[i];
    if(f.filename!==e.filename||f.reviewFocus!==e.reviewFocus)failures.push('finding '+i+' file binding mismatch');
    if(!['unreviewed','reviewed_no_issue','reviewed_attention','reviewed_blocker'].includes(f.state))failures.push('finding '+i+' invalid state');
    if(f.notes!==null&&!clean(f.notes,1000))failures.push('finding '+i+' invalid notes');
  }
  if(!['in_progress','evidence_accepted'].includes(review.state))failures.push('invalid review state');
  if(review.state==='evidence_accepted'){
    const a=review.humanAcceptance;
    if(a?.status!=='accepted'||!ID.test(a.reviewerId||'')||!ISO.test(a.reviewedAt||'')||!clean(a.summary,500))failures.push('invalid human acceptance');
    if(review.findings.some(f=>f.state==='unreviewed'||f.state==='reviewed_blocker'))failures.push('accepted review has unresolved/blocker finding');
  }
  return failures;
}
export function applyAction({review,pack,action}){
  const currentFailures=validateReview({review,pack});if(currentFailures.length)fail(currentFailures.join('; '));
  if(review.state!=='in_progress')fail('accepted review is immutable');
  const next=clone(review);
  if(action.action==='record_finding'){
    const allowed=new Set(['action','filename','state','notes']);
    for(const k of Object.keys(action))if(!allowed.has(k))fail('unknown finding action field '+k);
    if(!['reviewed_no_issue','reviewed_attention','reviewed_blocker'].includes(action.state))fail('invalid finding state');
    const finding=next.findings.find(f=>f.filename===action.filename);if(!finding)fail('changed file not found in evidence pack');
    if(action.notes!==undefined&&action.notes!==null&&!clean(action.notes,1000))fail('invalid or secret-like finding notes');
    finding.state=action.state;finding.notes=action.notes??null;
  }else if(action.action==='accept_evidence'){
    const allowed=new Set(['action','confirmation','reviewerId','reviewedAt','summary']);
    for(const k of Object.keys(action))if(!allowed.has(k))fail('unknown acceptance field '+k);
    if(action.confirmation!=='ACCEPT EVIDENCE')fail('literal ACCEPT EVIDENCE confirmation required');
    if(!ID.test(action.reviewerId||''))fail('invalid reviewerId');
    if(!ISO.test(action.reviewedAt||'')||!Number.isFinite(Date.parse(action.reviewedAt)))fail('invalid reviewedAt');
    if(!clean(action.summary,300))fail('invalid or secret-like acceptance summary');
    if(next.findings.some(f=>f.state==='unreviewed'))fail('every changed file requires a human finding before evidence acceptance');
    if(next.findings.some(f=>f.state==='reviewed_blocker'))fail('blocker findings prevent evidence acceptance');
    next.state='evidence_accepted';
    next.humanAcceptance={status:'accepted',reviewerId:action.reviewerId,reviewedAt:action.reviewedAt,summary:action.summary};
  }else fail('unknown action');
  const failures=validateReview({review:next,pack});if(failures.length)fail(failures.join('; '));
  return next;
}
export function acceptedEvidence({review,pack}){
  const failures=validateReview({review,pack});if(failures.length)fail(failures.join('; '));
  if(review.state!=='evidence_accepted')fail('human evidence has not been accepted');
  const attention=review.findings.filter(f=>f.state==='reviewed_attention').length;
  const a=review.humanAcceptance;
  return {
    source:'github',kind:'security_diff_review',
    reference:pack.repository+'@'+pack.reviewedCommitSha+'...'+pack.observedCommitSha,
    checkedAt:a.reviewedAt,
    summary:'Human diff review accepted by '+a.reviewerId+': '+a.summary+' Reviewed '+review.findings.length+' changed files; '+attention+' attention note'+(attention===1?'':'s')+'; no blocker findings.'
  };
}
function readAction(path){const full=isAbsolute(path)?path:resolve(process.cwd(),path),s=statSync(full);if(!s.isFile()||s.size>32*1024)fail('action must be JSON no larger than 32 KiB');try{return JSON.parse(readFileSync(full,'utf8'))}catch{fail('action is not valid JSON')}}
function packFor(appId){const r=buildLiveEvidencePacks();const p=r.items.find(x=>x.appId===appId);if(!p)fail('no current draftable evidence pack for '+appId);return p}
function loadReview(pack){const p=reviewPath(pack);return existsSync(p)?JSON.parse(readFileSync(p,'utf8')):createReview(pack)}
function show(review,pack){
  const pending=review.findings.filter(f=>f.state==='unreviewed').length,blockers=review.findings.filter(f=>f.state==='reviewed_blocker').length;
  console.log('SHINE DEFENCE HUMAN DIFF REVIEW');
  console.log('app: '+pack.appId);console.log('compare: '+pack.reviewedCommitSha+'...'+pack.observedCommitSha);
  console.log('commits: '+pack.compare.totalCommits+'; files: '+pack.compare.changedFiles+'; +'+pack.compare.additions+'/-'+pack.compare.deletions);
  console.log('state: '+review.state+'; unreviewed: '+pending+'; blockers: '+blockers);
  for(const f of review.findings)console.log('  ['+f.reviewFocus+'] '+f.filename+' -> '+f.state+(f.notes?' — '+f.notes:''));
}
function selfTest(){
  const pack={appId:'app',repository:'owner/app',reviewedCommitSha:'a'.repeat(40),observedCommitSha:'b'.repeat(40),deploymentObservationId:'obs',compare:{totalCommits:2,changedFiles:2,additions:10,deletions:1},reviewFocus:{files:[{filename:'tests/a.test.ts',reviewFocus:'tests'},{filename:'app/api/auth/route.ts',reviewFocus:'security_or_auth'}]}};
  let r=createReview(pack);
  if(r.findings[0].reviewFocus!=='security_or_auth')fail('sensitive file not surfaced first');
  r=applyAction({review:r,pack,action:{action:'record_finding',filename:'app/api/auth/route.ts',state:'reviewed_attention',notes:'Session boundary reviewed.'}});
  r=applyAction({review:r,pack,action:{action:'record_finding',filename:'tests/a.test.ts',state:'reviewed_no_issue',notes:'Coverage reviewed.'}});
  r=applyAction({review:r,pack,action:{action:'accept_evidence',confirmation:'ACCEPT EVIDENCE',reviewerId:'reviewer-1',reviewedAt:'2026-09-27T06:30:00.000Z',summary:'Reviewed changed files and supporting tests.'}});
  const e=acceptedEvidence({review:r,pack});if(e.kind!=='security_diff_review'||!e.summary.includes('reviewer-1'))fail('accepted evidence mismatch');
  let blocked=false;const b=createReview(pack);try{applyAction({review:b,pack,action:{action:'accept_evidence',confirmation:'ACCEPT EVIDENCE',reviewerId:'reviewer-1',reviewedAt:'2026-09-27T06:30:00.000Z',summary:'Too early.'}})}catch{blocked=true}if(!blocked)fail('unreviewed files accepted');
  console.log('SHINE DEFENCE HUMAN DIFF REVIEW SELF-TEST: PASS sensitive-first ordering, durable findings, explicit acceptance and incomplete-review fail-closed');
}
function parse(argv){const r={apply:false};for(let i=0;i<argv.length;i++){const a=argv[i];if(a==='--self-test'){r.selfTest=true;continue}if(a==='--apply'){r.apply=true;continue}if(a==='--app'){r.app=argv[++i];continue}if(a==='--action'){r.action=argv[++i];continue}fail('unknown argument '+a)}return r}
function main(){
  const a=parse(process.argv.slice(2));if(a.selfTest)return selfTest();if(!a.app)fail('--app is required');
  const pack=packFor(a.app),review=loadReview(pack);
  if(!a.action){show(review,pack);return}
  const next=applyAction({review,pack,action:readAction(a.action)});
  show(next,pack);
  if(!a.apply){console.log('DRY RUN: no files changed.');return}
  mkdirSync(reviewDir,{recursive:true});mkdirSync(evidenceDir,{recursive:true});
  atomicWrite(reviewPath(pack),Buffer.from(json(next)));
  if(next.state==='evidence_accepted')atomicWrite(evidencePath(pack),Buffer.from(json(acceptedEvidence({review:next,pack}))));
  console.log('SHINE DEFENCE HUMAN DIFF REVIEW: APPLIED '+next.reviewId);
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)main();
