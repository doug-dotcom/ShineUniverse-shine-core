#!/usr/bin/env node
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {
  SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY
} from '../../../foundation/runtime/_shared/shine-defence-release-attestation-authority-v1.mjs';

export const SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY_LINEAGE_VERIFIER_VERSION='1.2.0';

const SHA40=/^[a-f0-9]{40}$/;
const PROMOTION_RECEIPT_PATH=/^security\/shine-defence\/release-attestation-authority-promotions\/[a-z0-9][a-z0-9._-]*\.json$/;
const ROLLBACK_RECEIPT_PATH=/^security\/shine-defence\/release-attestation-authority-rollbacks\/[a-z0-9][a-z0-9._-]*\.json$/;

const same=(a,b)=>String(a??'')===String(b??'');
const expectedRef=(workflow,sha)=>workflow.repository+'/'+workflow.path+'@'+sha;
const gitBlobSha=bytes=>createHash('sha1').update(Buffer.from('blob '+bytes.length+'\0')).update(bytes).digest('hex');
const clean=(value,max)=>typeof value==='string'&&value.length>0&&value.length<=max&&!/[\u0000-\u001f\u007f]/.test(value);

function verifyReceiptFingerprint({reference,resolved,sequence,label}){
  const failures=[];
  if(!SHA40.test(String(reference?.blobSha||''))) failures.push('entry '+sequence+' '+label+' receipt blob SHA invalid');
  if(!same(reference?.blobSha,resolved?.blobSha)) failures.push('entry '+sequence+' '+label+' receipt blob fingerprint mismatch');
  return failures;
}

function verifyPromotionReceipt({entry,previous,activated,promotionPolicy,reference,resolved,sequence}){
  const failures=[];
  const receipt=resolved?.receipt;
  if(!receipt||typeof receipt!=='object'||Array.isArray(receipt)){
    failures.push('entry '+sequence+' promotion receipt is unreadable');
    return failures;
  }

  const spec=promotionPolicy?.receipt||{};
  if(receipt.contract!==spec.contract) failures.push('entry '+sequence+' promotion receipt contract mismatch');
  if(receipt.version!==spec.version) failures.push('entry '+sequence+' promotion receipt version mismatch');
  if(receipt.status!==spec.status) failures.push('entry '+sequence+' promotion receipt is not approved');

  if(!clean(receipt.promotionId,160)) failures.push('entry '+sequence+' promotion id invalid');
  else{
    const expectedPath=spec.directory+'/'+receipt.promotionId+'.json';
    if(reference.path!==expectedPath) failures.push('entry '+sequence+' promotion receipt path does not match promotion id');
  }

  if(!same(receipt.predecessorAuthoritySha,previous?.authoritySha)) failures.push('entry '+sequence+' promotion predecessor mismatch');
  if(!same(receipt.successorAuthoritySha,entry.authoritySha)) failures.push('entry '+sequence+' promotion successor mismatch');
  if(!same(receipt.successorWorkflowBlobSha,entry.workflowBlobSha)) failures.push('entry '+sequence+' promotion workflow blob mismatch');

  if(!clean(receipt.reviewerId,200)||receipt.reviewerId==='shine-defence-core') failures.push('entry '+sequence+' promotion reviewer id invalid');
  if(!clean(receipt.summary,2000)||receipt.summary.length<10) failures.push('entry '+sequence+' promotion summary invalid');

  const approved=Date.parse(String(receipt.approvedAt||''));
  if(Number.isNaN(approved)) failures.push('entry '+sequence+' promotion approvedAt invalid');
  else if(!Number.isNaN(activated)&&approved>activated) failures.push('entry '+sequence+' promotion approval occurs after activation');

  const controls=receipt.reviewControls;
  if(!controls||typeof controls!=='object'||Array.isArray(controls)) failures.push('entry '+sequence+' promotion review controls missing');
  else for(const control of (promotionPolicy?.requiredReviewControls||[])){
    if(controls[control]!==true) failures.push('entry '+sequence+' promotion control '+control+' is not explicitly true');
  }

  failures.push(...verifyReceiptFingerprint({reference,resolved,sequence,label:'promotion'}));
  return failures;
}

