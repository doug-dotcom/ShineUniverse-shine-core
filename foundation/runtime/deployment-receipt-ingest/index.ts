import postgres from 'npm:postgres@3.4.9';
import {verifyGithubActionsOidc} from '../_shared/github-actions-oidc-v1.mjs';
import {bindGithubOidcOperation,oidcReplayConflict} from '../_shared/github-oidc-operation-v1.mjs';

const AUDIENCE='shine-foundation-deployment-receipt';
const EXPECTED_REPOSITORY='doug-dotcom/ShineUniverse-shine-core';
const EXPECTED_REF='refs/heads/main';
const EXPECTED_WORKFLOW_REF='doug-dotcom/ShineUniverse-shine-core/.github/workflows/publish-foundation-deployment-receipt.yml@refs/heads/main';
const OIDC_POLICY={
  audience:AUDIENCE,
  expectedRepository:EXPECTED_REPOSITORY,
  expectedRepositoryId:'1072897952',
  expectedRepositoryOwner:'doug-dotcom',
  expectedRepositoryOwnerId:'225530237',
  expectedRef:EXPECTED_REF,
  expectedRefType:'branch',
  expectedRunnerEnvironment:'github-hosted',
  subjectMode:'repository-ref',
  expectedWorkflowRef:EXPECTED_WORKFLOW_REF,
  allowedEvents:["push","workflow_dispatch"]
};
const MAX_BODY_BYTES=32*1024;

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

const clean=(value:unknown,max=1024)=>typeof value==='string'&&value.length>0&&value.length<=max&&!/[\u0000-\u001f\u007f]/.test(value);
const sha40=(value:unknown)=>typeof value==='string'&&/^[a-f0-9]{40}$/i.test(value);
const sha64=(value:unknown)=>typeof value==='string'&&/^[a-f0-9]{64}$/i.test(value);

const jsonResponse=(status:number,body:unknown)=>new Response(JSON.stringify(body),{
  status,
  headers:{'content-type':'application/json','cache-control':'no-store'}
});

Deno.serve(async(req:Request)=>{
  try{
    if(req.method!=='POST') return jsonResponse(405,{error:'method-not-allowed'});

    const declaredLength=Number(req.headers.get('content-length')||0);
    if(declaredLength>MAX_BODY_BYTES) return jsonResponse(413,{error:'body-too-large'});

    const auth=req.headers.get('authorization')??'';
    if(!auth.startsWith('Bearer ')) return jsonResponse(401,{error:'missing-oidc-token'});
    const identity=await verifyGithubActionsOidc(auth.slice(7),OIDC_POLICY);

    const raw=await req.text();
    if(raw.length>MAX_BODY_BYTES) return jsonResponse(413,{error:'body-too-large'});
    const body=JSON.parse(raw||'{}');

    if(body?.contract!=='shine-foundation/deployment-receipt-publish-v1'||body?.schemaVersion!=='1.0.0'){
      return jsonResponse(400,{error:'unsupported-deployment-receipt'});
    }

    const receipt=body?.receipt;
    if(
      !receipt||
      !clean(receipt.runtimeVersion,128)||
      !/^\d+$/.test(receipt.runtimeVersion)||
      !sha64(receipt.artifactSha256)||
      !['active','inactive','failed'].includes(receipt.runtimeState)||
      !sha40(receipt.sourceCommit)||
      !clean(receipt.providerEvidenceRef,1000)||
      !clean(receipt.providerObservedAt,64)||
      Number.isNaN(Date.parse(receipt.providerObservedAt))||
      typeof receipt.rollback!=='boolean'
    ){
      return jsonResponse(400,{error:'invalid-deployment-receipt'});
    }

    const oidcBinding=await bindGithubOidcOperation({
      sql,
      identity,
      audience:AUDIENCE,
      operation:'deployment-receipt-publish',
      targetKey:'foundation.gateway:production',
      request:body
    });
    if(oidcReplayConflict(oidcBinding)){
      return jsonResponse(409,{error:'oidc-replay-conflict',binding:oidcBinding});
    }

    const rows=await sql`
      select foundation.submit_service_deployment_receipt_v1(
        'foundation.gateway',
        'production',
        'supabase-edge',
        'supabase://sjpxqeyewahraxvidvcc/functions/foundation-gateway',
        ${receipt.runtimeVersion},
        ${String(receipt.artifactSha256).toLowerCase()},
        ${receipt.runtimeState},
        ${'github://doug-dotcom/ShineUniverse-shine-core/commit/'+String(receipt.sourceCommit).toLowerCase()},
        ${receipt.providerEvidenceRef},
        ${new Date(receipt.providerObservedAt).toISOString()}::timestamptz,
        'github-actions-oidc',
        ${sql.json({
          transport:'github-oidc',
          githubRunId:identity.runId,
          githubRunAttempt:identity.runAttempt,
          githubEvent:identity.eventName,
          githubRunnerEnvironment:identity.runnerEnvironment,
          githubActor:identity.actor,
          githubRepository:identity.repository,
          githubRepositoryId:identity.repositoryId,
          githubRepositoryOwner:identity.repositoryOwner,
          githubRepositoryOwnerId:identity.repositoryOwnerId,
          githubRef:identity.ref,
          githubWorkflowRef:identity.workflowRef,
          githubWorkflowSha:identity.workflowSha,
          rollback:receipt.rollback
        })}
      ) as result
    `;

    const result=rows[0]?.result??null;
    if(!result) return jsonResponse(500,{error:'deployment-receipt-result-missing'});

    const statusRows=await sql`
      select foundation.get_deployment_reconciliation_status_v1(
        'foundation.gateway','production'
      ) as status
    `;

    return jsonResponse(200,{
      status:'accepted',
      contract:'shine-foundation/deployment-receipt-ingest-v1',
      receipt:result,
      reconciliation:statusRows[0]?.status??null,
      oidcBinding:{status:oidcBinding.status,bindingId:oidcBinding.bindingId}
    });
  }catch(error){
    const message=error instanceof Error?error.message:'deployment-receipt-ingest-error';
    const authFailure=/OIDC|oidc|repository mismatch|ref mismatch|workflow mismatch|event not allowed|missing-oidc/.test(message);
    console.error('foundation-deployment-receipt-ingest',message);
    return jsonResponse(authFailure?401:400,{
      error:authFailure?'unauthorized-deployment-receipt':'deployment-receipt-rejected'
    });
  }
});
