import postgres from 'npm:postgres@3.4.9';
import {verifyGithubActionsOidc} from '../_shared/github-actions-oidc-v1.mjs';
import {bindGithubOidcOperation,oidcReplayConflict} from '../_shared/github-oidc-operation-v1.mjs';

const AUDIENCE='shine-defence-on-demand-executor-readiness';
const OIDC_POLICY={
  audience:AUDIENCE,
  expectedRepositoryOwner:'doug-dotcom',
  expectedRepositoryOwnerId:'225530237',
  expectedRepository:'doug-dotcom/ShineUniverse-shine-core',
  expectedRef:'refs/heads/main',
  expectedRefType:'branch',
  expectedRunnerEnvironment:'github-hosted',
  subjectMode:'repository-ref',
  expectedWorkflow:{
    path:'.github/workflows/shine-defence-on-demand-executor-readiness.yml',
    branch:'main'
  },
  allowedEvents:['push','schedule','workflow_dispatch']
};
const MAX_BODY_BYTES=16*1024;

const requireEnv=(name:string)=>{
  const value=Deno.env.get(name);
  if(!value) throw new Error('Missing required environment variable: '+name);
  return value;
};

const sql=postgres(requireEnv('SUPABASE_DB_URL'),{
  max:1,prepare:false,idle_timeout:20,connect_timeout:10
});

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

    if(
      body?.contract!=='shine-defence/on-demand-executor-readiness-v1'||
      body?.schemaVersion!=='1.0.0'||
      body?.executorMode!=='direct_railway'||
      typeof body?.credentialReady!=='boolean'
    ){
      return jsonResponse(400,{error:'invalid-executor-readiness'});
    }

    const authorityRows=await sql`
      select foundation.get_defence_attestation_authority_sync_summary_v1(
        now(),5400
      ) as summary
    `;
    const summary=authorityRows[0]?.summary;
    if(
      !summary||
      summary.state!=='pass'||
      summary.reasonCode!=='attestation-authority-sync-current'
    ){
      return jsonResponse(409,{error:'defence-authority-heartbeat-not-current'});
    }

    const binding=await bindGithubOidcOperation({
      sql,
      identity,
      audience:AUDIENCE,
      operation:'on-demand-executor-readiness',
      targetKey:'direct_railway:'+String(body.credentialReady),
      request:body
    });
    if(oidcReplayConflict(binding)){
      return jsonResponse(409,{error:'oidc-replay-conflict',binding});
    }

    const observedAt=new Date();
    const validUntil=new Date(observedAt.getTime()+60*60*1000);
    const evidenceRef=[
      'github-oidc',
      'on-demand-executor-readiness',
      identity.runId,
      identity.runAttempt,
      body.credentialReady?'ready':'missing'
    ].join(':');

    const rows=await sql`
      select foundation.record_defence_on_demand_executor_readiness_v1(
        'direct_railway',
        ${body.credentialReady},
        ${observedAt.toISOString()}::timestamptz,
        ${validUntil.toISOString()}::timestamptz,
        ${evidenceRef},
        ${sql.json({
          collector:'shine-defence/on-demand-executor-readiness-v1',
          credentialName:'SHINE_DEFENCE_RAILWAY_WORKSPACE_TOKEN',
          credentialValueExposed:false,
          githubRunId:identity.runId,
          githubRunAttempt:identity.runAttempt,
          githubEvent:identity.eventName,
          githubActor:identity.actor,
          githubRepository:identity.repository,
          githubRef:identity.ref,
          githubWorkflowRef:identity.workflowRef,
          githubWorkflowSha:identity.workflowSha,
          githubJobWorkflowRef:identity.jobWorkflowRef||null,
          githubJobWorkflowSha:identity.jobWorkflowSha||null,
          authorityReceiptId:summary.latestReceipt?.receiptId??null,
          authoritySha:summary.currentAuthority?.authoritySha??null
        })}
      ) as result
    `;

    return jsonResponse(200,{
      status:'accepted',
      contract:'shine-defence/on-demand-executor-readiness-v1',
      executorMode:'direct_railway',
      credentialReady:body.credentialReady,
      observedAt:observedAt.toISOString(),
      validUntil:validUntil.toISOString(),
      result:rows[0]?.result??null
    });
  }catch(error){
    const message=error instanceof Error?error.message:'executor-readiness-error';
    const authFailure=/OIDC|oidc|repository mismatch|ref mismatch|workflow mismatch|event not allowed|missing-oidc/.test(message);
    console.error('defence-on-demand-executor-readiness',message);
    return jsonResponse(authFailure?401:400,{
      error:authFailure?'unauthorized-executor-readiness':'executor-readiness-rejected'
    });
  }
});