function verifyRollbackReceipt({entry,previous,original,activated,rollbackPolicy,reference,resolved,sequence}){
  const failures=[];
  const receipt=resolved?.receipt;
  if(!receipt||typeof receipt!=='object'||Array.isArray(receipt)){
    failures.push('entry '+sequence+' rollback receipt is unreadable');
    return failures;
  }

  const spec=rollbackPolicy?.receipt||{};
  if(receipt.contract!==spec.contract) failures.push('entry '+sequence+' rollback receipt contract mismatch');
  if(receipt.version!==spec.version) failures.push('entry '+sequence+' rollback receipt version mismatch');
  if(receipt.status!==spec.status) failures.push('entry '+sequence+' rollback receipt is not approved');

  if(!clean(receipt.rollbackId,160)) failures.push('entry '+sequence+' rollback id invalid');
  else{
    const expectedPath=spec.directory+'/'+receipt.rollbackId+'.json';
    if(reference.path!==expectedPath) failures.push('entry '+sequence+' rollback receipt path does not match rollback id');
  }

  if(!same(receipt.failedAuthoritySha,previous?.authoritySha)) failures.push('entry '+sequence+' rollback failed-authority mismatch');
  if(!same(receipt.restoreAuthoritySha,entry.authoritySha)) failures.push('entry '+sequence+' rollback restore-authority mismatch');
  if(!same(receipt.restoreWorkflowBlobSha,entry.workflowBlobSha)) failures.push('entry '+sequence+' rollback workflow blob mismatch');
  if(receipt.restoreFromSequence!==original?.sequence) failures.push('entry '+sequence+' rollback source sequence mismatch');

  if(!clean(receipt.reviewerId,200)||receipt.reviewerId==='shine-defence-core') failures.push('entry '+sequence+' rollback reviewer id invalid');
  if(!clean(receipt.summary,2000)||receipt.summary.length<10) failures.push('entry '+sequence+' rollback summary invalid');

  const approved=Date.parse(String(receipt.approvedAt||''));
  if(Number.isNaN(approved)) failures.push('entry '+sequence+' rollback approvedAt invalid');
  else if(!Number.isNaN(activated)&&approved>activated) failures.push('entry '+sequence+' rollback approval occurs after activation');

  const controls=receipt.reviewControls;
  if(!controls||typeof controls!=='object'||Array.isArray(controls)) failures.push('entry '+sequence+' rollback review controls missing');
  else for(const control of (rollbackPolicy?.requiredReviewControls||[])){
    if(controls[control]!==true) failures.push('entry '+sequence+' rollback control '+control+' is not explicitly true');
  }

  failures.push(...verifyReceiptFingerprint({reference,resolved,sequence,label:'rollback'}));
  return failures;
}

