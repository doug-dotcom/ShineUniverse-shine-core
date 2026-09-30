#!/usr/bin/env node
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {
  SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY
} from '../../../foundation/runtime/_shared/shine-defence-release-attestation-authority-v1.mjs';

export const SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY_LINEAGE_VERIFIER_VERSION='1.1.0';

const SHA40=/^[a-f0-9]{40}$/;
const RECEIPT_PATH=/^security\/shine-defence\/release-attestation-authority-promotions\/[a-z0-9][a-z0-9._-]*\.json$/;

const same=(a,b)=>String(a??'')===String(b??'');
const expectedRef=(workflow,sha)=>workflow.repository+'/'+workflow.path+'@'+sha;
const gitBlobSha=bytes=>createHash('sha1').update(Buffer.from('blob '+bytes.length+'\0')).update(bytes).digest('hex');
const clean=(value,max)=>typeof value==='string'&&value.length>0&&value.length<=max&&!/[\u0000-\u001f\u007f]/.test(value);

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
    const expectedPath=(promotionPolicy?.receipt?.directory||promotionPolicy?.receiptDirectory||'security/shine-defence/release-attestation-authority-promotions')+'/'+receipt.promotionId+'.json';
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

  if(!SHA40.test(String(reference.blobSha||''))) failures.push('entry '+sequence+' promotion receipt blob SHA invalid');
  if(!same(reference.blobSha,resolved?.blobSha)) failures.push('entry '+sequence+' promotion receipt blob fingerprint mismatch');

  return failures;
}

