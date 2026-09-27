#!/usr/bin/env node
import {createHash} from 'node:crypto';
import {existsSync,readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('../../../',import.meta.url));
const queuePath=join(root,'security/shine-defence/review-candidates-v1.json');
const decisionsPath=join(root,'security/shine-defence/review-decisions-v1.json');
const checklistDir=join(root,'security/shine-defence/review-checklists');

const gitBlobSha=bytes=>createHash('sha1').update(Buffer.from('blob '+bytes.length+'\0')).update(bytes).digest('hex');

export function verifyRejectedState({queue,decisions,checklists}){
  const failures=[];
  const decisionMap=new Map((decisions.decisions||[]).map(decision=>[decision.candidateId,decision]));
  let checked=0,legacy=0;

  for(const candidate of queue.candidates||[]){
    if(candidate.status!=='dismissed')continue;
    const record=checklists.get(candidate.candidateId);
    if(!record){legacy++;continue}

    checked++;
    const decision=decisionMap.get(candidate.candidateId);
    if(!decision){failures.push(candidate.candidateId+': dismissed candidate missing decision');continue}
    const checklist=record.checklist;
    const auth=checklist?.humanAuthorization;

    if(auth?.status!=='rejected')failures.push(candidate.candidateId+': dismissed checklist is not human-rejected');
    if(decision.outcome!=='dismissed')failures.push(candidate.candidateId+': decision outcome is not dismissed');
    if(decision.decisionId!==candidate.candidateId+'-dismissed')failures.push(candidate.candidateId+': decision id mismatch');
    if(decision.appId!==candidate.appId)failures.push(candidate.candidateId+': decision app id mismatch');

    if(auth?.status==='rejected'){
      if(candidate.decisionReason!==auth.summary)failures.push(candidate.candidateId+': decisionReason does not match human rejection summary');
      if(decision.authority!==auth.reviewerId)failures.push(candidate.candidateId+': decision authority does not match human reviewer');
      if(decision.decidedAt!==auth.reviewedAt)failures.push(candidate.candidateId+': decision timestamp does not match human rejection');
      if(decision.summary!==auth.summary)failures.push(candidate.candidateId+': decision summary does not match human rejection');
    }

    if(decision.reviewChecklistBlobSha!==gitBlobSha(record.bytes))failures.push(candidate.candidateId+': rejected checklist blob fingerprint mismatch');
    if(decision.reviewRegistryBlobSha!==checklist.registryBlobSha)failures.push(candidate.candidateId+': rejected registry fingerprint mismatch');
  }

  return {failures,checked,legacy};
}

function loadLive(){
  const queue=JSON.parse(readFileSync(queuePath,'utf8'));
  const decisions=JSON.parse(readFileSync(decisionsPath,'utf8'));
  const checklists=new Map();
  for(const candidate of queue.candidates||[]){
    const path=join(checklistDir,candidate.candidateId+'.json');
    if(!existsSync(path))continue;
    try{
      const bytes=readFileSync(path);
      checklists.set(candidate.candidateId,{bytes,checklist:JSON.parse(bytes.toString('utf8'))});
    }catch{
      checklists.set(candidate.candidateId,{bytes:Buffer.from(''),checklist:null});
    }
  }
  return {queue,decisions,checklists};
}

function selfTest(){
  const bytes=Buffer.from(JSON.stringify({
    checklist:'shine-defence/review-checklist-v1',
    candidateId:'app-release',
    registryBlobSha:'a'.repeat(40),
    humanAuthorization:{
      status:'rejected',
      reviewerId:'reviewer-1',
      reviewedAt:'2026-09-27T01:00:00.000Z',
      summary:'Rejected because a required control is not satisfied.'
    }
  },null,2)+'\n');
  const checklist=JSON.parse(bytes.toString('utf8'));
  const candidate={
    candidateId:'app-release',appId:'app',status:'dismissed',
    decisionReason:checklist.humanAuthorization.summary
  };
  const decision={
    decisionId:'app-release-dismissed',candidateId:'app-release',appId:'app',outcome:'dismissed',
    authority:'reviewer-1',decidedAt:'2026-09-27T01:00:00.000Z',
    summary:checklist.humanAuthorization.summary,
    reviewChecklistBlobSha:gitBlobSha(bytes),
    reviewRegistryBlobSha:checklist.registryBlobSha
  };
  const base={
    queue:{candidates:[candidate]},
    decisions:{decisions:[decision]},
    checklists:new Map([['app-release',{bytes,checklist}]])
  };

  const healthy=verifyRejectedState(base);
  if(healthy.failures.length||healthy.checked!==1)throw new Error('healthy rejection should pass: '+healthy.failures.join('; '));

  const clone=value=>JSON.parse(JSON.stringify(value));
  const expectFail=(name,mutate)=>{
    const q=clone(base.queue),d=clone(base.decisions);
    const b=Buffer.from(bytes),c=clone(checklist);
    mutate(q,d,c);
    const result=verifyRejectedState({queue:q,decisions:d,checklists:new Map([['app-release',{bytes:b,checklist:c}]])});
    if(!result.failures.length)throw new Error(name+' should fail');
  };
  expectFail('candidate reason drift',(q)=>{q.candidates[0].decisionReason='Different'});
  expectFail('authority drift',(q,d)=>{d.decisions[0].authority='other-reviewer'});
  expectFail('timestamp drift',(q,d)=>{d.decisions[0].decidedAt='2026-09-27T02:00:00.000Z'});
  expectFail('summary drift',(q,d)=>{d.decisions[0].summary='Different'});
  expectFail('registry fingerprint drift',(q,d)=>{d.decisions[0].reviewRegistryBlobSha='b'.repeat(40)});

  const legacy=verifyRejectedState({
    queue:{candidates:[{candidateId:'legacy',appId:'app',status:'dismissed'}]},
    decisions:{decisions:[{candidateId:'legacy',appId:'app',outcome:'dismissed'}]},
    checklists:new Map()
  });
  if(legacy.failures.length||legacy.legacy!==1)throw new Error('legacy dismissal without checklist should be grandfathered');

  console.log('SHINE DEFENCE REVIEW REJECTIONS SELF-TEST: PASS 1 healthy + 5 fail-closed cases + legacy grandfathering');
}

if(process.argv.includes('--self-test')){
  selfTest();
}else{
  const result=verifyRejectedState(loadLive());
  if(result.failures.length){
    for(const failure of result.failures)console.error('FAIL '+failure);
    process.exit(1);
  }
  console.log('SHINE DEFENCE REVIEW REJECTIONS: PASS '+result.checked+' checklist-bound dismissal'+(result.checked===1?'':'s')+'; '+result.legacy+' legacy dismissal'+(result.legacy===1?'':'s'));
}
