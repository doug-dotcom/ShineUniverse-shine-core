#!/usr/bin/env node
import {readdirSync,readFileSync} from 'node:fs';

const root=new URL('../../../',import.meta.url);
const queue=JSON.parse(readFileSync(new URL('security/shine-defence/review-candidates-v1.json',root),'utf8'));
const decisions=JSON.parse(readFileSync(new URL('security/shine-defence/review-decisions-v1.json',root),'utf8'));
const ledger=JSON.parse(readFileSync(new URL('security/shine-defence/ecosystem-profile-ledger-v1.json',root),'utf8'));
const receiptsDir=new URL('security/shine-defence/receipts/',root);

const sameArray=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const sameIdentity=(candidate,app)=>
  candidate.repository===app.repo&&
  candidate.profilePath===app.path&&
  candidate.releaseCommitSha===app.reviewCommitSha&&
  candidate.profileBlobSha===app.profileBlobSha&&
  candidate.profileVersion===app.profileVersion&&
  sameArray(candidate.policies,app.policies);

const receiptMatches=(receipt,candidate,app)=>
  receipt?.appId===candidate.appId&&
  receipt.repository===app.repo&&
  receipt.reviewCommitSha===candidate.releaseCommitSha&&
  receipt.profilePath===candidate.profilePath&&
  receipt.profileBlobSha===candidate.profileBlobSha&&
  receipt.profileVersion===candidate.profileVersion&&
  sameArray(receipt.policies,candidate.policies);

function verifyPromotionState({queue,decisions,ledger,receipts}){
  const failures=[];
  if(queue.ledger!=='shine-defence/review-candidates-v1'||!Array.isArray(queue.candidates))failures.push('unsupported review candidate queue');
  if(decisions.ledger!=='shine-defence/review-decisions-v1'||!Array.isArray(decisions.decisions))failures.push('unsupported review decision ledger');
  if(ledger.ledger!=='shine-defence/ecosystem-profile-ledger-v1'||!Array.isArray(ledger.apps))failures.push('unsupported ecosystem reviewed ledger');
  if(failures.length)return failures;

  const apps=new Map(ledger.apps.map(app=>[app.id,app]));
  const managed=new Set(queue.candidates.map(candidate=>candidate.appId));

  for(const appId of managed){
    const app=apps.get(appId);
    if(!app){failures.push(appId+': promotion-managed app missing from reviewed ledger');continue}
    const candidates=queue.candidates.filter(candidate=>candidate.appId===appId);
    const matchingCurrent=candidates.filter(candidate=>sameIdentity(candidate,app));
    const acceptedCurrent=matchingCurrent.filter(candidate=>candidate.status==='accepted');

    if(matchingCurrent.length!==1){
      failures.push(appId+': current reviewed identity must match exactly one review candidate; found '+matchingCurrent.length);
      continue;
    }
    if(acceptedCurrent.length!==1){
      failures.push(appId+': current reviewed identity is not exactly one accepted candidate');
      continue;
    }

    const current=acceptedCurrent[0];
    const acceptedDecision=decisions.decisions.filter(decision=>
      decision.candidateId===current.candidateId&&
      decision.appId===appId&&
      decision.outcome==='accepted'
    );
    if(acceptedDecision.length!==1)failures.push(appId+': current accepted candidate must have exactly one accepted decision; found '+acceptedDecision.length);

    const appReceipts=receipts.filter(receipt=>receipt.appId===appId);
    if(appReceipts.length!==1){
      failures.push(appId+': promotion-managed app must have exactly one current receipt; found '+appReceipts.length);
    }else if(!receiptMatches(appReceipts[0],current,app)){
      failures.push(appId+': current receipt does not match accepted candidate and reviewed ledger');
    }

    for(const historical of candidates.filter(candidate=>candidate.status==='accepted')){
      const review=decisions.decisions.filter(decision=>
        decision.candidateId===historical.candidateId&&
        decision.appId===appId&&
        decision.outcome==='accepted'
      );
      if(review.length!==1)failures.push(historical.candidateId+': historical accepted candidate must retain exactly one accepted decision');
    }
  }

  return failures;
}

