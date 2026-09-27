#!/usr/bin/env node
import {existsSync,readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildLiveEvidencePacks} from './generate-review-evidence-pack-v1.mjs';
import {acceptedEvidence,validateReview,reviewKey} from './human-diff-review-v1.mjs';
import {buildIntakePlan,materializeDraft} from './plan-review-intake-v1.mjs';
import {loadLiveDeploymentReport} from './deployment-observations-v1.mjs';
import {buildCandidateIntake} from './intake-review-v1.mjs';

export const SHINE_DEFENCE_CANDIDATE_INTAKE_READINESS_VERSION='1.0.0';
const root=fileURLToPath(new URL('../../../',import.meta.url));
const P={ledger:'security/shine-defence/ecosystem-profile-ledger-v1.json',candidates:'security/shine-defence/review-candidates-v1.json',registry:'security/shine-defence/canonical-registry-v1.json',reviews:'security/shine-defence/human-diff-reviews',evidence:'security/shine-defence/review-evidence-records'};
const readJson=p=>JSON.parse(readFileSync(join(root,p),'utf8'));
const fail=m=>{throw new Error(m)};
const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);

export function buildReadyItem({planItem,pack,review,evidence,queue,ledger,registry}){
  if(planItem?.state!=='needs_review_evidence')fail('current planner item is not draftable');
  if(pack.appId!==planItem.appId||pack.observedCommitSha!==planItem.intakeDraft.releaseCommitSha||pack.deploymentObservationId!==planItem.deploymentObservationId)fail('evidence pack does not match current planner identity');
  const failures=validateReview({review,pack});if(failures.length)fail('human review invalid: '+failures.join('; '));
  if(review.state!=='evidence_accepted')fail('human review evidence is not accepted');
  const expected=acceptedEvidence({review,pack});
  if(!same(evidence,expected))fail('accepted evidence record does not exactly match human review');
  if(Date.parse(evidence.checkedAt)<Date.parse(planItem.deploymentObservedAt))fail('accepted evidence predates deployment observation');

  const payload=materializeDraft({planItem,candidateObservedAt:evidence.checkedAt,evidence:[evidence],queue,ledger,registry});
  const validated=buildCandidateIntake({input:payload,queue,ledger,registry});
  return {
    appId:planItem.appId,repository:planItem.repository,state:'candidate_intake_ready',
    reviewId:review.reviewId,evidenceRecordId:reviewKey(pack),
    candidateId:validated.candidate.candidateId,
    intakePayload:payload,
    nextAction:{
      id:'apply_candidate_intake',
      helper:'security/shine-defence/integration-kit/intake-review-v1.mjs',
      args:['--input','<validated-candidate-intake.json>','--apply'],
      description:'Persist this validated payload to a file and run the existing guarded candidate-intake apply action.'
    }
  };
}

export function buildReadinessReport({plan,packs,queue,ledger,registry,readArtifact}){
  const packMap=new Map((packs.items||[]).map(p=>[p.appId,p])),items=[];
  for(const planItem of plan.items||[]){
    if(planItem.state!=='needs_review_evidence')continue;
    const pack=packMap.get(planItem.appId);if(!pack)continue;
    const id=reviewKey(pack),review=readArtifact('review',id),evidence=readArtifact('evidence',id);
    if(!review||!evidence)continue;
    try{items.push(buildReadyItem({planItem,pack,review,evidence,queue,ledger,registry}))}
    catch(error){items.push({appId:planItem.appId,repository:planItem.repository,state:'accepted_evidence_invalid',reason:error.message})}
  }
  items.sort((a,b)=>a.appId.localeCompare(b.appId));
  return {report:'shine-defence/candidate-intake-readiness-v1',version:'1.0.0',ready:items.filter(i=>i.state==='candidate_intake_ready').length,invalid:items.filter(i=>i.state==='accepted_evidence_invalid').length,items};
}

export function loadLiveReadiness(){
  const ledger=readJson(P.ledger),queue=readJson(P.candidates),registry=readJson(P.registry);
  const plan=buildIntakePlan({deploymentReport:loadLiveDeploymentReport(),ledger,candidates:queue});
  const packs=buildLiveEvidencePacks();
  return buildReadinessReport({plan,packs,queue,ledger,registry,readArtifact:(kind,id)=>{
    const path=join(root,kind==='review'?P.reviews:P.evidence,id+'.json');
    return existsSync(path)?JSON.parse(readFileSync(path,'utf8')):null;
  }});
}

function selfTest(){
  const ledger={ledger:'shine-defence/ecosystem-profile-ledger-v1',version:'1.1.0',apps:[{id:'app',repo:'owner/app',path:'security/profile.json',profileBlobSha:'b'.repeat(40),profileVersion:'1.0.0',policies:['baseline'],reviewCommitSha:'a'.repeat(40)}]};
  const queue={ledger:'shine-defence/review-candidates-v1',version:'1.0.0',candidates:[]};
  const registry={registry:'shine-defence/canonical-registry-v1',version:'1.0.0',entries:[{id:'baseline'}]};
  const planItem={appId:'app',repository:'owner/app',state:'needs_review_evidence',deploymentObservationId:'obs-1',deploymentObservedAt:'2026-09-27T01:00:00.000Z',intakeDraft:{appId:'app',repository:'owner/app',releaseCommitSha:'c'.repeat(40),profilePath:'security/profile.json',profileBlobSha:'b'.repeat(40),profileVersion:'1.0.0',policies:['baseline'],candidateObservedAt:null,evidence:[]}};
  const pack={appId:'app',repository:'owner/app',reviewedCommitSha:'a'.repeat(40),observedCommitSha:'c'.repeat(40),deploymentObservationId:'obs-1',compare:{totalCommits:1,changedFiles:1,additions:1,deletions:0},reviewFocus:{files:[{filename:'app/api/route.ts',reviewFocus:'api_or_server'}]}};
  const review={artifact:'shine-defence/human-diff-review-v1',version:'1.0.0',reviewId:reviewKey(pack),appId:'app',repository:'owner/app',reviewedCommitSha:pack.reviewedCommitSha,observedCommitSha:pack.observedCommitSha,deploymentObservationId:'obs-1',state:'evidence_accepted',packSummary:pack.compare,findings:[{filename:'app/api/route.ts',reviewFocus:'api_or_server',state:'reviewed_no_issue',notes:'Reviewed.'}],humanAcceptance:{status:'accepted',reviewerId:'reviewer-1',reviewedAt:'2026-09-27T01:10:00.000Z',summary:'Reviewed the changed API path.'}};
  const evidence=acceptedEvidence({review,pack});
  const ready=buildReadyItem({planItem,pack,review,evidence,queue,ledger,registry});
  if(ready.state!=='candidate_intake_ready'||ready.candidateId!=='app-'+('c'.repeat(12)))fail('ready item mismatch');
  let blocked=false;try{buildReadyItem({planItem,pack,review,evidence:{...evidence,summary:'tampered'},queue,ledger,registry})}catch{blocked=true}if(!blocked)fail('tampered evidence accepted');
  blocked=false;try{buildReadyItem({planItem,pack,review:{...review,state:'in_progress',humanAcceptance:{status:'pending'}},evidence,queue,ledger,registry})}catch{blocked=true}if(!blocked)fail('unaccepted review became ready');
  console.log('SHINE DEFENCE CANDIDATE INTAKE READINESS SELF-TEST: PASS accepted-evidence binding, canonical intake validation and fail-closed tamper/unaccepted cases');
}
function main(){if(process.argv.includes('--self-test'))return selfTest();console.log(JSON.stringify(loadLiveReadiness(),null,2))}
main();
