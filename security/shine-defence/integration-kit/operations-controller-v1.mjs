#!/usr/bin/env node
import {existsSync,readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {loadLiveQueue} from './review-queue-v1.mjs';
import {loadLiveDeploymentReport} from './deployment-observations-v1.mjs';
import {loadLiveReadiness} from './candidate-intake-readiness-v1.mjs';

export const SHINE_DEFENCE_OPERATIONS_CONTROLLER_VERSION='1.3.0';
const root=fileURLToPath(new URL('../../../',import.meta.url));
const P={candidates:'security/shine-defence/review-candidates-v1.json',ledger:'security/shine-defence/ecosystem-profile-ledger-v1.json',revocations:'security/shine-defence/revocations-v1.json',receipts:'security/shine-defence/receipts'};
const readJson=p=>JSON.parse(readFileSync(join(root,p),'utf8'));
const fail=m=>{throw new Error(m)};

const HELPERS={
  generate_checklist:'security/shine-defence/integration-kit/generate-review-checklist-v1.mjs',
  review_requirement:'security/shine-defence/integration-kit/review-workspace-v1.mjs',
  authorize_approve:'security/shine-defence/integration-kit/review-workspace-v1.mjs',
  authorize_reject:'security/shine-defence/integration-kit/review-workspace-v1.mjs',
  run_first_certification:'security/shine-defence/integration-kit/onboard-review-v1.mjs',
  run_recertification:'security/shine-defence/integration-kit/promote-review-v1.mjs',
  finalize_rejection:'security/shine-defence/integration-kit/finalize-rejection-v1.mjs'
};

function exactRevocation(app,revocations){
  return (revocations||[]).find(r=>r.appId===app.id&&r.reviewCommitSha===app.reviewCommitSha&&r.profileBlobSha===app.profileBlobSha)||null;
}
function candidateArgs(item){
  return item?.candidateId?['--candidate',item.candidateId]:[];
}
function mapPending(item){
  const helper=HELPERS[item.nextAction.id]||item.nextAction.helper||null;
  const humanRequired=Boolean(item.nextAction.humanRequired);
  let state='review_action_required';
  if(humanRequired)state='human_review_required';
  if(item.nextAction.id==='run_first_certification'||item.nextAction.id==='run_recertification')state='certification_action_ready';
  if(item.state==='blocked_invalid_checklist')state='blocked_canonical_state';
  return {
    appId:item.appId,
    repository:item.repository,
    state,
    reviewState:item.state,
    certificationState:item.reviewType==='re_certification'?'reviewed_with_pending_candidate':'uncertified_with_pending_candidate',
    nextAction:{
      id:item.nextAction.id,
      humanRequired,
      helper,
      args:helper?candidateArgs(item):[],
      description:item.nextAction.description
    },
    evidenceAssistance:item.evidenceAssistance
  };
}

export function buildOperationsReport({queueReport,ledger,candidates,revocations,receiptExists,deploymentReport={items:[]},readinessReport={items:[]}}){
  const reviewed=new Map((ledger.apps||[]).map(app=>[app.id,app]));
  const pending=new Map((queueReport.items||[]).map(item=>[item.appId,item]));
  const deployments=new Map((deploymentReport.items||[]).map(item=>[item.appId,item]));
  const readiness=new Map((readinessReport.items||[]).map(item=>[item.appId,item]));
  const histories=new Map();
  for(const c of candidates.candidates||[]){
    if(!histories.has(c.appId))histories.set(c.appId,[]);
    histories.get(c.appId).push(c);
  }
  const ids=[...new Set([...reviewed.keys(),...histories.keys(),...pending.keys(),...deployments.keys()])].sort();
  const apps=[];

  for(const appId of ids){
    if(pending.has(appId)){
      const item=mapPending(pending.get(appId));
      item.deployment=deployments.get(appId)||{state:'unobserved'};
      apps.push(item);continue
    }
    const app=reviewed.get(appId);
    const deployment=deployments.get(appId)||null;
    const history=histories.get(appId)||[];

    if(app){
      const revoked=exactRevocation(app,revocations.revocations);
      const hasReceipt=receiptExists(appId);
      if(!hasReceipt){
        apps.push({
          appId,repository:app.repo,state:'blocked_canonical_state',reviewState:'none',
          certificationState:'missing_receipt',
          deployment:deployment||{state:'unobserved'},
          nextAction:{id:'repair_canonical_receipt_state',humanRequired:false,helper:null,args:[],description:'Canonical reviewed state is missing its exact receipt. Investigate and repair deliberately; no automatic repair helper is authorized.'}
        });
      }else if(deployment){
        const ready=readiness.get(appId);
        const stateMap={protected:'protected',deployment_drift:'deployment_drift',profile_drift:'profile_drift',revoked:'revoked',needs_review:'needs_review'};
        const state=ready?.state==='candidate_intake_ready'?'candidate_intake_ready':(stateMap[deployment.state]||'needs_review');
              apps.push({
          appId,repository:app.repo,state,reviewState:'none',
          certificationState:revoked?'revoked_reviewed_release':'canonical_reviewed_release',
          revocationId:revoked?.revocationId||null,
          deployment,
          readiness:ready||null,
          nextAction:state==='candidate_intake_ready'
            ?{id:'apply_candidate_intake',humanRequired:false,helper:'security/shine-defence/integration-kit/intake-review-v1.mjs',args:['--input','<validated-candidate-intake.json>','--apply'],description:'Accepted human evidence is bound and the intake payload validates. Persist the displayed payload, then explicitly run guarded candidate intake.'}
            :state==='deployment_drift'
              ?{id:'plan_observed_release_review',humanRequired:false,helper:'security/shine-defence/integration-kit/plan-review-intake-v1.mjs',args:['--app',appId,'--json'],description:'Generate a safe candidate-intake draft from the exact observed deployment identity. Review evidence is still required before materialization.'}
            :state==='profile_drift'
              ?{id:'refresh_observed_profile_claims',humanRequired:false,helper:null,args:[],description:'The deployed Defence profile changed. Refresh profileVersion and policy claims before candidate intake can be planned safely.'}
              :state==='needs_review'
                ?{id:'investigate_deployment_proof',humanRequired:false,helper:null,args:[],description:'Deployment proof could not be verified. Investigate receipt/snapshot/observation integrity before creating review state.'}
                :state==='revoked'
                  ?{id:'intake_replacement_release',humanRequired:false,helper:'security/shine-defence/integration-kit/intake-review-v1.mjs',args:['--input','<candidate-intake.json>'],description:'The observed deployed release is revoked. Prepare a replacement release for review.'}
                  :{id:'none',humanRequired:false,helper:null,args:[],description:'Observed deployment exactly matches current Defence proof.'}
        });
      }else if(revoked){
        apps.push({
          appId,repository:app.repo,state:'reviewed_release_revoked',reviewState:'none',
          certificationState:'revoked_reviewed_release',
          revocationId:revoked.revocationId,
          deployment:{state:'unobserved'},
          nextAction:{id:'record_deployment_observation',humanRequired:false,helper:'security/shine-defence/integration-kit/record-deployment-observation-v1.mjs',args:['--input','<deployment-observation.json>'],description:'The canonical reviewed release is revoked, but no current deployment identity is observed. Record deployment identity before drawing a deployment-status conclusion.'}
        });
      }else{
        apps.push({
          appId,repository:app.repo,state:'canonical_reviewed_idle',reviewState:'none',
          certificationState:'canonical_reviewed_release',
          deployment:{state:'unobserved'},
          nextAction:{id:'record_deployment_observation',humanRequired:false,helper:'security/shine-defence/integration-kit/record-deployment-observation-v1.mjs',args:['--input','<deployment-observation.json>'],description:'Canonical review is current, but no deployment identity has been observed yet.'}
        });
      }
      continue;
    }

    const repository=history.at(-1)?.repository||null;
    apps.push({
      appId,repository,state:'uncertified_idle',reviewState:'none',certificationState:'uncertified',deployment:deployment||{state:'unobserved'},
      nextAction:{id:'intake_candidate',humanRequired:false,helper:'security/shine-defence/integration-kit/intake-review-v1.mjs',args:['--input','<candidate-intake.json>'],description:'Submit a new exact release candidate when the app is ready for review.'}
    });
  }

  const counts={};
  let humanAttention=0,actionable=0,blocked=0;
  for(const app of apps){
    counts[app.state]=(counts[app.state]||0)+1;
    if(app.nextAction.humanRequired)humanAttention++;
    if(app.nextAction.id!=='none')actionable++;
    if(app.state==='blocked_canonical_state')blocked++;
  }
  return {controller:'shine-defence/operations-controller-v1',version:'1.0.0',apps:apps.length,actionable,humanAttentionRequired:humanAttention,blocked,states:counts,items:apps};
}

export function loadLiveOperations(){
  return buildOperationsReport({
    queueReport:loadLiveQueue(),
    ledger:readJson(P.ledger),
    candidates:readJson(P.candidates),
    revocations:readJson(P.revocations),
    deploymentReport:loadLiveDeploymentReport(),
    readinessReport:loadLiveReadiness(),
    receiptExists:appId=>existsSync(join(root,P.receipts,appId+'.json'))
  });
}

function printHuman(report){
  console.log('SHINE DEFENCE OPERATIONS CONTROLLER');
  console.log('apps: '+report.apps);
  console.log('actionable: '+report.actionable);
  console.log('human attention required: '+report.humanAttentionRequired);
  console.log('blocked: '+report.blocked);
  for(const item of report.items){
    console.log('');
    console.log(item.appId+(item.repository?' / '+item.repository:''));
    console.log('  state: '+item.state);
    console.log('  certification: '+item.certificationState);
    if(item.reviewState!=='none')console.log('  review: '+item.reviewState);
    console.log('  deployment: '+(item.deployment?.state||'unobserved'));
    console.log('  next: '+item.nextAction.id);
    console.log('  '+item.nextAction.description);
    if(item.nextAction.helper)console.log('  helper: '+item.nextAction.helper+' '+item.nextAction.args.join(' '));
    if(item.nextAction.humanRequired)console.log('  HUMAN DECISION REQUIRED');
  }
}
function parseArgs(argv){
  const r={json:false};
  for(const a of argv){
    if(a==='--json'){r.json=true;continue}
    if(a==='--self-test'){r.selfTest=true;continue}
    if(a==='--help'||a==='-h'){r.help=true;continue}
    fail('unknown argument '+a);
  }
  return r;
}
function usage(){console.log(`Shine Defence operations controller v${SHINE_DEFENCE_OPERATIONS_CONTROLLER_VERSION}

Usage:
  node security/shine-defence/integration-kit/operations-controller-v1.mjs [--json]

Read-only only: classifies every known app and recommends the exact guarded helper for the
next Core workflow step. It never executes a mutating helper and does not infer live deployment state.`)}

function selfTest(){
  const q={items:[
    {appId:'new',repository:'owner/new',candidateId:'new-a',reviewType:'first_certification',state:'needs_checklist',nextAction:{id:'generate_checklist',humanRequired:false,description:'Generate.'},evidenceAssistance:{status:'missing'}},
    {appId:'human',repository:'owner/human',candidateId:'human-b',reviewType:'re_certification',state:'review_in_progress',nextAction:{id:'review_requirement',humanRequired:true,description:'Review.'},evidenceAssistance:{status:'valid'}},
    {appId:'ready',repository:'owner/ready',candidateId:'ready-c',reviewType:'re_certification',state:'approved_ready_for_recertification',nextAction:{id:'run_recertification',humanRequired:false,description:'Promote.'},evidenceAssistance:{status:'valid'}}
  ]};
  const ledger={apps:[
    {id:'human',repo:'owner/human',reviewCommitSha:'1'.repeat(40),profileBlobSha:'a'.repeat(40)},
    {id:'ready',repo:'owner/ready',reviewCommitSha:'2'.repeat(40),profileBlobSha:'b'.repeat(40)},
    {id:'idle',repo:'owner/idle',reviewCommitSha:'3'.repeat(40),profileBlobSha:'c'.repeat(40)},
    {id:'revoked',repo:'owner/revoked',reviewCommitSha:'4'.repeat(40),profileBlobSha:'d'.repeat(40)},
    {id:'broken',repo:'owner/broken',reviewCommitSha:'5'.repeat(40),profileBlobSha:'e'.repeat(40)},
    {id:'drift',repo:'owner/drift',reviewCommitSha:'6'.repeat(40),profileBlobSha:'f'.repeat(40)}
  ]};
  const candidates={candidates:[
    {appId:'new',repository:'owner/new',status:'pending_review'},
    {appId:'human',repository:'owner/human',status:'pending_review'},
    {appId:'ready',repository:'owner/ready',status:'pending_review'},
    {appId:'old-only',repository:'owner/old-only',status:'dismissed'}
  ]};
  const revocations={revocations:[{revocationId:'r1',appId:'revoked',reviewCommitSha:'4'.repeat(40),profileBlobSha:'d'.repeat(40)}]};
  const receipts=new Set(['human','ready','idle','revoked','drift']);
  const deploymentReport={items:[{appId:'idle',state:'protected'},{appId:'revoked',state:'revoked'},{appId:'ready',state:'deployment_drift'},{appId:'drift',state:'deployment_drift'}]};
  const readinessReport={items:[{appId:'drift',state:'candidate_intake_ready',candidateId:'drift-123'}]};
  const report=buildOperationsReport({queueReport:q,ledger,candidates,revocations,deploymentReport,readinessReport,receiptExists:id=>receipts.has(id)});
  const byId=new Map(report.items.map(x=>[x.appId,x]));
  if(byId.get('new').nextAction.helper!=='security/shine-defence/integration-kit/generate-review-checklist-v1.mjs')fail('self-test: checklist routing');
  if(byId.get('human').state!=='human_review_required'||!byId.get('human').nextAction.humanRequired)fail('self-test: human boundary');
  if(byId.get('ready').nextAction.helper!=='security/shine-defence/integration-kit/promote-review-v1.mjs')fail('self-test: recert routing');
  if(byId.get('idle').state!=='protected'||byId.get('idle').nextAction.helper!==null)fail('self-test: protected observed state');
  if(byId.get('revoked').state!=='revoked'||byId.get('revoked').nextAction.helper!=='security/shine-defence/integration-kit/intake-review-v1.mjs')fail('self-test: observed revoked routing');
  if(byId.get('broken').state!=='blocked_canonical_state'||byId.get('broken').nextAction.helper!==null)fail('self-test: missing receipt must fail closed');
  if(byId.get('drift').state!=='candidate_intake_ready'||byId.get('drift').nextAction.helper!=='security/shine-defence/integration-kit/intake-review-v1.mjs')fail('self-test: accepted evidence must route to explicit candidate intake');
  if(byId.get('old-only').state!=='uncertified_idle')fail('self-test: uncertified history');
  if(report.items.map(x=>x.appId).join(',')!=='broken,drift,human,idle,new,old-only,ready,revoked')fail('self-test: deterministic ordering');
  console.log('SHINE DEFENCE OPERATIONS CONTROLLER SELF-TEST: PASS review routing, human boundary, accepted-evidence readiness, revocation and blocked states');
}
function main(){const a=parseArgs(process.argv.slice(2));if(a.help){usage();return}if(a.selfTest){selfTest();return}const r=loadLiveOperations();if(a.json)console.log(JSON.stringify(r,null,2));else printHuman(r)}
main();
