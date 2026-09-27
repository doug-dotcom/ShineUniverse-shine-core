#!/usr/bin/env node
import {existsSync,readFileSync,renameSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {loadEstateAuditManifest} from './estate-audit-manifest-v1.mjs';
import {diffEstateManifests,verifyManifest} from './estate-manifest-diff-v1.mjs';

export const SHINE_DEFENCE_ESTATE_AUDIT_TIMELINE_VERSION='1.0.0';
const root=fileURLToPath(new URL('../../../',import.meta.url));
const timelinePath=join(root,'security/shine-defence/estate-audit-timeline.json');
const clone=v=>JSON.parse(JSON.stringify(v));
const fail=m=>{throw new Error(m)};
const json=v=>JSON.stringify(v,null,2)+'\n';
function atomicWrite(path,bytes){const t=path+'.tmp-'+process.pid;writeFileSync(t,bytes);renameSync(t,path)}

export function appendTimelineManifest({timeline,manifest}){
  const mf=verifyManifest(manifest);if(mf.length)fail('manifest invalid: '+mf.join('; '));
  const next=timeline?clone(timeline):{ledger:'shine-defence/estate-audit-timeline-v1',version:'1.0.0',entries:[]};
  const tf=verifyTimeline(next);if(tf.length)fail('timeline invalid before append: '+tf.join('; '));
  const previous=next.entries.at(-1);
  if(previous&&Date.parse(manifest.asOf)<=Date.parse(previous.manifest.asOf))fail('manifest asOf must increase strictly');
  const entry={
    sequence:next.entries.length+1,
    recordedAt:manifest.asOf,
    previousManifestSha256:previous?previous.manifest.manifestSha256:null,
    manifest:clone(manifest),
    transition:previous?diffEstateManifests({before:previous.manifest,after:manifest}):null
  };
  next.entries.push(entry);
  const after=verifyTimeline(next);if(after.length)fail('timeline invalid after append: '+after.join('; '));
  return next;
}
export function verifyTimeline(timeline){
  const failures=[];
  if(timeline?.ledger!=='shine-defence/estate-audit-timeline-v1'||timeline.version!=='1.0.0'||!Array.isArray(timeline.entries))return ['unsupported estate audit timeline'];
  for(let i=0;i<timeline.entries.length;i++){
    const e=timeline.entries[i],mf=verifyManifest(e.manifest);
    if(e.sequence!==i+1)failures.push('entry '+(i+1)+' sequence mismatch');
    if(mf.length)for(const f of mf)failures.push('entry '+(i+1)+' manifest: '+f);
    if(e.recordedAt!==e.manifest.asOf)failures.push('entry '+(i+1)+' recordedAt/asOf mismatch');
    if(i===0){
      if(e.previousManifestSha256!==null||e.transition!==null)failures.push('first entry must have null previous hash/transition');
    }else{
      const p=timeline.entries[i-1];
      if(Date.parse(e.manifest.asOf)<=Date.parse(p.manifest.asOf))failures.push('entry '+(i+1)+' asOf not strictly increasing');
      if(e.previousManifestSha256!==p.manifest.manifestSha256)failures.push('entry '+(i+1)+' previous manifest hash mismatch');
      try{
        const expected=diffEstateManifests({before:p.manifest,after:e.manifest});
        if(JSON.stringify(e.transition)!==JSON.stringify(expected))failures.push('entry '+(i+1)+' transition diff mismatch');
      }catch(error){failures.push('entry '+(i+1)+' transition recompute failed: '+error.message)}
    }
  }
  return failures;
}
export function firstAppearance(timeline,appId,dimension=null){
  const failures=verifyTimeline(timeline);if(failures.length)fail(failures.join('; '));
  for(const e of timeline.entries){
    if(e.sequence===1){
      const app=e.manifest.entries.find(x=>x.appId===appId);
      if(app&&!dimension)return {sequence:e.sequence,asOf:e.manifest.asOf,status:'present_at_timeline_start'};
      continue;
    }
    const item=e.transition.items.find(x=>x.appId===appId);
    if(!item)continue;
    if(!dimension&&item.status!=='unchanged')return {sequence:e.sequence,asOf:e.manifest.asOf,status:item.status};
    if(dimension&&item.changes?.some(c=>c.dimension===dimension))return {sequence:e.sequence,asOf:e.manifest.asOf,status:item.status,change:item.changes.find(c=>c.dimension===dimension)};
  }
  return null;
}
function selfTest(){
  const {estateManifestSha}=globalThis.__unused||{};
  const make=(asOf,state,hashChar)=>{
    const entries=[{appId:'a',repository:'o/a',exportSha256:hashChar.repeat(64),reviewCommitSha:'a'.repeat(40),observedReleaseCommitSha:'b'.repeat(40),deploymentState:state,checkpointIntegrityState:'not_applicable'}];
    const body={artifact:'shine-defence/estate-audit-manifest-v1',version:'1.0.0',asOf,reviewedApps:1,entries,provenance:{reviewedLedger:'ledger',auditExportContract:'audit'}};
    return import('./estate-audit-manifest-v1.mjs').then(m=>({...body,manifestSha256:m.estateManifestSha(body)}));
  };
  return Promise.all([make('2026-09-27T08:00:00.000Z','deployment_drift','1'),make('2026-09-28T08:00:00.000Z','protected','2'),make('2026-09-29T08:00:00.000Z','protected','2')]).then(([a,b,c])=>{
    let t=appendTimelineManifest({timeline:null,manifest:a});t=appendTimelineManifest({timeline:t,manifest:b});t=appendTimelineManifest({timeline:t,manifest:c});
    if(t.entries.length!==3||verifyTimeline(t).length)fail('timeline verification mismatch');
    if(t.entries[1].transition.items[0].changes.map(x=>x.dimension).join(',')!=='exportSha256,deploymentState')fail('transition diff mismatch');
    const seen=firstAppearance(t,'a','deploymentState');if(seen.sequence!==2||seen.change.before!=='deployment_drift'||seen.change.after!=='protected')fail('first appearance mismatch');
    const tampered=clone(t);tampered.entries[1].transition.counts.changed=99;if(!verifyTimeline(tampered).some(x=>x.includes('transition diff mismatch')))fail('tampered transition accepted');
    console.log('SHINE DEFENCE ESTATE AUDIT TIMELINE SELF-TEST: PASS append order, manifest linkage, neutral transition replay, first appearance and tamper detection');
  });
}
async function main(){
  const args=process.argv.slice(2),ti=args.indexOf('--as-of');
  if(args.includes('--self-test'))return selfTest();
  if(ti<0||!args[ti+1])fail('--as-of is required');
  const current=existsSync(timelinePath)?JSON.parse(readFileSync(timelinePath,'utf8')):null;
  const manifest=loadEstateAuditManifest(args[ti+1]),next=appendTimelineManifest({timeline:current,manifest});
  if(args.includes('--apply')){atomicWrite(timelinePath,Buffer.from(json(next)));console.log('SHINE DEFENCE ESTATE AUDIT TIMELINE: APPLIED entry '+next.entries.at(-1).sequence);return}
  console.log(JSON.stringify(next,null,2));console.log('DRY RUN: timeline not changed. Use --apply to append.');
}
main();
