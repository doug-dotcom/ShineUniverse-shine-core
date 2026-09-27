#!/usr/bin/env node
import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildIntakePlan} from './plan-review-intake-v1.mjs';
import {loadLiveDeploymentReport} from './deployment-observations-v1.mjs';

export const SHINE_DEFENCE_REVIEW_EVIDENCE_PACK_VERSION='1.0.0';
const root=fileURLToPath(new URL('../../../',import.meta.url));
const P={ledger:'security/shine-defence/ecosystem-profile-ledger-v1.json',candidates:'security/shine-defence/review-candidates-v1.json'};
const readJson=p=>JSON.parse(readFileSync(join(root,p),'utf8'));
const fail=m=>{throw new Error(m)};
const SHA=/^[a-f0-9]{40}$/;

function focus(filename){
  const f=filename.toLowerCase();
  if(/(^|\/)(auth|security|middleware|permission|session|token|crypto|secret|vault)(\/|[._-])/.test(f)||/(auth|security|csrf|permission|session|token|credential|secret)/.test(f))return 'security_or_auth';
  if(/(^|\/)(api|server|backend|routes?|functions?)(\/|[._-])/.test(f)||/(route\.|server\.|handler\.)/.test(f))return 'api_or_server';
  if(/(^|\/)(supabase|migrations?|database|db|sql)(\/|[._-])/.test(f)||/\.sql$/.test(f))return 'database_or_migration';
  if(/(^|\/)(package(-lock)?\.json|requirements.*\.txt|pyproject\.toml|deno\.json|cargo\.toml|go\.mod)$/.test(f)||/(package\.json|lock|requirements|pyproject)/.test(f))return 'dependency_or_build';
  if(/(^|\/)(\.github|railway\.toml|dockerfile|docker-compose|vercel\.json)/.test(f)||/(deploy|workflow|ci\.yml|ci\.yaml)/.test(f))return 'ci_or_deployment';
  if(/(^|\/)(tests?|__tests__)(\/|[._-])/.test(f)||/(\.test\.|\.spec\.)/.test(f))return 'tests';
  return 'other';
}

export function buildEvidencePack({planItem,reviewedApp,compare}){
  if(planItem?.state!=='needs_review_evidence')fail('evidence packs require a draftable intake-plan item');
  if(!reviewedApp||reviewedApp.id!==planItem.appId)fail('reviewed app binding mismatch');
  if(compare.repository_full_name!==planItem.repository)fail('compare repository mismatch');
  if(compare.base!==reviewedApp.reviewCommitSha||compare.head!==planItem.intakeDraft.releaseCommitSha)fail('compare commit binding mismatch');
  if(compare.status!=='ahead'||compare.behind_by!==0)fail('compare must be a forward-only release advance');
  if(!SHA.test(compare.base||'')||!SHA.test(compare.head||''))fail('invalid compare SHA');
  const files=(compare.files||[]).slice(0,300).map(file=>({
    filename:file.filename,
    status:file.status||null,
    additions:Number.isInteger(file.additions)?file.additions:null,
    deletions:Number.isInteger(file.deletions)?file.deletions:null,
    changes:Number.isInteger(file.changes)?file.changes:null,
    previousFilename:file.previous_filename||null,
    reviewFocus:focus(file.filename)
  }));
  if(files.some(f=>typeof f.filename!=='string'||f.filename.length>512))fail('invalid changed-file path');
  if(files.reduce((n,f)=>n+f.filename.length,0)>60000)fail('changed-file path text exceeds pack bound');
  const counts={};for(const f of files)counts[f.reviewFocus]=(counts[f.reviewFocus]||0)+1;
  const additions=files.reduce((n,f)=>n+(f.additions||0),0),deletions=files.reduce((n,f)=>n+(f.deletions||0),0);
  return {
    artifact:'shine-defence/review-evidence-pack-v1',
    version:'1.0.0',
    appId:planItem.appId,
    repository:planItem.repository,
    reviewedCommitSha:reviewedApp.reviewCommitSha,
    observedCommitSha:planItem.intakeDraft.releaseCommitSha,
    deploymentObservationId:planItem.deploymentObservationId,
    deploymentObservedAt:planItem.deploymentObservedAt,
    compare:{
      status:compare.status,
      aheadBy:compare.ahead_by,
      behindBy:compare.behind_by,
      totalCommits:compare.total_commits,
      changedFiles:files.length,
      additions,
      deletions,
      truncated:(compare.files||[]).length>300
    },
    reviewFocus:{counts,files},
    proposedEvidence:{
      status:'unreviewed',
      source:'github',
      kind:'security_diff_review',
      reference:planItem.repository+'@'+reviewedApp.reviewCommitSha+'...'+planItem.intakeDraft.releaseCommitSha,
      summary:'UNREVIEWED GitHub compare pack: '+String(compare.total_commits)+' commits, '+String(files.length)+' changed files, +'+String(additions)+'/-'+String(deletions)+'. Human review required before candidate intake.'
    }
  };
}