export function verifyAuthorityLineage({
  lineage,
  authority,
  promotionPolicy,
  rollbackPolicy,
  runtime=SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY,
  resolveWorkflowBlob,
  resolvePromotionReceipt,
  resolveRollbackReceipt
}={}){
  const failures=[];
  if(!lineage||typeof lineage!=='object')return ['lineage document is required'];
  if(!authority||typeof authority!=='object')return ['authority contract is required'];
  if(!promotionPolicy||typeof promotionPolicy!=='object')return ['promotion policy is required'];
  if(!rollbackPolicy||typeof rollbackPolicy!=='object')return ['rollback policy is required'];
  if(!runtime||typeof runtime!=='object')return ['runtime authority binding is required'];

  if(lineage.contract!=='shine-defence/release-attestation-authority-lineage-v1') failures.push('unsupported lineage contract');
  if(lineage.version!=='1.2.0') failures.push('unsupported lineage version');
  if(promotionPolicy.contract!=='shine-defence/release-attestation-authority-promotion-v1'||promotionPolicy.version!=='1.0.0'){
    failures.push('unsupported promotion policy');
  }
  if(rollbackPolicy.contract!=='shine-defence/release-attestation-authority-rollback-v1'||rollbackPolicy.version!=='1.0.0'){
    failures.push('unsupported rollback policy');
  }

  const workflow=lineage.workflow||{};
  const canonicalWorkflow=authority.reusableWorkflow||{};
  for(const key of ['repository','repositoryId','path']){
    if(!same(workflow[key],canonicalWorkflow[key])) failures.push('workflow '+key+' diverges from authority contract');
  }

  const promotionGate=lineage.promotionGate||{};
  if(!same(promotionGate.contractPath,authority.promotionGate?.contractPath)) failures.push('lineage promotion contract path diverges from authority contract');
  if(!same(promotionGate.receiptDirectory,authority.promotionGate?.receiptDirectory)) failures.push('lineage promotion receipt directory diverges from authority contract');
  if(!same(promotionGate.contractPath,'security/shine-defence/release-attestation-authority-promotion-v1.json')) failures.push('lineage promotion contract path invalid');
  if(!same(promotionGate.receiptDirectory,promotionPolicy.receipt?.directory)) failures.push('lineage promotion receipt directory diverges from promotion policy');
  if(promotionGate.bootstrapSequence!==1) failures.push('lineage bootstrap sequence must be 1');

  const rollbackGate=lineage.rollbackGate||{};
  if(!same(rollbackGate.contractPath,authority.rollbackGate?.contractPath)) failures.push('lineage rollback contract path diverges from authority contract');
  if(!same(rollbackGate.receiptDirectory,authority.rollbackGate?.receiptDirectory)) failures.push('lineage rollback receipt directory diverges from authority contract');
  if(!same(rollbackGate.contractPath,'security/shine-defence/release-attestation-authority-rollback-v1.json')) failures.push('lineage rollback contract path invalid');
  if(!same(rollbackGate.receiptDirectory,rollbackPolicy.receipt?.directory)) failures.push('lineage rollback receipt directory diverges from rollback policy');

  const entries=Array.isArray(lineage.entries)?lineage.entries:[];
  if(entries.length===0) failures.push('authority lineage has no entries');

  const firstOccurrence=new Map();
  let previous=null;
  let previousTime=-Infinity;
  for(let index=0;index<entries.length;index++){
    const entry=entries[index]||{};
    const sequence=index+1;
    if(entry.sequence!==sequence) failures.push('entry '+sequence+' has non-contiguous sequence');
    if(!SHA40.test(String(entry.authoritySha||''))) failures.push('entry '+sequence+' has invalid authority SHA');
    if(!SHA40.test(String(entry.workflowBlobSha||''))) failures.push('entry '+sequence+' has invalid workflow blob SHA');

    const activated=Date.parse(String(entry.activatedAt||''));
    if(Number.isNaN(activated)) failures.push('entry '+sequence+' has invalid activatedAt');
    else if(activated<=previousTime) failures.push('entry '+sequence+' activation time is not strictly increasing');
    previousTime=activated;

    if(sequence===1){
      if(entry.kind!=='bootstrap') failures.push('first lineage entry must be bootstrap');
      if(entry.predecessorAuthoritySha!==null) failures.push('first lineage entry must have null predecessor');
      if(entry.promotionReceipt!==null) failures.push('bootstrap lineage entry must not have a promotion receipt');
      if(entry.rollbackReceipt!==null) failures.push('bootstrap lineage entry must not have a rollback receipt');
      if(SHA40.test(String(entry.authoritySha||''))&&!firstOccurrence.has(entry.authoritySha)){
        firstOccurrence.set(entry.authoritySha,{sequence,workflowBlobSha:entry.workflowBlobSha});
      }
    }else{
      if(!same(entry.predecessorAuthoritySha,previous?.authoritySha)){
        failures.push('entry '+sequence+' predecessor does not match previous active authority SHA');
      }

      if(entry.kind==='promotion'){
        if(firstOccurrence.has(entry.authoritySha)) failures.push('entry '+sequence+' promotion reuses an authority SHA; use rollback activation');
        if(entry.rollbackReceipt!==null) failures.push('entry '+sequence+' promotion must not have a rollback receipt');

        const reference=entry.promotionReceipt;
        if(!reference||typeof reference!=='object'||Array.isArray(reference)){
          failures.push('entry '+sequence+' promotion receipt reference missing');
        }else if(!PROMOTION_RECEIPT_PATH.test(String(reference.path||''))){
          failures.push('entry '+sequence+' promotion receipt path invalid');
        }else if(typeof resolvePromotionReceipt!=='function'){
          failures.push('entry '+sequence+' promotion receipt resolver unavailable');
        }else{
          try{
            const resolved=resolvePromotionReceipt(reference.path);
            failures.push(...verifyPromotionReceipt({entry,previous,activated,promotionPolicy,reference,resolved,sequence}));
          }catch(error){
            failures.push('entry '+sequence+' promotion receipt cannot be resolved: '+(error instanceof Error?error.message:String(error)));
          }
        }

        if(SHA40.test(String(entry.authoritySha||''))&&!firstOccurrence.has(entry.authoritySha)){
          firstOccurrence.set(entry.authoritySha,{sequence,workflowBlobSha:entry.workflowBlobSha});
        }
      }else if(entry.kind==='rollback'){
        if(entry.promotionReceipt!==null) failures.push('entry '+sequence+' rollback must not have a promotion receipt');
        const original=firstOccurrence.get(entry.authoritySha);
        if(!original) failures.push('entry '+sequence+' rollback target has no earlier trusted lineage occurrence');
        else if(!same(entry.workflowBlobSha,original.workflowBlobSha)) failures.push('entry '+sequence+' rollback workflow blob differs from original trusted occurrence');

        const reference=entry.rollbackReceipt;
        if(!reference||typeof reference!=='object'||Array.isArray(reference)){
          failures.push('entry '+sequence+' rollback receipt reference missing');
        }else if(!ROLLBACK_RECEIPT_PATH.test(String(reference.path||''))){
          failures.push('entry '+sequence+' rollback receipt path invalid');
        }else if(typeof resolveRollbackReceipt!=='function'){
          failures.push('entry '+sequence+' rollback receipt resolver unavailable');
        }else{
          try{
            const resolved=resolveRollbackReceipt(reference.path);
            failures.push(...verifyRollbackReceipt({entry,previous,original,activated,rollbackPolicy,reference,resolved,sequence}));
          }catch(error){
            failures.push('entry '+sequence+' rollback receipt cannot be resolved: '+(error instanceof Error?error.message:String(error)));
          }
        }
      }else{
        failures.push('entry '+sequence+' has unsupported activation kind');
      }
    }

    if(typeof resolveWorkflowBlob==='function'&&SHA40.test(String(entry.authoritySha||''))){
      try{
        const resolved=resolveWorkflowBlob(entry.authoritySha,workflow.path);
        if(!same(resolved,entry.workflowBlobSha)){
          failures.push('entry '+sequence+' workflow blob mismatch '+resolved+' != '+entry.workflowBlobSha);
        }
      }catch(error){
        failures.push('entry '+sequence+' authority commit/workflow cannot be resolved: '+(error instanceof Error?error.message:String(error)));
      }
    }
    previous=entry;
  }

  const active=entries.at(-1);
  if(active){
    if(!same(active.authoritySha,canonicalWorkflow.authoritySha)) failures.push('active lineage authority SHA diverges from authority contract');
    if(!same(active.authoritySha,runtime.authoritySha)) failures.push('active lineage authority SHA diverges from runtime binding');
    if(!same(workflow.repository,runtime.repository)) failures.push('runtime repository diverges from lineage workflow');
    if(!same(workflow.repositoryId,runtime.repositoryId)) failures.push('runtime repository id diverges from lineage workflow');
    if(!same(workflow.path,runtime.workflowPath)) failures.push('runtime workflow path diverges from lineage workflow');

    const ref=expectedRef(workflow,active.authoritySha);
    if(!same(authority.enforcement?.requiredJobWorkflowRef,ref)) failures.push('authority required job workflow ref diverges from active lineage');
    if(!same(authority.enforcement?.requiredJobWorkflowSha,active.authoritySha)) failures.push('authority required job workflow SHA diverges from active lineage');
    const runtimeRef=expectedRef({repository:runtime.repository,path:runtime.workflowPath},runtime.authoritySha);
    if(!same(runtimeRef,ref)) failures.push('runtime derived authority ref diverges from active lineage');
  }

  return failures;
}

