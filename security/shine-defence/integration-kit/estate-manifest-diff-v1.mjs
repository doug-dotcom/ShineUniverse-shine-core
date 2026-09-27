#!/usr/bin/env node
import {readFileSync,statSync} from 'node:fs';
import {isAbsolute,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {estateManifestSha} from './estate-audit-manifest-v1.mjs';

export const SHINE_DEFENCE_ESTATE_MANIFEST_DIFF_VERSION='1.0.1';
const DIMENSIONS=['repository','exportSha256','reviewCommitSha','observedReleaseCommitSha','deploymentState','checkpointIntegrityState'];
const fail=m=>{throw new Error(m)};
const clone=v=>JSON.parse(JSON.stringify(v));

export function verifyManifest(manifest){
  const failures=[];
  if(manifest?.artifact!=='shine-defence/estate-audit-manifest-v1'||manifest.version!=='1.0.0')return ['unsupported estate audit manifest'];
  if(!Array.isArray(manifest.entries))return ['manifest entries missing'];
  if(manifest.reviewedApps!==manifest.entries.length)failures.push('reviewedApps count mismatch');
  const ids=new Set();
  for(const e of manifest.entries){if(ids.has(e.appId))failures.push('duplicate appId '+e.appId);ids.add(e.appId)}
  const body=clone(manifest);delete body.manifestSha256;
  if(manifest.manifestSha256!==estateManifestSha(body))failures.push('manifestSha256 mismatch');
  return failures;
}
export function diffEstateManifests({before,after}){
  const bf=verifyManifest(before),af=verifyManifest(after);
  if(bf.length)fail('before manifest invalid: '+bf.join('; '));
  if(af.length)fail('after manifest invalid: '+af.join('; '));
  const b=new Map(before.entries.map(e=>[e.appId,e])),a=new Map(after.entries.map(e=>[e.appId,e]));
  const ids=[...new Set([...b.keys(),...a.keys()])].sort(),items=[];
  for(const appId of ids){
    const x=b.get(appId),y=a.get(appId);
    if(!x){items.push({appId,status:'added',before:null,after:clone(y),changes:[]});continue}
    if(!y){items.push({appId,status:'removed',before:clone(x),after:null,changes:[]});continue}
    const changes=[];
    for(const dimension of DIMENSIONS)if((x[dimension]??null)!==(y[dimension]??null))changes.push({dimension,before:x[dimension]??null,after:y[dimension]??null});
    items.push({appId,status:changes.length?'changed':'unchanged',changes});
  }
  const counts={added:0,removed:0,changed:0,unchanged:0};for(const i of items)counts[i.status]++;
  return {
    report:'shine-defence/estate-manifest-diff-v1',version:'1.0.0',
    before:{asOf:before.asOf,manifestSha256:before.manifestSha256,reviewedApps:before.reviewedApps},
    after:{asOf:after.asOf,manifestSha256:after.manifestSha256,reviewedApps:after.reviewedApps},
    counts,changedDimensions:DIMENSIONS,items
  };
}
function readManifest(path,label){
  const full=isAbsolute(path)?path:resolve(process.cwd(),path),s=statSync(full);
  if(!s.isFile()||s.size>1024*1024)fail(label+' manifest must be JSON no larger than 1 MiB');
  try{return JSON.parse(readFileSync(full,'utf8'))}catch{fail(label+' manifest is not valid JSON')}
}
function makeManifest(asOf,entries){
  const body={artifact:'shine-defence/estate-audit-manifest-v1',version:'1.0.0',asOf,reviewedApps:entries.length,entries,provenance:{reviewedLedger:'ledger',auditExportContract:'audit'}};
  return {...body,manifestSha256:estateManifestSha(body)};
}
function selfTest(){
  const base={appId:'a',repository:'o/a',exportSha256:'1'.repeat(64),reviewCommitSha:'a'.repeat(40),observedReleaseCommitSha:'b'.repeat(40),deploymentState:'deployment_drift',checkpointIntegrityState:'not_applicable'};
  const before=makeManifest('2026-09-27T08:00:00.000Z',[base,{...base,appId:'removed',repository:'o/r'}]);
  const after=makeManifest('2026-09-28T08:00:00.000Z',[
    {...base,exportSha256:'2'.repeat(64),observedReleaseCommitSha:'c'.repeat(40),deploymentState:'protected',checkpointIntegrityState:'verified'},
    {...base,appId:'added',repository:'o/n'}
  ]);
  const r=diffEstateManifests({before,after});
  if(JSON.stringify(r.counts)!==JSON.stringify({added:1,removed:1,changed:1,unchanged:0}))fail('diff counts mismatch');
  const a=r.items.find(i=>i.appId==='a');if(a.changes.map(c=>c.dimension).join(',')!=='exportSha256,observedReleaseCommitSha,deploymentState,checkpointIntegrityState')fail('dimension diff mismatch');
  const tampered=clone(before);tampered.entries[0].deploymentState='protected';let blocked=false;try{diffEstateManifests({before:tampered,after})}catch{blocked=true}if(!blocked)fail('tampered manifest accepted');
  console.log('SHINE DEFENCE ESTATE MANIFEST DIFF SELF-TEST: PASS added/removed/changed detection, exact dimension changes and invalid-manifest fail-closed');
}
function main(){
  const args=process.argv.slice(2),bi=args.indexOf('--before'),ai=args.indexOf('--after');
  if(args.includes('--self-test'))return selfTest();
  if(bi<0||!args[bi+1]||ai<0||!args[ai+1])fail('--before and --after manifest paths are required');
  console.log(JSON.stringify(diffEstateManifests({before:readManifest(args[bi+1],'before'),after:readManifest(args[ai+1],'after')}),null,2));
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)main();
