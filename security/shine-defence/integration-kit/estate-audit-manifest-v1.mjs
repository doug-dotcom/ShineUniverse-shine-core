#!/usr/bin/env node
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {loadAuditExport} from './audit-export-v1.mjs';

export const SHINE_DEFENCE_ESTATE_AUDIT_MANIFEST_VERSION='1.0.1';
const root=fileURLToPath(new URL('../../../',import.meta.url));
const ledgerPath='security/shine-defence/ecosystem-profile-ledger-v1.json';
const readJson=p=>JSON.parse(readFileSync(join(root,p),'utf8'));
export const estateManifestSha=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
const fail=m=>{throw new Error(m)};

export function buildEstateAuditManifest({apps,asOf,exportForApp}){
  if(!Number.isFinite(Date.parse(asOf)))fail('estate audit manifest asOf must be an ISO timestamp');
  const ids=new Set(),entries=[];
  for(const app of apps){
    if(ids.has(app.id))fail('duplicate reviewed app id '+app.id);ids.add(app.id);
    const audit=exportForApp(app.id);
    if(audit.exportMetadata.appId!==app.id||audit.exportMetadata.repository!==app.repo||audit.exportMetadata.asOf!==asOf)fail('per-app audit export binding mismatch for '+app.id);
    if(audit.certificationIdentity.reviewCommitSha!==app.reviewCommitSha)fail('reviewed commit mismatch for '+app.id);
    entries.push({
      appId:app.id,repository:app.repo,exportSha256:audit.exportSha256,
      reviewCommitSha:audit.certificationIdentity.reviewCommitSha,
      observedReleaseCommitSha:audit.commandCentre.deployment.releaseCommitSha,
      deploymentState:audit.commandCentre.deployment.state,
      checkpointIntegrityState:audit.commandCentre.checkpointIntegrity?.state||'not_applicable'
    });
  }
  entries.sort((a,b)=>a.appId.localeCompare(b.appId));
  const body={
    artifact:'shine-defence/estate-audit-manifest-v1',version:'1.0.0',asOf,
    reviewedApps:entries.length,entries,
    provenance:{reviewedLedger:ledgerPath,auditExportContract:'security/shine-defence/audit-export-v1.json'}
  };
  return {...body,manifestSha256:estateManifestSha(body)};
}
export function loadEstateAuditManifest(asOf){
  const ledger=readJson(ledgerPath);
  return buildEstateAuditManifest({apps:ledger.apps,asOf,exportForApp:appId=>loadAuditExport({appId,asOf})});
}
function selfTest(){
  const apps=[
    {id:'b',repo:'o/b',reviewCommitSha:'b'.repeat(40)},
    {id:'a',repo:'o/a',reviewCommitSha:'a'.repeat(40)}
  ];
  const exports={
    a:{exportMetadata:{appId:'a',repository:'o/a',asOf:'2026-09-27T08:00:00.000Z'},exportSha256:'1'.repeat(64),certificationIdentity:{reviewCommitSha:'a'.repeat(40)},commandCentre:{deployment:{releaseCommitSha:'a'.repeat(40),state:'protected'},checkpointIntegrity:{state:'not_applicable'}}},
    b:{exportMetadata:{appId:'b',repository:'o/b',asOf:'2026-09-27T08:00:00.000Z'},exportSha256:'2'.repeat(64),certificationIdentity:{reviewCommitSha:'b'.repeat(40)},commandCentre:{deployment:{releaseCommitSha:'c'.repeat(40),state:'deployment_drift'},checkpointIntegrity:{state:'verified'}}}
  };
  const make=()=>buildEstateAuditManifest({apps,asOf:'2026-09-27T08:00:00.000Z',exportForApp:id=>exports[id]});
  const x=make(),y=make();
  if(x.entries.map(e=>e.appId).join(',')!=='a,b'||x.reviewedApps!==2)fail('manifest ordering/count mismatch');
  if(JSON.stringify(x)!==JSON.stringify(y)||x.manifestSha256!==y.manifestSha256)fail('manifest is not deterministic');
  const changed=JSON.parse(JSON.stringify(exports));changed.b.exportSha256='3'.repeat(64);
  const z=buildEstateAuditManifest({apps,asOf:'2026-09-27T08:00:00.000Z',exportForApp:id=>changed[id]});
  if(z.manifestSha256===x.manifestSha256)fail('per-app export change did not change estate manifest hash');
  console.log('SHINE DEFENCE ESTATE AUDIT MANIFEST SELF-TEST: PASS complete scope, deterministic ordering/hash and per-app change sensitivity');
}
function main(){
  const args=process.argv.slice(2),ti=args.indexOf('--as-of');
  if(args.includes('--self-test'))return selfTest();
  if(ti<0||!args[ti+1])fail('--as-of is required for deterministic estate audit manifest');
  console.log(JSON.stringify(loadEstateAuditManifest(args[ti+1]),null,2));
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)main();
