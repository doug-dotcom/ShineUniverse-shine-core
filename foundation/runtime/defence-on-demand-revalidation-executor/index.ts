import postgres from 'npm:postgres@3.4.9';
import {verifyGithubActionsOidc} from '../_shared/github-actions-oidc-v1.mjs';
import {bindGithubOidcOperation,oidcReplayConflict} from '../_shared/github-oidc-operation-v1.mjs';

const AUDIENCE='shine-defence-on-demand-revalidation';
const EXPECTED_WORKFLOW_PATH='.github/workflows/shine-defence-on-demand-revalidation.yml';
const EXPECTED_WORKFLOW_BRANCH='main';
const OIDC_POLICY={
  audience:AUDIENCE,
  expectedRepositoryOwner:'doug-dotcom',
  expectedRepositoryOwnerId:'225530237',
  expectedRepository:'doug-dotcom/ShineUniverse-shine-core',
  expectedRef:'refs/heads/'+EXPECTED_WORKFLOW_BRANCH,
  expectedRefType:'branch',
  expectedRunnerEnvironment:'github-hosted',
  subjectMode:'repository-ref',
  expectedWorkflow:{path:EXPECTED_WORKFLOW_PATH,branch:EXPECTED_WORKFLOW_BRANCH},
  allowedEvents:['push']
};
const MAX_BODY_BYTES=32*1024;
const UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
const SHA=/^[a-f0-9]{40}$/i;

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

const jsonResponse=(status:number,body:unknown)=>new Response(JSON.stringify(body),{
  status,
  headers:{'content-type':'application/json','cache-control':'no-store'}
});

const clean=(value:unknown,max=256)=>typeof value==='string'&&value.length>0&&value.length<=max&&!/[\u0000-\u001f\u007f]/.test(value);

async function getLiveAuthority(){
  const rows=await sql`
    select
      lower(a.authority_sha) as authority_sha,
      a.authority_ref,
      foundation.get_defence_attestation_authority_sync_summary_v1(
        now(),5400
      ) as sync_summary
    from foundation.current_defence_attestation_authority a
  `;
  const current=rows?.[0];
  const summary=current?.sync_summary;
  const age=Number(summary?.receiptAgeSeconds);
  if(
    !current||
    !SHA.test(String(current.authority_sha??''))||
    !clean(current.authority_ref,1024)||
    !summary||
    summary.state!=='pass'||
    summary.reasonCode!=='attestation-authority-sync-current'||
    !Number.isFinite(age)||
    age<0||
    age>5400||
    String(summary?.currentAuthority?.authoritySha??'').toLowerCase()!==String(current.authority_sha).toLowerCase()||
    String(summary?.currentAuthority?.authorityRef??'')!==String(current.authority_ref)
  ){
    throw new Error('revalidation-executor-authority-not-current');
  }
  return {
    authoritySha:String(current.authority_sha).toLowerCase(),
    authorityRef:String(current.authority_ref),
    receiptAgeSeconds:age
  };
}

