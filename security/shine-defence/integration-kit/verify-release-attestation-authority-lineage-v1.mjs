#!/usr/bin/env node
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {
  SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY,
  SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY_REF,
  SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY_SHA
} from '../../../foundation/runtime/_shared/shine-defence-release-attestation-authority-v1.mjs';

export const SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY_LINEAGE_VERIFIER_VERSION='1.0.0';

const SHA40=/^[a-f0-9]{40}$/;

const same=(a,b)=>String(a??'')===String(b??'');
const expectedRef=(workflow,sha)=>workflow.repository+'/'+workflow.path+'@'+sha;

export function verifyAuthorityLineage({lineage,authority,runtime=SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY,resolveWorkflowBlob}={}){
  const failures=[];
  if(!lineage||typeof lineage!=='object')return ['lineage document is required'];
  if(!authority||typeof authority!=='object')return ['authority contract is required'];
  if(!runtime||typeof runtime!=='object')return ['runtime authority binding is required'];

  if(lineage.contract!=='shine-defence/release-attestation-authority-lineage-v1') failures.push('unsupported lineage contract');
  if(lineage.version!=='1.0.0') failures.push('unsupported lineage version');

  const workflow=lineage.workflow||{};
  const canonicalWorkflow=authority.reusableWorkflow||{};
  for(const key of ['repository','repositoryId','path']){
    if(!same(workflow[key],canonicalWorkflow[key])) failures.push('workflow '+key+' diverges from authority contract');
  }

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
    }else if(!same(entry.predecessorAuthoritySha,previous.authoritySha)){
      failures.push('entry '+sequence+' predecessor does not match previous authority SHA');
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
    if(!same(SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY_REF,ref)) failures.push('runtime exported authority ref diverges from active lineage');
    if(!same(SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY_SHA,active.authoritySha)) failures.push('runtime exported authority SHA diverges from active lineage');
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

function selfTest(){
  const workflow={repository:'doug-dotcom/ShineUniverse-shine-core',repositoryId:'1072897952',path:'.github/workflows/shine-defence-release-attestation-v1.yml'};
  const first='1'.repeat(40),second='2'.repeat(40),firstBlob='a'.repeat(40),secondBlob='b'.repeat(40);
  const lineage={
    contract:'shine-defence/release-attestation-authority-lineage-v1',
    version:'1.0.0',
    workflow,
    entries:[
      {sequence:1,authoritySha:first,workflowBlobSha:firstBlob,activatedAt:'2026-09-30T01:00:00.000Z',predecessorAuthoritySha:null},
      {sequence:2,authoritySha:second,workflowBlobSha:secondBlob,activatedAt:'2026-09-30T02:00:00.000Z',predecessorAuthoritySha:first}
    ]
  };
  const runtime={repository:workflow.repository,repositoryId:workflow.repositoryId,workflowPath:workflow.path,authoritySha:second};
  const authority={
    reusableWorkflow:{...workflow,authoritySha:second},
    enforcement:{requiredJobWorkflowRef:expectedRef(workflow,second),requiredJobWorkflowSha:second}
  };
  const blobs=new Map([[first,firstBlob],[second,secondBlob]]);
  const resolver=sha=>blobs.get(sha);

  const ok=verifyAuthorityLineage({lineage,authority,runtime,resolveWorkflowBlob:resolver});
  if(ok.length) throw new Error('valid lineage rejected: '+ok.join('; '));

  const brokenPredecessor=structuredClone(lineage);
  brokenPredecessor.entries[1].predecessorAuthoritySha='3'.repeat(40);
  if(!verifyAuthorityLineage({lineage:brokenPredecessor,authority,runtime,resolveWorkflowBlob:resolver}).some(x=>x.includes('predecessor'))){
    throw new Error('broken predecessor was not rejected');
  }

  const brokenBlob=structuredClone(lineage);
  brokenBlob.entries[1].workflowBlobSha='c'.repeat(40);
  if(!verifyAuthorityLineage({lineage:brokenBlob,authority,runtime,resolveWorkflowBlob:resolver}).some(x=>x.includes('workflow blob mismatch'))){
    throw new Error('workflow blob tamper was not rejected');
  }

  const staleRuntime={...runtime,authoritySha:first};
  if(!verifyAuthorityLineage({lineage,authority,runtime:staleRuntime,resolveWorkflowBlob:resolver}).some(x=>x.includes('runtime binding'))){
    throw new Error('stale runtime authority was not rejected');
  }

  console.log('SHINE DEFENCE RELEASE ATTESTATION AUTHORITY LINEAGE SELF-TEST: PASS append-only predecessor chain, workflow blob proof and active runtime/contract parity');
}

function main(){
  if(process.argv.includes('--self-test')) return selfTest();
  const lineage=JSON.parse(readFileSync(new URL('../release-attestation-authority-lineage-v1.json',import.meta.url),'utf8'));
  const authority=JSON.parse(readFileSync(new URL('../release-attestation-authority-v1.json',import.meta.url),'utf8'));
  const failures=verifyAuthorityLineage({lineage,authority,resolveWorkflowBlob:resolveGitWorkflowBlob});
  if(failures.length){
    for(const failure of failures) console.error('FAIL '+failure);
    process.exit(1);
  }
  console.log('SHINE DEFENCE RELEASE ATTESTATION AUTHORITY LINEAGE: PASS '+lineage.entries.length+' authority generation(s), active '+lineage.entries.at(-1).authoritySha);
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)main();