function loadReceipts(){
  const receipts=[];
  for(const file of readdirSync(receiptsDir).filter(name=>name.endsWith('.json'))){
    try{receipts.push(JSON.parse(readFileSync(new URL(file,receiptsDir),'utf8')))}
    catch{receipts.push({appId:'<invalid:'+file+'>'})}
  }
  return receipts;
}

function selfTest(){
  const a='a'.repeat(40),b='b'.repeat(40),c='c'.repeat(40),p='d'.repeat(40);
  const oldCandidate={candidateId:'app-old',appId:'app',repository:'owner/app',profilePath:'security/profile.json',releaseCommitSha:a,profileBlobSha:p,profileVersion:'1.0.0',policies:['baseline'],status:'accepted'};
  const currentCandidate={...oldCandidate,candidateId:'app-current',releaseCommitSha:b,status:'accepted'};
  const base={
    queue:{ledger:'shine-defence/review-candidates-v1',candidates:[oldCandidate,currentCandidate]},
    decisions:{ledger:'shine-defence/review-decisions-v1',decisions:[
      {candidateId:'app-old',appId:'app',outcome:'accepted'},
      {candidateId:'app-current',appId:'app',outcome:'accepted'}
    ]},
    ledger:{ledger:'shine-defence/ecosystem-profile-ledger-v1',apps:[
      {id:'app',repo:'owner/app',path:'security/profile.json',reviewCommitSha:b,profileBlobSha:p,profileVersion:'1.0.0',policies:['baseline']},
      {id:'legacy',repo:'owner/legacy',path:'security/profile.json',reviewCommitSha:c,profileBlobSha:p,profileVersion:'1.0.0',policies:['baseline']}
    ]},
    receipts:[{appId:'app',repository:'owner/app',reviewCommitSha:b,profilePath:'security/profile.json',profileBlobSha:p,profileVersion:'1.0.0',policies:['baseline']}]
  };
  const clone=value=>JSON.parse(JSON.stringify(value));
  const mustPass=(name,state)=>{const f=verifyPromotionState(state);if(f.length)throw new Error(name+' should pass: '+f.join('; '))};
  const mustFail=(name,state)=>{
    const f=verifyPromotionState(state);
    if(!f.length)throw new Error(name+' should fail');
  };

  mustPass('healthy successive acceptance',clone(base));

  const missingDecision=clone(base);
  missingDecision.decisions.decisions=missingDecision.decisions.decisions.filter(d=>d.candidateId!=='app-current');
  mustFail('missing current decision',missingDecision);

  const staleReceipt=clone(base);
  staleReceipt.receipts[0].reviewCommitSha=a;
  mustFail('stale receipt',staleReceipt);

  const staleLedger=clone(base);
  staleLedger.ledger.apps[0].reviewCommitSha=c;
  mustFail('ledger without matching accepted candidate',staleLedger);

  const pendingCurrent=clone(base);
  pendingCurrent.queue.candidates[1].status='pending_review';
  mustFail('current candidate still pending',pendingCurrent);

  const duplicateCurrent=clone(base);
  duplicateCurrent.queue.candidates.push({...duplicateCurrent.queue.candidates[1],candidateId:'app-current-duplicate'});
  duplicateCurrent.decisions.decisions.push({candidateId:'app-current-duplicate',appId:'app',outcome:'accepted'});
  mustFail('duplicate accepted current identity',duplicateCurrent);

  const missingReceipt=clone(base);
  missingReceipt.receipts=[];
  mustFail('missing current receipt',missingReceipt);

  console.log('SHINE DEFENCE REVIEW PROMOTION SELF-TEST: PASS 1 healthy + 6 fail-closed cases');
}

if(process.argv.includes('--self-test')){
  selfTest();
}else{
  const failures=verifyPromotionState({queue,decisions,ledger,receipts:loadReceipts()});
  if(failures.length){for(const failure of failures)console.error('FAIL '+failure);process.exit(1)}
  const managed=new Set(queue.candidates.map(candidate=>candidate.appId));
  console.log('SHINE DEFENCE REVIEW PROMOTION: PASS '+managed.size+' promotion-managed apps');
}