export function resolveGitWorkflowBlob(authoritySha,workflowPath){
  if(!SHA40.test(String(authoritySha||''))) throw new Error('invalid authority SHA');
  execFileSync('git',['cat-file','-e',authoritySha+'^{commit}'],{stdio:'ignore'});
  const row=execFileSync('git',['ls-tree',authoritySha,'--',workflowPath],{encoding:'utf8'}).trim();
  const match=row.match(/\bblob ([a-f0-9]{40})\t/);
  if(!match) throw new Error('workflow path missing at authority commit');
  return match[1];
}

function resolveRepositoryReceipt(path,pattern){
  if(!pattern.test(String(path||''))) throw new Error('invalid receipt path');
  const root=new URL('../../../',import.meta.url);
  const bytes=readFileSync(new URL(path,root));
  return {receipt:JSON.parse(bytes.toString('utf8')),blobSha:gitBlobSha(bytes)};
}
export const resolveRepositoryPromotionReceipt=path=>resolveRepositoryReceipt(path,PROMOTION_RECEIPT_PATH);
export const resolveRepositoryRollbackReceipt=path=>resolveRepositoryReceipt(path,ROLLBACK_RECEIPT_PATH);

function selfTest(){
  const workflow={repository:'doug-dotcom/ShineUniverse-shine-core',repositoryId:'1072897952',path:'.github/workflows/shine-defence-release-attestation-v1.yml'};
  const first='1'.repeat(40),second='2'.repeat(40),firstBlob='a'.repeat(40),secondBlob='b'.repeat(40);
  const promotionPolicy={
    contract:'shine-defence/release-attestation-authority-promotion-v1',
    version:'1.0.0',
    receipt:{
      directory:'security/shine-defence/release-attestation-authority-promotions',
      contract:'shine-defence/release-attestation-authority-promotion-receipt-v1',
      version:'1.0.0',
      status:'approved'
    },
    requiredReviewControls:['workflowDiffReviewed','oidcClaimCompatibilityReviewed','rollbackReadinessReviewed','consumerMigrationReviewed']
  };
  const rollbackPolicy={
    contract:'shine-defence/release-attestation-authority-rollback-v1',
    version:'1.0.0',
    receipt:{
      directory:'security/shine-defence/release-attestation-authority-rollbacks',
      contract:'shine-defence/release-attestation-authority-rollback-receipt-v1',
      version:'1.0.0',
      status:'approved'
    },
    requiredReviewControls:['incidentConfirmed','restoreAuthorityReviewed','oidcCompatibilityReviewed','consumerCompatibilityReviewed']
  };

  const promotionReceipt={
    contract:promotionPolicy.receipt.contract,
    version:'1.0.0',
    promotionId:'authority-'+second.slice(0,12),
    status:'approved',
    predecessorAuthoritySha:first,
    successorAuthoritySha:second,
    successorWorkflowBlobSha:secondBlob,
    reviewerId:'reviewer-1',
    approvedAt:'2026-09-30T01:50:00.000Z',
    summary:'Reviewed and approved the bounded forward authority rotation.',
    reviewControls:{
      workflowDiffReviewed:true,
      oidcClaimCompatibilityReviewed:true,
      rollbackReadinessReviewed:true,
      consumerMigrationReviewed:true
    }
  };
  const promotionBytes=Buffer.from(JSON.stringify(promotionReceipt,null,2)+'\n');
  const promotionPath=promotionPolicy.receipt.directory+'/'+promotionReceipt.promotionId+'.json';
  const promotionSha=gitBlobSha(promotionBytes);

  const rollbackReceipt={
    contract:rollbackPolicy.receipt.contract,
    version:'1.0.0',
    rollbackId:'rollback-'+first.slice(0,12),
    status:'approved',
    failedAuthoritySha:second,
    restoreAuthoritySha:first,
    restoreWorkflowBlobSha:firstBlob,
    restoreFromSequence:1,
    reviewerId:'reviewer-2',
    approvedAt:'2026-09-30T02:50:00.000Z',
    summary:'Incident confirmed; restore the previously trusted bootstrap authority.',
    reviewControls:{
      incidentConfirmed:true,
      restoreAuthorityReviewed:true,
      oidcCompatibilityReviewed:true,
      consumerCompatibilityReviewed:true
    }
  };
  const rollbackBytes=Buffer.from(JSON.stringify(rollbackReceipt,null,2)+'\n');
  const rollbackPath=rollbackPolicy.receipt.directory+'/'+rollbackReceipt.rollbackId+'.json';
  const rollbackSha=gitBlobSha(rollbackBytes);

  const lineage={
    contract:'shine-defence/release-attestation-authority-lineage-v1',
    version:'1.2.0',
    workflow,
    promotionGate:{
      contractPath:'security/shine-defence/release-attestation-authority-promotion-v1.json',
      receiptDirectory:promotionPolicy.receipt.directory,
      bootstrapSequence:1
    },
    rollbackGate:{
      contractPath:'security/shine-defence/release-attestation-authority-rollback-v1.json',
      receiptDirectory:rollbackPolicy.receipt.directory
    },
    entries:[
      {sequence:1,kind:'bootstrap',authoritySha:first,workflowBlobSha:firstBlob,activatedAt:'2026-09-30T01:00:00.000Z',predecessorAuthoritySha:null,promotionReceipt:null,rollbackReceipt:null},
      {sequence:2,kind:'promotion',authoritySha:second,workflowBlobSha:secondBlob,activatedAt:'2026-09-30T02:00:00.000Z',predecessorAuthoritySha:first,promotionReceipt:{path:promotionPath,blobSha:promotionSha},rollbackReceipt:null},
      {sequence:3,kind:'rollback',authoritySha:first,workflowBlobSha:firstBlob,activatedAt:'2026-09-30T03:00:00.000Z',predecessorAuthoritySha:second,promotionReceipt:null,rollbackReceipt:{path:rollbackPath,blobSha:rollbackSha}}
    ]
  };
  const runtime={repository:workflow.repository,repositoryId:workflow.repositoryId,workflowPath:workflow.path,authoritySha:first};
  const authority={
    reusableWorkflow:{...workflow,authoritySha:first},
    enforcement:{requiredJobWorkflowRef:expectedRef(workflow,first),requiredJobWorkflowSha:first},
    promotionGate:{contractPath:'security/shine-defence/release-attestation-authority-promotion-v1.json',receiptDirectory:promotionPolicy.receipt.directory},
    rollbackGate:{contractPath:'security/shine-defence/release-attestation-authority-rollback-v1.json',receiptDirectory:rollbackPolicy.receipt.directory}
  };
  const blobs=new Map([[first,firstBlob],[second,secondBlob]]);
  const workflowResolver=sha=>blobs.get(sha);
  const promotionResolver=path=>{
    if(path!==promotionPath) throw new Error('unknown promotion receipt');
    return {receipt:JSON.parse(promotionBytes.toString('utf8')),blobSha:promotionSha};
  };
  const rollbackResolver=path=>{
    if(path!==rollbackPath) throw new Error('unknown rollback receipt');
    return {receipt:JSON.parse(rollbackBytes.toString('utf8')),blobSha:rollbackSha};
  };
  const verify=overrides=>verifyAuthorityLineage({
    lineage,
    authority,
    promotionPolicy,
    rollbackPolicy,
    runtime,
    resolveWorkflowBlob:workflowResolver,
    resolvePromotionReceipt:promotionResolver,
    resolveRollbackReceipt:rollbackResolver,
    ...overrides
  });

  const ok=verify();
  if(ok.length) throw new Error('valid promotion+rollback lineage rejected: '+ok.join('; '));

  const accidentalReplay=structuredClone(lineage);
  accidentalReplay.entries[1].authoritySha=first;
  accidentalReplay.entries[1].workflowBlobSha=firstBlob;
  if(!verify({lineage:accidentalReplay}).some(x=>x.includes('promotion reuses an authority SHA'))){
    throw new Error('promotion replay of prior authority was not rejected');
  }

  const missingRollback=structuredClone(lineage);
  missingRollback.entries[2].rollbackReceipt=null;
  if(!verify({lineage:missingRollback}).some(x=>x.includes('rollback receipt reference missing'))){
    throw new Error('missing rollback receipt was not rejected');
  }

  const wrongRollbackBlob=structuredClone(lineage);
  wrongRollbackBlob.entries[2].workflowBlobSha='c'.repeat(40);
  if(!verify({lineage:wrongRollbackBlob}).some(x=>x.includes('rollback workflow blob differs'))){
    throw new Error('rollback to altered workflow bytes was not rejected');
  }

  const badRollback={...rollbackReceipt,reviewControls:{...rollbackReceipt.reviewControls,incidentConfirmed:false}};
  const badRollbackBytes=Buffer.from(JSON.stringify(badRollback,null,2)+'\n');
  const badRollbackLineage=structuredClone(lineage);
  badRollbackLineage.entries[2].rollbackReceipt.blobSha=gitBlobSha(badRollbackBytes);
  if(!verify({
    lineage:badRollbackLineage,
    resolveRollbackReceipt:()=>({receipt:badRollback,blobSha:gitBlobSha(badRollbackBytes)})
  }).some(x=>x.includes('incidentConfirmed'))){
    throw new Error('rollback without confirmed incident was not rejected');
  }

  const staleRuntime={...runtime,authoritySha:second};
  if(!verify({runtime:staleRuntime}).some(x=>x.includes('runtime binding'))){
    throw new Error('stale runtime after rollback was not rejected');
  }

  console.log('SHINE DEFENCE RELEASE ATTESTATION AUTHORITY LINEAGE SELF-TEST: PASS promotion uniqueness, receipt-gated rollback reactivation, original workflow-byte restoration and active runtime/contract parity');
}

