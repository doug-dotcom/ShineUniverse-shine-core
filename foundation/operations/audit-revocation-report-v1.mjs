import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
import {spawnSync} from 'node:child_process';

export function assessOperations(snapshot,{now=Date.now(),maxAgeMs=600000}={}) {
 const fail=reason=>({state:'unknown',reason,actions:[],integrationAccepted:false});
 if(snapshot?.contract!=='shine-foundation/audit-revocation-operations-v1') return fail('invalid-snapshot');
 const at=Date.parse(snapshot.observedAt);
 if(!Number.isFinite(now)||!Number.isFinite(at)||at>now+30000||now-at>maxAgeMs) return fail('stale-or-invalid-observation');
 const d=snapshot.deployment;
 if(!d||!/^\d+$/.test(d.runtime_version??'')||!/^[a-f0-9]{64}$/.test(d.artifact_sha256??'')) return fail('deployment-unverified');
 if(!Array.isArray(snapshot.audit)||!Array.isArray(snapshot.revocations)) return fail('incomplete-snapshot');
 const scopes=new Set();
 for(const a of snapshot.audit) {
  if(!['current','historical'].includes(a.scope)||scopes.has(a.scope)||!['fresh_complete','broken','stale_open','pending'].every(k=>Number.isSafeInteger(a[k])&&a[k]>=0)||!Array.isArray(a.issues)||a.issues.length!==a.broken+a.stale_open) return fail('invalid-audit-counts');
  scopes.add(a.scope);
 }
 for(const r of snapshot.revocations) if(!Number.isSafeInteger(r.pendingCount)||r.pendingCount<0||!['current','pending','stale'].includes(r.freshness)||typeof r.appId!=='string') return fail('invalid-revocation-evidence');
 const current=snapshot.audit.find(a=>a.scope==='current');
 const historic=snapshot.audit.find(a=>a.scope==='historical');
 const currentState=!current?'unknown':current.broken?'fail':current.stale_open?'degraded':current.fresh_complete?'pass':'unknown';
 const actions=[];
 for(const a of snapshot.audit) for(const issue of a.issues) actions.push({kind:issue.kind,scope:a.scope,traceId:issue.id,action:issue.kind==='broken-chain'?'Investigate chain integrity; retain original events.':'Investigate original execution evidence; record outcome only if independently recoverable. Never replay the domain operation to repair its audit.'});
 for(const r of snapshot.revocations) if(r.pendingCount) actions.push({kind:'revocation-pending',appId:r.appId,count:r.pendingCount,action:'Consumer must fetch its scoped revocation feed, invalidate access, then acknowledge the delivered sequence. Never advance its checkpoint on its behalf.'});
 const historicIssues=Boolean(historic&&(historic.broken||historic.stale_open));
 const revocationState=snapshot.revocations.length===0?'unknown':snapshot.revocations.some(r=>r.pendingCount>0)?'degraded':'pass';
 const state=currentState==='fail'||historic?.broken?'fail':currentState==='unknown'||revocationState==='unknown'?'unknown':currentState==='degraded'||historicIssues||revocationState==='degraded'?'degraded':'pass';
 return {state,currentReleaseAudit:currentState,historicalIssues:historicIssues,revocationState,observedAt:snapshot.observedAt,runtimeVersion:d.runtime_version,actions,integrationAccepted:false,meaning:'Operational evidence only. Empty revocation backlog does not prove a consumer enforces withdrawal.'};
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
 try {
  let snapshot;
  if(process.argv[2]==='--snapshot'&&process.argv.length===4) snapshot=JSON.parse(readFileSync(process.argv[3],'utf8'));
  else if(process.argv.length===2) {
   // libpq reads PG* credentials. They never enter command arguments or output.
   const sql=readFileSync(new URL('./audit-revocation-snapshot-v1.sql',import.meta.url),'utf8');
   const r=spawnSync('psql',['-X','-A','-t','-q','-v','ON_ERROR_STOP=1'],{input:sql,encoding:'utf8',timeout:30000,maxBuffer:4*1024*1024});
   if(r.error||r.status!==0) throw Error('Protected database snapshot unavailable. Check operator connection and SELECT permissions.');
   snapshot=JSON.parse(r.stdout.trim());
  } else throw Error('Usage: node audit-revocation-report-v1.mjs [--snapshot FILE]');
  const report=assessOperations(snapshot);process.stdout.write(JSON.stringify(report,null,2)+'\n');
  process.exitCode=report.state==='pass'?0:2;
 } catch { process.stderr.write('Audit/revocation report unavailable; no authority or operation was changed.\n');process.exitCode=1; }
}
