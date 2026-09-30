import postgres from 'npm:postgres@3.4.9';
import {verifyGithubActionsOidc} from '../_shared/github-actions-oidc-v1.mjs';
import {bindGithubOidcOperation,oidcReplayConflict} from '../_shared/github-oidc-operation-v1.mjs';

const AUDIENCE='shine-defence-rollback-readiness';
const EXPECTED_WORKFLOW_PATH='.github/workflows/shine-defence-release-head.yml';
const EXPECTED_WORKFLOW_BRANCH='main';
const OIDC_POLICY={
  audience:AUDIENCE,
  expectedRepositoryOwner:'doug-dotcom',
  expectedRepositoryOwnerId:'225530237',
  expectedRef:'refs/heads/'+EXPECTED_WORKFLOW_BRANCH,
  expectedRefType:'branch',
  expectedRunnerEnvironment:'github-hosted',
  subjectMode:'repository-ref',
  expectedWorkflow:{path:EXPECTED_WORKFLOW_PATH,branch:EXPECTED_WORKFLOW_BRANCH},
  allowedEvents:["schedule","workflow_dispatch","push"]
};
const MAX_BODY_BYTES=64*1024;

const requireEnv=(name:string)=>{
  const value=Deno.env.get(name);
  if(!value) throw new Error('Missing required environment variable: '+name);
  return value;
};

const sql=postgres(requireEnv('SUPABASE_DB_URL'),{
  max:1,
  prepare:false,
  idle_timeout:20,
  connect_timeout:10
});

const clean=(value:unknown,max=512)=>typeof value==='string'&&value.length>0&&value.length<=max&&!/[\u0000-\u001f\u007f]/.test(value);
const sha40=(value:unknown)=>typeof value==='string'&&/^[a-f0-9]{40}$/i.test(value);
const targetId=(value:unknown)=>typeof value==='string'&&/^railway:[a-z0-9][a-z0-9-]*$/.test(value);
const repository=(value:unknown)=>typeof value==='string'&&/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(value);

const jsonResponse=(status:number,body:unknown)=>new Response(JSON.stringify(body),{
  status,
  headers:{'content-type':'application/json','cache-control':'no-store'}
});

async function verifyTargetBinding(target:string,identity:any){
  const rows=await sql`
    select
      provider,
      metadata->>'sourceRepository' as source_repository,
      metadata->>'sourceRepositoryId' as source_repository_id,
      metadata->>'sourceRepositoryOwner' as source_repository_owner,
      metadata->>'sourceRepositoryOwnerId' as source_repository_owner_id
    from foundation.defence_estate_targets
    where target_id=${target}
      and lifecycle='active'
      and required_for_estate
  `;
  const row=rows[0];
  return Boolean(
    row&&
    row.provider==='railway'&&
    String(row.source_repository??'').toLowerCase()===String(identity.repository??'').toLowerCase()&&
    String(row.source_repository_id??'')===String(identity.repositoryId??'')&&
    String(row.source_repository_owner??'')===String(identity.repositoryOwner??'')&&
    String(row.source_repository_owner_id??'')===String(identity.repositoryOwnerId??'')
  );
}

