import postgres from 'npm:postgres@3.4.9';

const CONTRACT='shine-defence/railway-transition-webhook-v1';
const WEBHOOK_SECRET_SHA256='24184b6ac81093a435a0bc1b5c3628d0aea2a8ed5cd2fbf9e6b619266ed58300';
const MAX_BODY_BYTES=64*1024;
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA40=/^[0-9a-f]{40}$/i;

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

const hex=(bytes:Uint8Array)=>Array.from(bytes).map(b=>b.toString(16).padStart(2,'0')).join('');

async function sha256(value:string){
  return hex(new Uint8Array(await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(value)
  )));
}

function constantTimeEqual(a:string,b:string){
  if(a.length!==b.length) return false;
  let diff=0;
  for(let i=0;i<a.length;i++) diff|=a.charCodeAt(i)^b.charCodeAt(i);
  return diff===0;
}

const clean=(value:unknown,max=200)=>
  typeof value==='string'&&value.length>0&&value.length<=max&&!/[\u0000-\u001f\u007f]/.test(value)
    ? value
    : null;

const transitionState=(type:string)=>{
  const suffix=type.split('.').slice(1).join('.').toLowerCase().replace(/[^a-z0-9]+/g,'_');
  const map:Record<string,string>={
    waiting:'waiting',
    needs_approval:'needs_approval',
    queued:'queued',
    initializing:'initializing',
    initialising:'initializing',
    skipped:'skipped',
    building:'building',
    deploying:'deploying',
    success:'success',
    succeeded:'success',
    successful:'success',
    failed:'failed',
    removed:'removed',
    crashed:'crashed',
    removing:'removing',
    sleeping:'sleeping'
  };
  return map[suffix]??'unknown';
};

const json=(status:number,body:unknown)=>new Response(JSON.stringify(body),{
  status,
  headers:{
    'content-type':'application/json',
    'cache-control':'no-store',
    'access-control-allow-origin':'*',
    'access-control-allow-methods':'POST,OPTIONS',
    'access-control-allow-headers':'content-type'
  }
});

Deno.serve(async(req:Request)=>{
  try{
    if(req.method==='OPTIONS') return new Response(null,{
      status:204,
      headers:{
        'access-control-allow-origin':'*',
        'access-control-allow-methods':'POST,OPTIONS',
        'access-control-allow-headers':'content-type',
        'cache-control':'no-store'
      }
    });
    if(req.method!=='POST') return json(405,{error:'method-not-allowed'});

    const supplied=new URL(req.url).searchParams.get('k')??'';
    if(!supplied || supplied.length>128) return json(401,{error:'unauthorized'});
    const suppliedHash=await sha256(supplied);
    if(!constantTimeEqual(suppliedHash,WEBHOOK_SECRET_SHA256)){
      return json(401,{error:'unauthorized'});
    }

    const contentLength=Number(req.headers.get('content-length')||0);
    if(contentLength>MAX_BODY_BYTES) return json(413,{error:'body-too-large'});

    const raw=await req.text();
    if(raw.length>MAX_BODY_BYTES) return json(413,{error:'body-too-large'});
    const payloadSha256=await sha256(raw);

    let event:any;
    try{ event=JSON.parse(raw); }
    catch{ return json(400,{error:'invalid-json'}); }

    const eventType=clean(event?.type,128);
    if(!eventType || !eventType.startsWith('Deployment.')){
      return json(200,{status:'ignored',reasonCode:'non-deployment-event'});
    }

    const resource=event?.resource??{};
    const details=event?.details??{};
    const projectId=resource?.project?.id;
    const environmentId=resource?.environment?.id;
    const serviceId=resource?.service?.id;
    const deploymentId=resource?.deployment?.id;
    const environmentName=clean(resource?.environment?.name,200);
    const occurredAt=clean(event?.timestamp,64);

    if(
      !UUID.test(projectId??'')||
      !UUID.test(environmentId??'')||
      !UUID.test(serviceId??'')||
      !UUID.test(deploymentId??'')||
      !occurredAt||
      Number.isNaN(Date.parse(occurredAt))
    ){
      return json(400,{error:'invalid-deployment-event'});
    }

    if(environmentName && environmentName.toLowerCase()!=='production'){
      return json(200,{status:'ignored',reasonCode:'non-production-environment'});
    }

    const state=transitionState(eventType);
    const severityRaw=String(event?.severity??'').toUpperCase();
    const severity=['INFO','WARNING','ERROR','CRITICAL'].includes(severityRaw)
      ? severityRaw
      : null;
    const sourceKind=clean(details?.source,64);
    const branch=clean(details?.branch,200);
    const commitRaw=clean(details?.commitHash,64);
    const commitSha=commitRaw&&SHA40.test(commitRaw)?commitRaw.toLowerCase():null;
    const evidenceRef=[
      'railway-webhook',
      projectId,
      environmentId,
      serviceId,
      deploymentId,
      eventType,
      occurredAt,
      payloadSha256.slice(0,20)
    ].join(':');

    const rows=await sql`
      select foundation.record_defence_railway_transition_v1(
        ${projectId}::uuid,
        ${environmentId}::uuid,
        ${serviceId}::uuid,
        ${deploymentId}::uuid,
        ${eventType},
        ${state},
        ${severity},
        ${sourceKind},
        ${branch},
        ${commitSha},
        ${new Date(occurredAt).toISOString()}::timestamptz,
        ${payloadSha256},
        ${evidenceRef},
        ${sql.json({
          contract:CONTRACT,
          projectName:clean(resource?.project?.name,200),
          environmentName,
          serviceName:clean(resource?.service?.name,200),
          detailsStatus:clean(details?.status,64),
          environmentEphemeral:resource?.environment?.isEphemeral===true
        })}
      ) as result
    `;

    return json(200,{
      status:'accepted',
      contract:CONTRACT,
      result:rows[0]?.result??null
    });
  }catch(error){
    console.error('defence-railway-events',error instanceof Error?error.message:'receiver-error');
    return json(500,{error:'receiver-error'});
  }
});