async function claimExecution(executionId:string,identity:any,liveAuthority:any){
  return sql.begin(async tx=>{
    const rows=await tx`
      select
        a.execution_id,
        a.expires_at,
        a.evidence_fingerprint,
        a.execution_envelope,
        a.envelope_sha256,
        encode(
          extensions.digest(
            convert_to(a.execution_envelope::text,'UTF8'),'sha256'
          ),
          'hex'
        ) as computed_envelope_sha256,
        foundation.get_defence_on_demand_revalidation_status_v1(
          a.execution_envelope->>'targetId',now()
        ) as control_status,
        foundation.get_defence_on_demand_revalidation_fingerprint_v1(
          foundation.get_defence_on_demand_revalidation_snapshot_v1(
            a.execution_envelope->>'targetId',now()
          )
        ) as live_fingerprint
      from foundation.defence_on_demand_revalidation_admissions a
      where a.execution_id=${executionId}::uuid
      for update
    `;
    const admission=rows[0];
    if(!admission) throw new Error('revalidation-execution-missing');
    if(new Date(admission.expires_at).getTime()<=Date.now()) throw new Error('revalidation-execution-expired');
    if(admission.envelope_sha256!==admission.computed_envelope_sha256) throw new Error('revalidation-execution-integrity-failed');
    if(admission.live_fingerprint!==admission.evidence_fingerprint) throw new Error('revalidation-execution-live-fingerprint-drift');
    if(admission.control_status?.state!=='admitted') throw new Error('revalidation-execution-not-admitted');

    const terminal=await tx`
      select exists(
        select 1
        from foundation.defence_on_demand_revalidation_events
        where execution_id=${executionId}::uuid
          and step_type in ('completed','failed')
      ) as terminal,
      exists(
        select 1
        from foundation.defence_on_demand_revalidation_events
        where execution_id=${executionId}::uuid
          and step_type='redeploy_started'
      ) as already_claimed
    `;
    if(terminal[0]?.terminal) throw new Error('revalidation-execution-terminal');
    if(terminal[0]?.already_claimed) throw new Error('revalidation-execution-already-claimed');

    const envelope=admission.execution_envelope;
    const expectedSha=envelope?.constraints?.expectedSourceHeadSha;
    if(
      String(envelope?.authority?.sha??'').toLowerCase()!==liveAuthority.authoritySha||
      String(envelope?.authority?.ref??'')!==liveAuthority.authorityRef
    ){
      throw new Error('revalidation-execution-authority-drift');
    }
    if(!UUID.test(String(envelope?.railway?.projectId??''))||
       !UUID.test(String(envelope?.railway?.environmentId??''))||
       !UUID.test(String(envelope?.railway?.serviceId??''))||
       !SHA.test(String(expectedSha??''))){
      throw new Error('revalidation-execution-envelope-scope-invalid');
    }

    await tx`set local role shine_defence_on_demand_executor`;
    const eventRows=await tx`
      select foundation.record_defence_on_demand_revalidation_step_v1(
        gen_random_uuid(),
        ${executionId}::uuid,
        'redeploy_started',
        ${tx.json({
          projectId:envelope.railway.projectId,
          environmentId:envelope.railway.environmentId,
          serviceId:envelope.railway.serviceId,
          expectedSourceHeadSha:expectedSha,
          githubRunId:String(identity.runId),
          githubRunAttempt:String(identity.runAttempt),
          githubActor:String(identity.actor),
          githubWorkflowRef:String(identity.workflowRef),
          githubJobWorkflowRef:identity.jobWorkflowRef||null,
          githubJobWorkflowSha:identity.jobWorkflowSha||null,
          activeAuthoritySha:liveAuthority.authoritySha,
          activeAuthorityRef:liveAuthority.authorityRef
        })},
        now()
      ) as result
    `;
    return {envelope,event:eventRows[0]?.result??null};
  });
}

async function recordDeployment(
  executionId:string,
  deploymentId:string|null,
  status:string,
  commitSha:string|null,
  identity:any
){
  return sql.begin(async tx=>{
    const rows=await tx`
      select execution_envelope
      from foundation.defence_on_demand_revalidation_admissions
      where execution_id=${executionId}::uuid
      for update
    `;
    const envelope=rows[0]?.execution_envelope;
    if(!envelope) throw new Error('revalidation-execution-missing');
    const expectedSha=String(envelope?.constraints?.expectedSourceHeadSha??'').toLowerCase();
    const normalizedStatus=String(status||'').toUpperCase();
    const normalizedCommit=String(commitSha||'').toLowerCase();

    await tx`set local role shine_defence_on_demand_executor`;
    if(normalizedStatus==='SUCCESS'&&UUID.test(String(deploymentId||''))&&normalizedCommit===expectedSha){
      const eventRows=await tx`
        select foundation.record_defence_on_demand_revalidation_step_v1(
          gen_random_uuid(),
          ${executionId}::uuid,
          'deployment_verified',
          ${tx.json({
            status:'SUCCESS',
            deploymentId,
            deployedCommitSha:normalizedCommit,
            githubRunId:String(identity.runId),
            githubRunAttempt:String(identity.runAttempt)
          })},
          now()
        ) as result
      `;
      return {status:'deployment-verified',result:eventRows[0]?.result??null};
    }

    const eventRows=await tx`
      select foundation.record_defence_on_demand_revalidation_step_v1(
        gen_random_uuid(),
        ${executionId}::uuid,
        'failed',
        ${tx.json({
          phase:'redeploy_current_source',
          reasonCode:'railway-deployment-not-verified',
          deploymentId:deploymentId||null,
          railwayStatus:normalizedStatus||'UNKNOWN',
          deployedCommitSha:normalizedCommit||null,
          expectedSourceHeadSha:expectedSha,
          externalMutationPerformed:true,
          githubRunId:String(identity.runId),
          githubRunAttempt:String(identity.runAttempt)
        })},
        now()
      ) as result
    `;
    return {status:'failed',result:eventRows[0]?.result??null};
  });
}