function main(){
  if(process.argv.includes('--self-test')) return selfTest();
  const lineage=JSON.parse(readFileSync(new URL('../release-attestation-authority-lineage-v1.json',import.meta.url),'utf8'));
  const authority=JSON.parse(readFileSync(new URL('../release-attestation-authority-v1.json',import.meta.url),'utf8'));
  const promotionPolicy=JSON.parse(readFileSync(new URL('../release-attestation-authority-promotion-v1.json',import.meta.url),'utf8'));
  const rollbackPolicy=JSON.parse(readFileSync(new URL('../release-attestation-authority-rollback-v1.json',import.meta.url),'utf8'));
  const failures=verifyAuthorityLineage({
    lineage,
    authority,
    promotionPolicy,
    rollbackPolicy,
    resolveWorkflowBlob:resolveGitWorkflowBlob,
    resolvePromotionReceipt:resolveRepositoryPromotionReceipt,
    resolveRollbackReceipt:resolveRepositoryRollbackReceipt
  });
  if(failures.length){
    for(const failure of failures) console.error('FAIL '+failure);
    process.exit(1);
  }
  console.log('SHINE DEFENCE RELEASE ATTESTATION AUTHORITY LINEAGE: PASS '+lineage.entries.length+' activation(s), active '+lineage.entries.at(-1).authoritySha);
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)main();
