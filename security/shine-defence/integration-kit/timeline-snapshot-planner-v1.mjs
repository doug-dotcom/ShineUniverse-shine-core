#!/usr/bin/env node
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {loadEstateAuditManifest} from './estate-audit-manifest-v1.mjs';
import {diffEstateManifests,verifyManifest} from './estate-manifest-diff-v1.mjs';
import {verifyTimeline} from './estate-audit-timeline-v1.mjs';

export const SHINE_DEFENCE_TIMELINE_SNAPSHOT_PLANNER_VERSION='1.0.0';
const root=fileURLToPath(new URL('../../../',import.meta.url));
const timelinePath=join(root,'security/shine-defence/estate-audit-timeline.json');
const MATERIAL=new Set(['repository','reviewCommitSha','observedReleaseCommitSha','deploymentState','checkpointIntegrityState']);
const fail=m=>{throw new Error(m)};

export function buildSnapshotPlan({timeline,candidateManifest}){
  const tf=verifyTimeline(timeline);if(tf.length)fail('timeline invalid: '+tf.join('; '));
  if(!timeline.entries.length)fail('timeline has no baseline');
  const mf=verifyManifest(candidateManifest);if(mf.length)fail('candidate manifest invalid: '+mf.join('; '));
  const latest=timeline.entries.at(-1).manifest;
  if(Date.parse(candidateManifest.asOf)<=Date.parse(latest.asOf))fail('candidate manifest asOf must be later than latest timeline entry');
  const diff=diffEstateManifests({before:latest,after:candidateManifest});
  const materialChanges=[],snapshotHashChanges=[];
  for(const item of diff.items){
    if(item.status==='added'||item.status==='removed'){
      materialChanges.push({appId:item.appId,kind:item.status,changes:[]});continue;
    }
    if(item.status!=='changed')continue;
    const material=item.changes.filter(c=>MATERIAL.has(c.dimension));
    const hashes=item.changes.filter(c=>c.dimension==='exportSha256');
    if(material.length)materialChanges.push({appId:item.appId,kind:'changed',changes:material});
    if(hashes.length)snapshotHashChanges.push({appId:item.appId,changes:hashes});
  }
  const state=materialChanges.length?'material_change':snapshotHashChanges.length?'snapshot_hash_only':'no_change';
  return {
    report:'shine-defence/timeline-snapshot-planner-v1',version:'1.0.0',state,
    latest:{sequence:timeline.entries.at(-1).sequence,asOf:latest.asOf,manifestSha256:latest.manifestSha256},
    candidate:{asOf:candidateManifest.asOf,manifestSha256:candidateManifest.manifestSha256},
    counts:{materialApps:materialChanges.length,snapshotHashOnlyApps:snapshotHashChanges.filter(x=>!materialChanges.some(m=>m.appId===x.appId)).length},
    materialChanges,snapshotHashChanges,canonicalDiff:diff,
    nextAction:state==='material_change'
      ?{id:'append_timeline_snapshot',humanRequired:true,description:'Review this neutral change set, then explicitly append the candidate manifest with the Estate Audit Timeline --apply action if this snapshot should become persistent history.'}
      :{id:'none',humanRequired:false,description:state==='snapshot_hash_only'?'No material manifest identity change is exposed; only time-sensitive per-app audit hashes changed.':'No manifest dimensions changed.'}
  };
}
export function loadLiveSnapshotPlan(asOf){
  const timeline=JSON.parse(readFileSync(timelinePath,'utf8'));
  return buildSnapshotPlan({timeline,candidateManifest:loadEstateAuditManifest(asOf)});
}
function selfTest(){
  const makeManifest=async(asOf,opts={})=>{
    const {estateManifestSha}=await import('./estate-audit-manifest-v1.mjs');
    const e={appId:'a',repository:'o/a',exportSha256:(opts.hash||'1').repeat(64),reviewCommitSha:'a'.repeat(40),observedReleaseCommitSha:(opts.release||'b').repeat(40),deploymentState:opts.state||'deployment_drift',checkpointIntegrityState:opts.checkpoint||'not_applicable'};
    const body={artifact:'shine-defence/estate-audit-manifest-v1',version:'1.0.0',asOf,reviewedApps:1,entries:[e],provenance:{reviewedLedger:'ledger',auditExportContract:'audit'}};
    return {...body,manifestSha256:estateManifestSha(body)};
  };
  return Promise.all([
    makeManifest('2026-09-27T08:00:00.000Z'),
    makeManifest('2026-09-27T09:00:00.000Z',{hash:'2'}),
    makeManifest('2026-09-27T10:00:00.000Z',{hash:'3',state:'protected'})
  ]).then(([base,hashOnly,material])=>{
    const timeline={ledger:'shine-defence/estate-audit-timeline-v1',version:'1.0.0',entries:[{sequence:1,recordedAt:base.asOf,previousManifestSha256:null,manifest:base,transition:null}]};
    const a=buildSnapshotPlan({timeline,candidateManifest:hashOnly});if(a.state!=='snapshot_hash_only'||a.counts.materialApps!==0||a.nextAction.id!=='none')fail('hash-only plan mismatch');
    const b=buildSnapshotPlan({timeline,candidateManifest:material});if(b.state!=='material_change'||b.materialChanges[0].changes[0].dimension!=='deploymentState'||b.nextAction.id!=='append_timeline_snapshot')fail('material plan mismatch');
    console.log('SHINE DEFENCE TIMELINE SNAPSHOT PLANNER SELF-TEST: PASS material-vs-temporal hash separation, neutral diff retention and explicit append boundary');
  });
}
async function main(){
  const args=process.argv.slice(2),ti=args.indexOf('--as-of');
  if(args.includes('--self-test'))return selfTest();
  if(ti<0||!args[ti+1])fail('--as-of is required');
  console.log(JSON.stringify(loadLiveSnapshotPlan(args[ti+1]),null,2));
}
main();
