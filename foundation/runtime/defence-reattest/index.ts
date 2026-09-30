import postgres from 'npm:postgres@3.4.9';
import {verifyGithubActionsOidc} from '../_shared/github-actions-oidc-v1.mjs';
import {bindGithubOidcOperation,oidcReplayConflict,oidcExactReplay} from '../_shared/github-oidc-operation-v1.mjs';

const AUDIENCE='shine-defence-reattest';
const EXPECTED_REPOSITORY='doug-dotcom/ShineUniverse-shine-core';
const EXPECTED_REF='refs/heads/main';
const EXPECTED_WORKFLOW_REF='doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-reattest.yml@refs/heads/main';
const OIDC_POLICY={
  audience:AUDIENCE,
  expectedRepository:EXPECTED_REPOSITORY,
  expectedRef:EXPECTED_REF,
  expectedWorkflowRef:EXPECTED_WORKFLOW_REF,
  allowedEvents:["schedule","workflow_dispatch","push"]
};
const MAX_BODY_BYTES=64*1024;

const requireEnv=(name:string)=>{
  const value=Deno.env.get(name);
  if(!value)throw new Error('Missing required environment variable: '+name);
  return value;
};

const rawSql=postgres(requireEnv('SUPABASE_DB_URL'),{
  max:1,
  prepare:false,
  idle_timeout:20,
  connect_timeout:10
});

const clean=(value:unknown,max=512)=>typeof value==='string'&&value.length>0&&value.length<=max;
const sha40=(value:unknown)=>typeof value==='string'&&/^[a-f0-9]{40}$/i.test(value);
const sha64=(value:unknown)=>typeof value==='string'&&/^[a-f0-9]{64}$/i.test(value);
const serviceId=(value:unknown)=>typeof value==='string'&&/^[a-z0-9][a-z0-9._:-]*$/.test(value);
const environment=(value:unknown)=>typeof value==='string'&&/^[a-z0-9][a-z0-9._-]*$/.test(value);

const jsonResponse=(status:number,body:unknown)=>new Response(JSON.stringify(body),{
  status,
  headers:{'content-type':'application/json','cache-control':'no-store'}
});