Deno.serve(async(req:Request)=>{
  try{
    if(req.method!=='POST') return jsonResponse(405,{error:'method-not-allowed'});
    const contentLength=Number(req.headers.get('content-length')||0);
    if(contentLength>MAX_BODY_BYTES) return jsonResponse(413,{error:'body-too-large'});

    const auth=req.headers.get('authorization')??'';
    if(!auth.startsWith('Bearer ')) return jsonResponse(401,{error:'missing-oidc-token'});
    const identity=await verifyGithubActionsOidc(auth.slice(7),OIDC_POLICY);

    const raw=await req.text();
    if(raw.length>MAX_BODY_BYTES) return jsonResponse(413,{error:'body-too-large'});
    const body=JSON.parse(raw||'{}');

    if(body?.action==='claim'){
      if(!targetId(body?.targetId)) return jsonResponse(400,{error:'invalid-target'});
      if(!(await verifyTargetBinding(body.targetId,identity))){
        return jsonResponse(401,{error:'rollback-oidc-source-mismatch'});
      }
      const claimBinding=await bindGithubOidcOperation({
        sql,
        identity,
        audience:AUDIENCE,
        operation:'rollback-claim',
        targetKey:String(body.targetId),
        request:body
      });
      if(oidcReplayConflict(claimBinding)){
        return jsonResponse(409,{error:'oidc-replay-conflict',binding:claimBinding});
      }
      const rows=await sql`
        select foundation.get_defence_rollback_claim_v1(${body.targetId}) as claim
      `;
      const claim=rows[0]?.claim??null;
      if(!claim) return jsonResponse(400,{error:'rollback-claim-unavailable'});
      return jsonResponse(200,{
        status:'ok',
        contract:'shine-defence/rollback-readiness-claim-response-v1',
        claim,
        oidcBinding:{status:claimBinding.status,bindingId:claimBinding.bindingId}
      });
    }

    if(body?.action!=='attest') return jsonResponse(400,{error:'unsupported-action'});
    const submission=body?.submission;
    if(
      !submission||
      submission.contract!=='shine-defence/rollback-source-attestation-v1'||
      submission.schemaVersion!=='1.0.0'||
      !targetId(submission.targetId)||
      !sha40(submission.rollbackCommitSha)||
      !sha40(submission.canonicalCommitSha)||
      typeof submission.sourceAvailable!=='boolean'||
      typeof submission.canonicalSourceAvailable!=='boolean'
    ){
      return jsonResponse(400,{error:'invalid-rollback-attestation'});
    }

    if(!(await verifyTargetBinding(submission.targetId,identity))){
      return jsonResponse(401,{error:'rollback-oidc-source-mismatch'});
    }

    const attestBinding=await bindGithubOidcOperation({
      sql,
      identity,
      audience:AUDIENCE,
      operation:'rollback-attest',
      targetKey:String(submission.targetId),
      request:body
    });
    if(oidcReplayConflict(attestBinding)){
      return jsonResponse(409,{error:'oidc-replay-conflict',binding:attestBinding});
    }

    const observedAt=new Date();
    const validUntil=new Date(observedAt.getTime()+2*60*60*1000);
    const evidenceRef=[
      'github-oidc',
      'rollback-readiness',
      identity.runId,
      identity.runAttempt,
      submission.targetId,
      String(submission.rollbackCommitSha).toLowerCase()
    ].join(':');

    const rows=await sql`
      select foundation.record_defence_rollback_source_attestation_v2(
        ${submission.targetId},
        ${identity.repository},
        ${String(submission.rollbackCommitSha).toLowerCase()},
        ${String(submission.canonicalCommitSha).toLowerCase()},
        ${submission.sourceAvailable},
        ${submission.canonicalSourceAvailable},
        ${observedAt.toISOString()}::timestamptz,
        ${validUntil.toISOString()}::timestamptz,
        ${evidenceRef},
        ${sql.json({
          collector:'shine-defence/rollback-readiness-v2',
          githubRunId:identity.runId,
          githubRunAttempt:identity.runAttempt,
          githubEvent:identity.eventName,
          githubActor:identity.actor,
          githubRepository:identity.repository,
          githubRepositoryId:identity.repositoryId,
          githubRepositoryOwner:identity.repositoryOwner,
          githubRepositoryOwnerId:identity.repositoryOwnerId,
          githubRef:identity.ref,
          githubWorkflowRef:identity.workflowRef,
          githubWorkflowSha:identity.workflowSha,
          githubRunnerEnvironment:identity.runnerEnvironment
        })}
      ) as result
    `;

    const result=rows[0]?.result??null;
    if(result?.status==='rejected'){
      return jsonResponse(400,{
        error:'rollback-attestation-rejected',
        reasonCode:result.reasonCode
      });
    }

    return jsonResponse(200,{
      status:'accepted',
      contract:'shine-defence/rollback-source-attestation-response-v1',
      result,
      oidcBinding:{status:attestBinding.status,bindingId:attestBinding.bindingId}
    });
  }catch(error){
    const message=error instanceof Error?error.message:'rollback-readiness-error';
    const authFailure=/OIDC|oidc|workflow mismatch|ref mismatch|missing-oidc|source-mismatch/.test(message);
    console.error('defence-rollback-readiness',message);
    return jsonResponse(authFailure?401:400,{
      error:authFailure?'unauthorized-rollback-readiness':'rollback-readiness-rejected'
    });
  }
});