function githubCompare(repo,base,head){
  const endpoint='repos/'+repo+'/compare/'+base+'...'+head;
  const raw=spawnSync('gh',['api',endpoint],{cwd:root,encoding:'utf8'});
  if(raw.status!==0)fail('GitHub compare failed for '+repo+': '+String(raw.stderr||raw.stdout).trim());
  let value;try{value=JSON.parse(raw.stdout)}catch{fail('GitHub compare returned invalid JSON for '+repo)}
  return {
    repository_full_name:repo,base,head,status:value.status||null,ahead_by:value.ahead_by??null,behind_by:value.behind_by??null,total_commits:value.total_commits??null,
    files:(value.files||[]).map(f=>({filename:f.filename,status:f.status,additions:f.additions,deletions:f.deletions,changes:f.changes,previous_filename:f.previous_filename||null}))
  };
}

export function buildLiveEvidencePacks(){
  const ledger=readJson(P.ledger),candidates=readJson(P.candidates);
  const plan=buildIntakePlan({deploymentReport:loadLiveDeploymentReport(),ledger,candidates});
  const reviewed=new Map(ledger.apps.map(a=>[a.id,a]));
  const packs=[];
  for(const item of plan.items.filter(i=>i.state==='needs_review_evidence')){
    const app=reviewed.get(item.appId);
    packs.push(buildEvidencePack({planItem:item,reviewedApp:app,compare:githubCompare(item.repository,app.reviewCommitSha,item.intakeDraft.releaseCommitSha)}));
  }
  return {report:'shine-defence/review-evidence-packs-v1',version:'1.0.0',packs:packs.length,items:packs};
}

function selfTest(){
  const planItem={appId:'app',repository:'owner/app',state:'needs_review_evidence',deploymentObservationId:'obs-1',deploymentObservedAt:'2026-09-27T01:00:00.000Z',intakeDraft:{releaseCommitSha:'b'.repeat(40)}};
  const reviewedApp={id:'app',reviewCommitSha:'a'.repeat(40)};
  const compare={repository_full_name:'owner/app',base:'a'.repeat(40),head:'b'.repeat(40),status:'ahead',ahead_by:3,behind_by:0,total_commits:3,files:[
    {filename:'app/api/session/route.ts',status:'modified',additions:10,deletions:2,changes:12},
    {filename:'supabase/migrations/001.sql',status:'added',additions:20,deletions:0,changes:20},
    {filename:'tests/session.test.ts',status:'added',additions:30,deletions:0,changes:30}
  ]};
  const pack=buildEvidencePack({planItem,reviewedApp,compare});
  if(pack.compare.changedFiles!==3||pack.reviewFocus.counts.api_or_server!==1||pack.reviewFocus.counts.database_or_migration!==1||pack.reviewFocus.counts.tests!==1)fail('self-test: focus/count mismatch');
  if(pack.proposedEvidence.status!=='unreviewed'||!pack.proposedEvidence.summary.startsWith('UNREVIEWED'))fail('self-test: pack must remain unreviewed');
  let blocked=false;try{buildEvidencePack({planItem,reviewedApp,compare:{...compare,status:'diverged',behind_by:1}})}catch{blocked=true}if(!blocked)fail('self-test: divergent compare accepted');
  console.log('SHINE DEFENCE REVIEW EVIDENCE PACK SELF-TEST: PASS bounded metadata, review focus, unreviewed gate and divergent fail-closed');
}

function main(){if(process.argv.includes('--self-test'))return selfTest();const r=buildLiveEvidencePacks();console.log(JSON.stringify(r,null,2))}
main();
