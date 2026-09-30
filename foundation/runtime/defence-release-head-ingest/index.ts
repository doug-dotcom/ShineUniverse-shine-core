import postgres from 'npm:postgres@3.4.9';
import {verifyGithubActionsOidc} from '../_shared/github-actions-oidc-v1.mjs';
import {bindGithubOidcOperation,oidcReplayConflict} from '../_shared/github-oidc-operation-v1.mjs';

const AUDIENCE='shine-defence-release-head';
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
const MAX_BODY_BYTES=96*1024;
const MAX_OBSERVATIONS=50;

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

Deno.serve(async(req:Request)=>{
  try{
    if(req.method!=='POST') return jsonResponse(405,{error:'method-not-allowed'});
    const length=Number(req.headers.get('content-length')||0);
    if(length>MAX_BODY_BYTES) return jsonResponse(413,{error:'body-too-large'});

    const auth=req.headers.get('authorization')??'';
    if(!auth.startsWith('Bearer ')) return jsonResponse(401,{error:'missing-oidc-token'});
    const identity=await verifyGithubActionsOidc(auth.slice(7),OIDC_POLICY);

    const raw=await req.text();
    if(raw.length>MAX_BODY_BYTES) return jsonResponse(413,{error:'body-too-large'});
    const body=JSON.parse(raw||'{}');

    if(body?.contract!=='shine-defence/release-head-snapshot-v1'||body?.schemaVersion!=='1.0.0'){
      return jsonResponse(400,{error:'unsupported-release-head-snapshot'});
    }
    if(!Array.isArray(body.observations)||body.observations.length!==1){
      return jsonResponse(400,{error:'invalid-observation-count'});
    }

    const observedAt=new Date();
    const validUntil=new Date(observedAt.getTime()+24*60*60*1000);
    let accepted=0;

    for(const observation of body.observations){
      const targetRows=await sql`
        select
          provider,
          metadata->>'sourceRepository' as source_repository,
          metadata->>'sourceRepositoryId' as source_repository_id,
          metadata->>'sourceRepositoryOwner' as source_repository_owner,
          metadata->>'sourceRepositoryOwnerId' as source_repository_owner_id,
          metadata->>'sourceBranch' as source_branch
        from foundation.defence_estate_targets
        where target_id=${observation?.targetId}
          and lifecycle='active'
      `;
      const target=targetRows[0];
      if(!target||target.provider!=='railway'){
        return jsonResponse(400,{error:'release-head-target-not-allowed'});
      }

      if(
        String(identity.repository).toLowerCase()!==String(target.source_repository??'').toLowerCase()||
        String(identity.repositoryId)!==String(target.source_repository_id??'')||
        String(identity.repositoryOwner)!==String(target.source_repository_owner??'')||
        String(identity.repositoryOwnerId)!==String(target.source_repository_owner_id??'')||
        String(observation?.repository??'').toLowerCase()!==String(identity.repository).toLowerCase()||
        String(observation?.branch??'')!==String(target.source_branch??'')
      ){
        return jsonResponse(401,{error:'release-head-oidc-source-mismatch'});
      }

      if(
        !targetId(observation?.targetId)||
        !repository(observation?.repository)||
        !clean(observation?.branch,200)||
        !sha40(observation?.headSha)||
        !clean(observation?.headCommittedAt,64)||
        Number.isNaN(Date.parse(observation.headCommittedAt))||
        typeof observation?.deploymentRelevant!=='boolean'||
        !Number.isInteger(observation?.changedFileCount)||
        observation.changedFileCount<0||
        observation.changedFileCount>10000
      ){
        return jsonResponse(400,{error:'invalid-release-head-observation'});
      }

      const oidcBinding=await bindGithubOidcOperation({
        sql,
        identity,
        audience:AUDIENCE,
        operation:'release-head-snapshot',
        targetKey:String(observation.targetId),
        request:body
      });
      if(oidcReplayConflict(oidcBinding)){
        return jsonResponse(409,{error:'oidc-replay-conflict',binding:oidcBinding});
      }

      const evidenceRef=[
        'github-oidc',
        'release-head',
        identity.runId,
        identity.runAttempt,
        observation.targetId,
        String(observation.headSha).toLowerCase()
      ].join(':');

      const rows=await sql`
        select foundation.record_defence_release_source_head_v1(
          ${observation.targetId},
          ${observation.repository},
          ${observation.branch},
          ${String(observation.headSha).toLowerCase()},
          ${new Date(observation.headCommittedAt).toISOString()}::timestamptz,
          ${observedAt.toISOString()}::timestamptz,
          ${validUntil.toISOString()}::timestamptz,
          ${evidenceRef},
          ${sql.json({
            collector:'shine-defence/release-source-watch-v1',
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
            githubRunnerEnvironment:identity.runnerEnvironment,
            deploymentRelevant:observation.deploymentRelevant,
            changedFileCount:observation.changedFileCount
          })}
        ) as result
      `;

      if(rows[0]?.result?.status==='rejected'){
        return jsonResponse(400,{
          error:'release-head-observation-rejected',
          targetId:observation.targetId,
          reasonCode:rows[0].result.reasonCode
        });
      }
      accepted++;
    }

    const sentinelRows=await sql`
      select foundation.run_defence_release_source_head_sentinel_v1(now()) as sentinel
    `;

    return jsonResponse(200,{
      status:'accepted',
      contract:'shine-defence/release-head-ingest-v1',
      accepted,
      observedAt:observedAt.toISOString(),
      validUntil:validUntil.toISOString(),
      sentinel:sentinelRows[0]?.sentinel??null
    });
  }catch(error){
    const message=error instanceof Error?error.message:'release-head-ingest-error';
    const authFailure=/OIDC|oidc|repository mismatch|ref mismatch|workflow mismatch|event not allowed|missing-oidc/.test(message);
    console.error('defence-release-head-ingest',message);
    return jsonResponse(authFailure?401:400,{
      error:authFailure?'unauthorized-release-head-ingest':'release-head-ingest-rejected'
    });
  }
});