Deno.serve(async(req:Request)=>{
  try{
    if(req.method!=='POST') return jsonResponse(405,{error:'method-not-allowed'});
    const length=Number(req.headers.get('content-length')||0);
    if(length>MAX_BODY_BYTES) return jsonResponse(413,{error:'body-too-large'});

    const auth=req.headers.get('authorization')??'';
    if(!auth.startsWith('Bearer ')) return jsonResponse(401,{error:'missing-oidc-token'});
    const identity=await verifyGithubActionsOidc(auth.slice(7),OIDC_POLICY);
    const liveAuthority=await getLiveAuthority();

    const raw=await req.text();
    if(raw.length>MAX_BODY_BYTES) return jsonResponse(413,{error:'body-too-large'});
    const body=JSON.parse(raw||'{}');
    if(body?.contract!=='shine-defence/on-demand-revalidation-executor-gate-v1'||
       body?.schemaVersion!=='1.0.0'||
       !UUID.test(String(body?.executionId??''))){
      return jsonResponse(400,{error:'invalid-revalidation-executor-request'});
    }

    const action=String(body.action||'');
    if(!['claim','record-deployment'].includes(action)){
      return jsonResponse(400,{error:'unsupported-revalidation-executor-action'});
    }

    const binding=await bindGithubOidcOperation({
      sql,
      identity,
      audience:AUDIENCE,
      operation:'on-demand-revalidation-'+action,
      targetKey:[
        String(body.executionId),
        action,
        action==='record-deployment'?String(body.deploymentId||body.status||'unknown'):'claim'
      ].join(':'),
      request:body
    });
    if(oidcReplayConflict(binding)){
      return jsonResponse(409,{error:'oidc-replay-conflict',binding});
    }

    if(action==='claim'){
      const result=await claimExecution(String(body.executionId),identity,liveAuthority);
      return jsonResponse(200,{
        status:'claimed',
        contract:'shine-defence/on-demand-revalidation-executor-gate-v1',
        executionId:body.executionId,
        executionEnvelope:result.envelope,
        event:result.event
      });
    }

    if(!clean(body.status,40)||
       (body.deploymentId!==null&&body.deploymentId!==undefined&&!UUID.test(String(body.deploymentId)))||
       (body.commitSha!==null&&body.commitSha!==undefined&&!SHA.test(String(body.commitSha)))){
      return jsonResponse(400,{error:'invalid-revalidation-deployment-result'});
    }
    const result=await recordDeployment(
      String(body.executionId),
      body.deploymentId?String(body.deploymentId):null,
      String(body.status),
      body.commitSha?String(body.commitSha):null,
      identity
    );
    return jsonResponse(200,{
      contract:'shine-defence/on-demand-revalidation-executor-gate-v1',
      executionId:body.executionId,
      ...result
    });
  }catch(error){
    const message=error instanceof Error?error.message:'revalidation-executor-error';
    const authFailure=/OIDC|oidc|repository mismatch|ref mismatch|workflow mismatch|event not allowed|missing-oidc/.test(message);
    console.error('defence-on-demand-revalidation-executor',message);
    return jsonResponse(authFailure?401:409,{
      error:authFailure?'unauthorized-revalidation-executor':'revalidation-executor-rejected',
      reasonCode:message
    });
  }
});
