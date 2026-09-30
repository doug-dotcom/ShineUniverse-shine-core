import postgres from 'npm:postgres@3.4.9';
import {verifyGithubActionsOidc} from '../_shared/github-actions-oidc-v1.mjs';
import {bindGithubOidcOperation,oidcReplayConflict} from '../_shared/github-oidc-operation-v1.mjs';

const AUDIENCE='shine-defence-provider-ingest';
const EXPECTED_REPOSITORY='doug-dotcom/ShineUniverse-shine-core';
const EXPECTED_REF='refs/heads/main';
const EXPECTED_WORKFLOW_REF='doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-provider-collector.yml@refs/heads/main';
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
  allowedEvents:["schedule","workflow_dispatch","push"]
};
const MAX_BODY_BYTES=96*1024;
const MAX_OBSERVATIONS=50;

const requireEnv=(name:string)=>{
  const value=Deno.env.get(name);
  if(!value) throw new Error('Missing required environment variable: '+name);
  return value;
};

const rawSql=postgres(requireEnv('SUPABASE_DB_URL'),{
  max:1,
  prepare:false,
  idle_timeout:20,
  connect_timeout:10
});

const clean=(value:unknown,max=512)=>typeof value==='string'&&value.length>0&&value.length<=max;
const secretKey=/^(?:secret|token|password|credential|authorization|cookie|api[_-]?key|apikey)$/i;
const hasSensitiveKey=(value:unknown):boolean=>{
  if(Array.isArray(value)) return value.some(hasSensitiveKey);
  if(value&&typeof value==='object'){
    for(const [key,child] of Object.entries(value as Record<string,unknown>)){
      if(secretKey.test(key)||hasSensitiveKey(child)) return true;
    }
  }
  return false;
};

type ProviderObservation={
  targetId:string;
  provider:'railway'|'supabase';
  runtimeState:'active'|'sleeping'|'transitioning'|'inactive'|'failed'|'unknown';
  healthState:'healthy'|'degraded'|'unhealthy'|'unknown';
  deploymentRef:string|null;
  versionRef:string|null;
  artifactRef:string|null;
  sourceRef:string;
  metadata:Record<string,unknown>;
};

function validateObservation(value:any):ProviderObservation{
  if(!value||typeof value!=='object') throw new Error('provider observation must be an object');
  if(!/^(?:railway|supabase):[a-z0-9][a-z0-9-]*$/.test(value.targetId||'')) throw new Error('invalid provider targetId');
  if(!['railway','supabase'].includes(value.provider)) throw new Error('invalid provider');
  if(!['active','sleeping','transitioning','inactive','failed','unknown'].includes(value.runtimeState)) throw new Error('invalid runtimeState');
  if(!['healthy','degraded','unhealthy','unknown'].includes(value.healthState)) throw new Error('invalid healthState');
  for(const key of ['deploymentRef','versionRef','artifactRef']){
    if(value[key]!==null&&value[key]!==undefined&&!clean(value[key],512)) throw new Error('invalid '+key);
  }
  if(!clean(value.sourceRef,512)) throw new Error('invalid sourceRef');
  if(!value.metadata||typeof value.metadata!=='object'||Array.isArray(value.metadata)) throw new Error('invalid metadata');
  if(JSON.stringify(value.metadata).length>8192) throw new Error('provider metadata too large');
  if(hasSensitiveKey(value.metadata)) throw new Error('sensitive provider metadata key rejected');
  return value as ProviderObservation;
}

const jsonResponse=(status:number,body:unknown)=>new Response(JSON.stringify(body),{
  status,
  headers:{'content-type':'application/json','cache-control':'no-store'}
});

Deno.serve(async(req:Request)=>{
  try{
    if(req.method!=='POST') return jsonResponse(405,{error:'method-not-allowed'});
    const length=Number(req.headers.get('content-length')||0);
    if(length>MAX_BODY_BYTES) return jsonResponse(413,{error:'body-too-large'});

    const auth=req.headers.get('authorization')||'';
    if(!auth.startsWith('Bearer ')) return jsonResponse(401,{error:'missing-oidc-token'});
    const identity=await verifyGithubActionsOidc(auth.slice(7),OIDC_POLICY);

    const raw=await req.text();
    if(raw.length>MAX_BODY_BYTES) return jsonResponse(413,{error:'body-too-large'});
    const body=JSON.parse(raw);
    if(body?.contract!=='shine-defence/provider-snapshot-v1'||body?.schemaVersion!=='1.0.0') return jsonResponse(400,{error:'unsupported-provider-snapshot'});
    if(!Array.isArray(body.observations)||body.observations.length>MAX_OBSERVATIONS) return jsonResponse(400,{error:'invalid-observation-count'});
    const observations=body.observations.map(validateObservation);

    const oidcBinding=await bindGithubOidcOperation({
      sql:rawSql,
      identity,
      audience:AUDIENCE,
      operation:'provider-snapshot',
      targetKey:'estate-provider-snapshot',
      request:body
    });
    if(oidcReplayConflict(oidcBinding)){
      return jsonResponse(409,{error:'oidc-replay-conflict',binding:oidcBinding});
    }

    const now=new Date();
    const observedAt=now.toISOString();
    const validUntil=new Date(now.getTime()+2*60*60*1000).toISOString();
    let accepted=0;

    await rawSql.begin(async(tx:any)=>{
      for(const observation of observations){
        if(!observation.targetId.startsWith(observation.provider+':')){
          throw new Error('provider mismatch for '+observation.targetId);
        }

        const evidenceKind=observation.provider==='railway'?'railway-api':'supabase-management-api';
        await tx`
          select foundation.record_defence_estate_observation_v1(
            ${observation.targetId},
            ${observation.runtimeState},
            ${observation.healthState},
            ${observation.deploymentRef},
            ${observation.versionRef},
            ${observation.artifactRef},
            ${observedAt}::timestamptz,
            ${validUntil}::timestamptz,
            ${evidenceKind},
            ${'github-oidc:'+observation.sourceRef+':'+identity.runId+':'+identity.runAttempt},
            ${tx.json({
              ...observation.metadata,
              collector:'shine-defence/estate-provider-collector-v1',
              githubRunId:identity.runId,
              githubRunAttempt:identity.runAttempt,
          githubRepository:identity.repository,
          githubRepositoryId:identity.repositoryId,
          githubRepositoryOwner:identity.repositoryOwner,
          githubRepositoryOwnerId:identity.repositoryOwnerId,
          githubRef:identity.ref,
          githubWorkflowRef:identity.workflowRef,
          githubWorkflowSha:identity.workflowSha,
          githubRunnerEnvironment:identity.runnerEnvironment,
              githubEvent:identity.eventName
            })}
          )
        `;
        accepted++;
      }
    });

    return jsonResponse(200,{
      status:'accepted',
      contract:'shine-defence/provider-ingest-v1',
      accepted,
      observedAt,
      validUntil,
      oidcBinding:{status:oidcBinding.status,bindingId:oidcBinding.bindingId}
    });
  }catch(error){
    const message=error instanceof Error?error.message:'provider-ingest-error';
    const authFailure=/OIDC|oidc|repository mismatch|ref mismatch|workflow mismatch|event not allowed|missing-oidc/.test(message);
    console.error('defence-provider-ingest',message);
    return jsonResponse(authFailure?401:400,{error:authFailure?'unauthorized-provider-ingest':'provider-ingest-rejected'});
  }
});
