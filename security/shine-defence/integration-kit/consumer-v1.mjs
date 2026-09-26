#!/usr/bin/env node
import {createHash} from 'node:crypto';
import {existsSync,readFileSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {evaluateReleaseStatus} from './evaluate-release-status-v1.mjs';

export const SHINE_DEFENCE_CONSUMER_VERSION='1.0.0';

const sha=/^[a-f0-9]{40}$/;
export const gitBlobSha=bytes=>createHash('sha1').update(Buffer.from('blob '+bytes.length+'\0')).update(bytes).digest('hex');

export function verifyConsumerBundle({receipt,registryBytes,profileBytes,revocations,expectedAppId,expectedRepository}){
  const errors=[];
  let registry=null,profile=null;
  try{registry=JSON.parse(Buffer.from(registryBytes||[]).toString('utf8'))}catch{errors.push('registry snapshot invalid')}
  try{profile=JSON.parse(Buffer.from(profileBytes||[]).toString('utf8'))}catch{errors.push('Defence profile invalid')}
  if(!receipt||receipt.receipt!=='shine-defence/certification-receipt-v1'||receipt.version!=='1.0.0')errors.push('receipt invalid');
  if(receipt&&expectedAppId&&receipt.appId!==expectedAppId)errors.push('receipt app mismatch');
  if(receipt&&expectedRepository&&receipt.repository!==expectedRepository)errors.push('receipt repository mismatch');
  if(receipt&&(!sha.test(receipt.reviewCommitSha||'')||!sha.test(receipt.profileBlobSha||'')||!sha.test(receipt.registryBlobSha||'')))errors.push('receipt SHA invalid');
  const registryBlobSha=registryBytes?gitBlobSha(Buffer.from(registryBytes)):null;
  if(receipt&&registryBlobSha!==receipt.registryBlobSha)errors.push('registry snapshot hash mismatch');
  if(receipt&&registry){
    if(registry.registry!=='shine-defence/canonical-registry-v1'||registry.version!==receipt.registryVersion)errors.push('registry snapshot identity mismatch');
    const entries=new Map((registry.entries||[]).map(entry=>[entry.id,entry]));
    for(const id of receipt.policies||[])if(!entries.has(id))errors.push('receipt policy missing from registry: '+id);
    const release=entries.get('release-claim');
    if(!release||release.version!==receipt.releaseClaimContractVersion||release.blobSha!==receipt.releaseClaimContractBlobSha)errors.push('release-claim identity mismatch');
    const receiptContract=entries.get('certification-receipt');
    if(!receiptContract||receiptContract.version!==receipt.version)errors.push('receipt contract identity mismatch');
  }
  const currentProfileBlobSha=profileBytes?gitBlobSha(Buffer.from(profileBytes)):null;
  if(receipt&&profile){
    if(expectedAppId&&profile.app?.id!==expectedAppId)errors.push('current profile app mismatch');
    if(profile.version!==receipt.profileVersion)errors.push('current profile version mismatch');
  }
  if(!revocations||revocations.ledger!=='shine-defence/revocations-v1'||revocations.version!=='1.0.0'||!Array.isArray(revocations.revocations))errors.push('revocation ledger invalid');
  return {ok:errors.length===0,errors,registry,profile,registryBlobSha,currentProfileBlobSha};
}

export function evaluateConsumerStatus({
  receipt,registryBytes,profileBytes,revocations,releaseCommitSha,
  expectedAppId,expectedRepository,revocationFreshness='unknown'
}){
  if(!receipt)return {state:'receipt_missing',badgeCurrent:false,display:'No Defence receipt for this build'};
  const evidence=verifyConsumerBundle({receipt,registryBytes,profileBytes,revocations,expectedAppId,expectedRepository});
  if(!evidence.ok)return {state:'verification_failed',badgeCurrent:false,display:'Defence verification failed',appId:receipt.appId||null,errors:evidence.errors};
  const base=evaluateReleaseStatus({
    receipt,registry:evidence.registry,registryBlobSha:evidence.registryBlobSha,revocations,
    releaseCommitSha,profileBlobSha:evidence.currentProfileBlobSha
  });
  if(base.state==='reviewed_release'&&revocationFreshness!=='current'){
    return {...base,state:'verification_failed',badgeCurrent:false,display:'Defence verification failed',underlyingState:'reviewed_release',revocationFreshness,errors:['current revocation authority not established']};
  }
  return {...base,revocationFreshness};
}

export function loadConsumerFiles({
  root=process.cwd(),receiptPath='security/shine-defence/release-receipt.json',
  profilePath='security/shine-defence/profile.json',snapshotsDir='security/shine-defence/registry-snapshots',
  revocationsPath='security/shine-defence/revocations-v1.json'
}={}){
  if(!existsSync(join(root,receiptPath)))return {receipt:null,registryBytes:null,profileBytes:null,revocations:null};
  const receipt=JSON.parse(readFileSync(join(root,receiptPath),'utf8'));
  if(!sha.test(receipt.registryBlobSha||''))return {receipt,registryBytes:null,profileBytes:null,revocations:null};
  let registryBytes=null,profileBytes=null,revocations=null;
  try{registryBytes=readFileSync(join(root,snapshotsDir,receipt.registryBlobSha+'.json'))}catch{}
  try{profileBytes=readFileSync(join(root,profilePath))}catch{}
  try{revocations=JSON.parse(readFileSync(join(root,revocationsPath),'utf8'))}catch{}
  return {receipt,registryBytes,profileBytes,revocations};
}

function selfTest(){
  const registry={registry:'shine-defence/canonical-registry-v1',version:'1.0.0',entries:[
    {id:'baseline',version:'1.0.0',blobSha:'1'.repeat(40)},
    {id:'release-claim',version:'1.0.0',blobSha:'2'.repeat(40)},
    {id:'certification-receipt',version:'1.0.0',blobSha:'3'.repeat(40)}
  ]};
  const registryBytes=Buffer.from(JSON.stringify(registry));
  const registryBlobSha=gitBlobSha(registryBytes);
  const profileBytes=Buffer.from(JSON.stringify({app:{id:'demo'},version:'1.0.0'}));
  const profileBlobSha=gitBlobSha(profileBytes);
  const receipt={receipt:'shine-defence/certification-receipt-v1',version:'1.0.0',appId:'demo',repository:'doug/demo',reviewCommitSha:'a'.repeat(40),profileBlobSha,profileVersion:'1.0.0',policies:['baseline'],registryVersion:'1.0.0',registryBlobSha,releaseClaimContractVersion:'1.0.0',releaseClaimContractBlobSha:'2'.repeat(40)};
  const clean={ledger:'shine-defence/revocations-v1',version:'1.0.0',revocations:[]};
  const revoked={...clean,revocations:[{revocationId:'r1',appId:'demo',reviewCommitSha:'a'.repeat(40),profileBlobSha,revokedAt:'2026-01-01T00:00:00Z',reasonCode:'critical_defect',publicReason:'withdrawn'}]};
  const common={receipt,registryBytes,profileBytes,expectedAppId:'demo',expectedRepository:'doug/demo'};
  const cases=[
    ['receipt_missing',evaluateConsumerStatus({...common,receipt:null,revocations:clean,releaseCommitSha:'a'.repeat(40),revocationFreshness:'current'})],
    ['unreviewed_revision',evaluateConsumerStatus({...common,revocations:clean,releaseCommitSha:'b'.repeat(40),revocationFreshness:'unknown'})],
    ['revoked_release',evaluateConsumerStatus({...common,revocations:revoked,releaseCommitSha:'a'.repeat(40),revocationFreshness:'snapshot'})],
    ['verification_failed',evaluateConsumerStatus({...common,revocations:clean,releaseCommitSha:'a'.repeat(40),revocationFreshness:'snapshot'})],
    ['reviewed_release',evaluateConsumerStatus({...common,revocations:clean,releaseCommitSha:'a'.repeat(40),revocationFreshness:'current'})],
    ['verification_failed',evaluateConsumerStatus({...common,registryBytes:Buffer.from('{}'),revocations:clean,releaseCommitSha:'a'.repeat(40),revocationFreshness:'current'})]
  ];
  for(const [expected,value] of cases)if(value.state!==expected)throw new Error('expected '+expected+', got '+value.state);
  if(!cases[4][1].badgeCurrent||cases.filter((_,i)=>i!==4).some(([,value])=>value.badgeCurrent))throw new Error('badgeCurrent state error');
  console.log('SHINE DEFENCE CONSUMER: PASS '+cases.length+' states');
}

function main(){if(process.argv.includes('--self-test'))return selfTest()}
if(import.meta.url===pathToFileURL(process.argv[1]).href)main();