export function verifyAuthorityLineage({
  lineage,
  authority,
  promotionPolicy,
  runtime=SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY,
  resolveWorkflowBlob,
  resolvePromotionReceipt
}={}){
  const failures=[];
  if(!lineage||typeof lineage!=='object')return ['lineage document is required'];
  if(!authority||typeof authority!=='object')return ['authority contract is required'];
  if(!promotionPolicy||typeof promotionPolicy!=='object')return ['promotion policy is required'];
  if(!runtime||typeof runtime!=='object')return ['runtime authority binding is required'];

  if(lineage.contract!=='shine-defence/release-attestation-authority-lineage-v1') failures.push('unsupported lineage contract');
  if(lineage.version!=='1.1.0') failures.push('unsupported lineage version');
  if(promotionPolicy.contract!=='shine-defence/release-attestation-authority-promotion-v1'||promotionPolicy.version!=='1.0.0'){
    failures.push('unsupported promotion policy');
  }

  const workflow=lineage.workflow||{};
  const canonicalWorkflow=authority.reusableWorkflow||{};
  for(const key of ['repository','repositoryId','path']){
    if(!same(workflow[key],canonicalWorkflow[key])) failures.push('workflow '+key+' diverges from authority contract');
  }

  const gate=lineage.promotionGate||{};
  if(!same(gate.contractPath,authority.promotionGate?.contractPath)) failures.push('lineage promotion contract path diverges from authority contract');
  if(!same(gate.receiptDirectory,authority.promotionGate?.receiptDirectory)) failures.push('lineage promotion receipt directory diverges from authority contract');
  if(!same(gate.contractPath,'security/shine-defence/release-attestation-authority-promotion-v1.json')) failures.push('lineage promotion contract path invalid');
  if(!same(gate.receiptDirectory,promotionPolicy.receipt?.directory)) failures.push('lineage promotion receipt directory diverges from promotion policy');
  if(gate.bootstrapSequence!==1) failures.push('lineage bootstrap sequence must be 1');

  const entries=Array.isArray(lineage.entries)?lineage.entries:[];
  if(entries.length===0) failures.push('authority lineage has no entries');

  const seen=new Set();
  let previous=null;
  let previousTime=-Infinity;
  for(let index=0;index<entries.length;index++){
    const entry=entries[index]||{};
    const sequence=index+1;
    if(entry.sequence!==sequence) failures.push('entry '+sequence+' has non-contiguous sequence');
    if(!SHA40.test(String(entry.authoritySha||''))) failures.push('entry '+sequence+' has invalid authority SHA');
    if(!SHA40.test(String(entry.workflowBlobSha||''))) failures.push('entry '+sequence+' has invalid workflow blob SHA');
    if(seen.has(entry.authoritySha)) failures.push('entry '+sequence+' repeats an authority SHA');
    seen.add(entry.authoritySha);

    const activated=Date.parse(String(entry.activatedAt||''));
    if(Number.isNaN(activated)) failures.push('entry '+sequence+' has invalid activatedAt');
    else if(activated<=previousTime) failures.push('entry '+sequence+' activation time is not strictly increasing');
    previousTime=activated;

    if(sequence===1){
      if(entry.predecessorAuthoritySha!==null) failures.push('first lineage entry must have null predecessor');
      if(entry.promotionReceipt!==null) failures.push('bootstrap lineage entry must not have a promotion receipt');
    }else{
      if(!same(entry.predecessorAuthoritySha,previous?.authoritySha)){
        failures.push('entry '+sequence+' predecessor does not match previous authority SHA');
      }
      const reference=entry.promotionReceipt;
      if(!reference||typeof reference!=='object'||Array.isArray(reference)){
        failures.push('entry '+sequence+' promotion receipt reference missing');
      }else if(!RECEIPT_PATH.test(String(reference.path||''))){
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

export function resolveRepositoryPromotionReceipt(path){
  if(!RECEIPT_PATH.test(String(path||''))) throw new Error('invalid promotion receipt path');
  const root=new URL('../../../',import.meta.url);
  const bytes=readFileSync(new URL(path,root));
  return {receipt:JSON.parse(bytes.toString('utf8')),blobSha:gitBlobSha(bytes)};
}

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
  const receipt={
    contract:'shine-defence/release-attestation-authority-promotion-receipt-v1',
    version:'1.0.0',
    promotionId:'authority-'+second.slice(0,12),
    status:'approved',
    predecessorAuthoritySha:first,
    successorAuthoritySha:second,
    successorWorkflowBlobSha:secondBlob,
    reviewerId:'reviewer-1',
    approvedAt:'2026-09-30T01:50:00.000Z',
    summary:'Reviewed the authority rotation and approved the bounded trust-root change.',
    reviewControls:{
      workflowDiffReviewed:true,
      oidcClaimCompatibilityReviewed:true,
      rollbackReadinessReviewed:true,
      consumerMigrationReviewed:true
    }
  };
  const receiptBytes=Buffer.from(JSON.stringify(receipt,null,2)+'\n');
  const receiptPath=promotionPolicy.receipt.directory+'/'+receipt.promotionId+'.json';
  const receiptSha=gitBlobSha(receiptBytes);
  const lineage={
    contract:'shine-defence/release-attestation-authority-lineage-v1',
    version:'1.1.0',
    workflow,
    promotionGate:{
      contractPath:'security/shine-defence/release-attestation-authority-promotion-v1.json',
      receiptDirectory:promotionPolicy.receipt.directory,
      bootstrapSequence:1
    },
    entries:[
      {sequence:1,authoritySha:first,workflowBlobSha:firstBlob,activatedAt:'2026-09-30T01:00:00.000Z',predecessorAuthoritySha:null,promotionReceipt:null},
      {sequence:2,authoritySha:second,workflowBlobSha:secondBlob,activatedAt:'2026-09-30T02:00:00.000Z',predecessorAuthoritySha:first,promotionReceipt:{path:receiptPath,blobSha:receiptSha}}
    ]
  };
  const runtime={repository:workflow.repository,repositoryId:workflow.repositoryId,workflowPath:workflow.path,authoritySha:second};
  const authority={
    reusableWorkflow:{...workflow,authoritySha:second},
    enforcement:{requiredJobWorkflowRef:expectedRef(workflow,second),requiredJobWorkflowSha:second},
    promotionGate:{contractPath:'security/shine-defence/release-attestation-authority-promotion-v1.json',receiptDirectory:promotionPolicy.receipt.directory}
  };
  const blobs=new Map([[first,firstBlob],[second,secondBlob]]);
  const resolver=sha=>blobs.get(sha);
  const receiptResolver=path=>{
    if(path!==receiptPath) throw new Error('unknown receipt');
    return {receipt:JSON.parse(receiptBytes.toString('utf8')),blobSha:receiptSha};
  };

  const ok=verifyAuthorityLineage({lineage,authority,promotionPolicy,runtime,resolveWorkflowBlob:resolver,resolvePromotionReceipt:receiptResolver});
  if(ok.length) throw new Error('valid lineage rejected: '+ok.join('; '));

  const missingReceipt=structuredClone(lineage);
  delete missingReceipt.entries[1].promotionReceipt;
  if(!verifyAuthorityLineage({lineage:missingReceipt,authority,promotionPolicy,runtime,resolveWorkflowBlob:resolver,resolvePromotionReceipt:receiptResolver}).some(x=>x.includes('promotion receipt reference missing'))){
    throw new Error('missing promotion receipt was not rejected');
  }

  const brokenPredecessor=structuredClone(lineage);
  brokenPredecessor.entries[1].predecessorAuthoritySha='3'.repeat(40);
  if(!verifyAuthorityLineage({lineage:brokenPredecessor,authority,promotionPolicy,runtime,resolveWorkflowBlob:resolver,resolvePromotionReceipt:receiptResolver}).some(x=>x.includes('predecessor'))){
    throw new Error('broken predecessor was not rejected');
  }

  const brokenBlob=structuredClone(lineage);
  brokenBlob.entries[1].workflowBlobSha='c'.repeat(40);
  if(!verifyAuthorityLineage({lineage:brokenBlob,authority,promotionPolicy,runtime,resolveWorkflowBlob:resolver,resolvePromotionReceipt:receiptResolver}).some(x=>x.includes('workflow blob'))){
    throw new Error('workflow blob tamper was not rejected');
  }

  const badReceipt={...receipt,reviewControls:{...receipt.reviewControls,rollbackReadinessReviewed:false}};
  const badReceiptBytes=Buffer.from(JSON.stringify(badReceipt,null,2)+'\n');
  const badReceiptResolver=()=>({receipt:badReceipt,blobSha:gitBlobSha(badReceiptBytes)});
  const badReceiptLineage=structuredClone(lineage);
  badReceiptLineage.entries[1].promotionReceipt.blobSha=gitBlobSha(badReceiptBytes);
  if(!verifyAuthorityLineage({lineage:badReceiptLineage,authority,promotionPolicy,runtime,resolveWorkflowBlob:resolver,resolvePromotionReceipt:badReceiptResolver}).some(x=>x.includes('rollbackReadinessReviewed'))){
    throw new Error('incomplete promotion review was not rejected');
  }

  const tamperedReceiptResolver=()=>({receipt,blobSha:'f'.repeat(40)});
  if(!verifyAuthorityLineage({lineage,authority,promotionPolicy,runtime,resolveWorkflowBlob:resolver,resolvePromotionReceipt:tamperedReceiptResolver}).some(x=>x.includes('blob fingerprint mismatch'))){
    throw new Error('promotion receipt fingerprint tamper was not rejected');
  }

  const staleRuntime={...runtime,authoritySha:first};
  if(!verifyAuthorityLineage({lineage,authority,promotionPolicy,runtime:staleRuntime,resolveWorkflowBlob:resolver,resolvePromotionReceipt:receiptResolver}).some(x=>x.includes('runtime binding'))){
    throw new Error('stale runtime authority was not rejected');
  }

  console.log('SHINE DEFENCE RELEASE ATTESTATION AUTHORITY LINEAGE SELF-TEST: PASS predecessor chain, workflow blob proof, promotion receipt gate and active runtime/contract parity');
}

function main(){
  if(process.argv.includes('--self-test')) return selfTest();
  const lineage=JSON.parse(readFileSync(new URL('../release-attestation-authority-lineage-v1.json',import.meta.url),'utf8'));
  const authority=JSON.parse(readFileSync(new URL('../release-attestation-authority-v1.json',import.meta.url),'utf8'));
  const promotionPolicy=JSON.parse(readFileSync(new URL('../release-attestation-authority-promotion-v1.json',import.meta.url),'utf8'));
  const failures=verifyAuthorityLineage({
    lineage,
    authority,
    promotionPolicy,
    resolveWorkflowBlob:resolveGitWorkflowBlob,
    resolvePromotionReceipt:resolveRepositoryPromotionReceipt
  });
  if(failures.length){
    for(const failure of failures) console.error('FAIL '+failure);
    process.exit(1);
  }
  console.log('SHINE DEFENCE RELEASE ATTESTATION AUTHORITY LINEAGE: PASS '+lineage.entries.length+' authority generation(s), active '+lineage.entries.at(-1).authoritySha);
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)main();