Deno.serve(async(req:Request)=>{
  try{
    if(req.method!=='POST')return jsonResponse(405,{error:'method-not-allowed'});
    const length=Number(req.headers.get('content-length')||0);
    if(length>MAX_BODY_BYTES)return jsonResponse(413,{error:'body-too-large'});

    const auth=req.headers.get('authorization')||'';
    if(!auth.startsWith('Bearer '))return jsonResponse(401,{error:'missing-oidc-token'});
    const identity=await verifyGithubActionsOidc(auth.slice(7),OIDC_POLICY);

    const raw=await req.text();
    if(raw.length>MAX_BODY_BYTES)return jsonResponse(413,{error:'body-too-large'});
    const body=JSON.parse(raw||'{}');

    if(body?.action==='claim'){
      const claimBinding=await bindGithubOidcOperation({
        sql:rawSql,
        identity,
        audience:AUDIENCE,
        operation:'reattest-claim',
        targetKey:'foundation-core',
        request:body
      });
      if(oidcReplayConflict(claimBinding)){
        return jsonResponse(409,{error:'oidc-replay-conflict',binding:claimBinding});
      }
      const force=body.force===true&&identity.eventName==='push';
      const rows=await rawSql`
        select foundation.get_defence_reattestation_work_v1(${force}) as work
      `;
      return jsonResponse(200,{
        status:'ok',
        contract:'shine-defence/reattestation-claim-v1',
        work:rows[0]?.work??null,
        oidcBinding:{status:claimBinding.status,bindingId:claimBinding.bindingId}
      });
    }

    if(body?.action!=='attest')return jsonResponse(400,{error:'unsupported-action'});
    const submission=body?.submission;
    if(!submission||submission.contract!=='shine-defence/reattestation-submission-v1'||submission.schemaVersion!=='1.0.0'){
      return jsonResponse(400,{error:'unsupported-submission'});
    }

    if(!serviceId(submission.serviceId)
       ||!environment(submission.environment)
       ||!sha64(submission.artifactSha256)
       ||!sha40(submission.sourceCommit)
       ||!sha40(submission.policyCommit)
       ||!sha64(submission.reportSha256)
       ||!clean(submission.inspectorVersion,64)
       ||!['pass','fail'].includes(submission.authStatus)
       ||!['pass','fail'].includes(submission.dependenciesStatus)
       ||!['pass','fail'].includes(submission.reportState)){
      return jsonResponse(400,{error:'invalid-submission'});
    }

    const summary=submission.summary;
    if(!summary||typeof summary!=='object'||Array.isArray(summary)){
      return jsonResponse(400,{error:'invalid-summary'});
    }
    for(const key of ['findingCount','npmImportCount','unpinnedNpmImportCount','remoteRuntimeImportCount']){
      if(!Number.isInteger(summary[key])||summary[key]<0||summary[key]>100000){
        return jsonResponse(400,{error:'invalid-summary-count'});
      }
    }

    const attestBinding=await bindGithubOidcOperation({
      sql:rawSql,
      identity,
      audience:AUDIENCE,
      operation:'reattest-attest',
      targetKey:[submission.serviceId,submission.environment,submission.artifactSha256].join(':'),
      request:body
    });
    if(oidcReplayConflict(attestBinding)){
      return jsonResponse(409,{error:'oidc-replay-conflict',binding:attestBinding});
    }

    const observedAt=new Date();
    const validUntil=new Date(observedAt.getTime()+24*60*60*1000);
    const evidenceRef=[
      'github-oidc',
      'defence-reattest',
      identity.runId,
      identity.runAttempt,
      submission.serviceId,
      submission.artifactSha256
    ].join(':');

    if(oidcExactReplay(attestBinding)){
      const existing=await rawSql`
        select
          event_id,state,service_id,environment,artifact_sha256,source_commit,valid_until
        from foundation.defence_artifact_attestation_events
        where evidence_ref=${evidenceRef}
        limit 1
      `;
      const row=existing[0];
      if(row){
        return jsonResponse(200,{
          status:'accepted',
          contract:'shine-defence/reattestation-ingest-v1',
          result:{
            defenceReattestation:'shine-defence/reattestation-result-v1',
            schemaVersion:'1.0.0',
            state:row.state,
            serviceId:row.service_id,
            environment:row.environment,
            artifactSha256:row.artifact_sha256,
            sourceCommit:row.source_commit,
            attestationEventId:row.event_id,
            validUntil:row.valid_until,
            replayed:true
          },
          oidcBinding:{status:attestBinding.status,bindingId:attestBinding.bindingId}
        });
      }
    }

    const rows=await rawSql`
      select foundation.record_defence_reattestation_v1(
        ${submission.serviceId},
        ${submission.environment},
        ${submission.artifactSha256},
        ${submission.sourceCommit},
        ${submission.authStatus},
        ${submission.dependenciesStatus},
        ${submission.inspectorVersion},
        ${submission.policyCommit},
        ${submission.reportSha256},
        ${observedAt.toISOString()}::timestamptz,
        ${validUntil.toISOString()}::timestamptz,
        ${evidenceRef},
        ${rawSql.json({
          collector:'shine-defence/automatic-reattestation-v1',
          reportState:submission.reportState,
          findingCount:summary.findingCount,
          npmImportCount:summary.npmImportCount,
          unpinnedNpmImportCount:summary.unpinnedNpmImportCount,
          remoteRuntimeImportCount:summary.remoteRuntimeImportCount,
          githubRunId:identity.runId,
          githubRunAttempt:identity.runAttempt,
          githubEvent:identity.eventName,
          githubActor:identity.actor
        })}
      ) as result
    `;

    return jsonResponse(200,{
      status:'accepted',
      contract:'shine-defence/reattestation-ingest-v1',
      result:rows[0]?.result??null,
      oidcBinding:{status:attestBinding.status,bindingId:attestBinding.bindingId}
    });
  }catch(error){
    const message=error instanceof Error?error.message:'reattestation-error';
    const authFailure=/OIDC|oidc|repository mismatch|ref mismatch|workflow mismatch|event not allowed|missing-oidc/.test(message);
    console.error('defence-reattest',message);
    return jsonResponse(authFailure?401:400,{
      error:authFailure?'unauthorized-reattestation':'reattestation-rejected'
    });
  }
});
