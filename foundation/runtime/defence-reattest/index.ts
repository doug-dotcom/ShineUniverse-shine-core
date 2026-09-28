import postgres from 'npm:postgres@3.4.9';

const AUDIENCE='shine-defence-reattest';
const EXPECTED_ISSUER='https://token.actions.githubusercontent.com';
const EXPECTED_REPOSITORY='doug-dotcom/ShineUniverse-shine-core';
const EXPECTED_REF='refs/heads/main';
const EXPECTED_WORKFLOW_REF='doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-reattest.yml@refs/heads/main';
const MAX_BODY_BYTES=64*1024;
const encoder=new TextEncoder();
const decoder=new TextDecoder();

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

const base64urlBytes=(value:string)=>{
  const padded=value.replace(/-/g,'+').replace(/_/g,'/')+'='.repeat((4-value.length%4)%4);
  const binary=atob(padded);
  return Uint8Array.from(binary,c=>c.charCodeAt(0));
};
const parsePart=(value:string)=>JSON.parse(decoder.decode(base64urlBytes(value)));
const clean=(value:unknown,max=512)=>typeof value==='string'&&value.length>0&&value.length<=max;
const sha40=(value:unknown)=>typeof value==='string'&&/^[a-f0-9]{40}$/i.test(value);
const sha64=(value:unknown)=>typeof value==='string'&&/^[a-f0-9]{64}$/i.test(value);
const serviceId=(value:unknown)=>typeof value==='string'&&/^[a-z0-9][a-z0-9._:-]*$/.test(value);
const environment=(value:unknown)=>typeof value==='string'&&/^[a-z0-9][a-z0-9._-]*$/.test(value);

let oidcMetadataPromise:Promise<{jwks_uri:string}>|null=null;
let jwksPromise:Promise<{keys:JsonWebKey[]}>|null=null;
const getOidcMetadata=()=>oidcMetadataPromise??=(async()=>{
  const response=await fetch(EXPECTED_ISSUER+'/.well-known/openid-configuration');
  if(!response.ok)throw new Error('GitHub OIDC metadata unavailable');
  const body=await response.json();
  if(!clean(body?.jwks_uri,1024))throw new Error('GitHub OIDC jwks_uri missing');
  return {jwks_uri:body.jwks_uri};
})();
const getJwks=()=>jwksPromise??=(async()=>{
  const metadata=await getOidcMetadata();
  const response=await fetch(metadata.jwks_uri);
  if(!response.ok)throw new Error('GitHub OIDC JWKS unavailable');
  const body=await response.json();
  if(!Array.isArray(body?.keys))throw new Error('GitHub OIDC JWKS invalid');
  return {keys:body.keys};
})();

async function verifyGithubOidc(token:string){
  const parts=token.split('.');
  if(parts.length!==3)throw new Error('invalid OIDC token format');
  const header=parsePart(parts[0]);
  const payload=parsePart(parts[1]);
  if(header?.alg!=='RS256'||!clean(header?.kid,256))throw new Error('unsupported OIDC signing header');

  const jwks=await getJwks();
  const jwk=jwks.keys.find((key:any)=>key.kid===header.kid);
  if(!jwk)throw new Error('OIDC signing key not found');

  const key=await crypto.subtle.importKey(
    'jwk',jwk,{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['verify']
  );
  const ok=await crypto.subtle.verify(
    {name:'RSASSA-PKCS1-v1_5'},
    key,
    base64urlBytes(parts[2]),
    encoder.encode(parts[0]+'.'+parts[1])
  );
  if(!ok)throw new Error('OIDC signature verification failed');

  const now=Math.floor(Date.now()/1000);
  const aud=Array.isArray(payload.aud)?payload.aud:[payload.aud];
  if(payload.iss!==EXPECTED_ISSUER)throw new Error('OIDC issuer mismatch');
  if(!aud.includes(AUDIENCE))throw new Error('OIDC audience mismatch');
  if(typeof payload.exp!=='number'||payload.exp<now-30)throw new Error('OIDC token expired');
  if(typeof payload.nbf==='number'&&payload.nbf>now+30)throw new Error('OIDC token not active');
  if(payload.repository!==EXPECTED_REPOSITORY)throw new Error('OIDC repository mismatch');
  if(payload.ref!==EXPECTED_REF)throw new Error('OIDC ref mismatch');
  if(payload.workflow_ref!==EXPECTED_WORKFLOW_REF)throw new Error('OIDC workflow mismatch');
  if(!['schedule','workflow_dispatch','push'].includes(String(payload.event_name)))throw new Error('OIDC event not allowed');

  return {
    runId:String(payload.run_id??''),
    runAttempt:String(payload.run_attempt??''),
    eventName:String(payload.event_name),
    actor:String(payload.actor??''),
    sha:String(payload.sha??'')
  };
}

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
    const identity=await verifyGithubOidc(auth.slice(7));

    const raw=await req.text();
    if(raw.length>MAX_BODY_BYTES)return jsonResponse(413,{error:'body-too-large'});
    const body=JSON.parse(raw||'{}');

    if(body?.action==='claim'){
      const force=body.force===true&&identity.eventName==='push';
      const rows=await rawSql`
        select foundation.get_defence_reattestation_work_v1(${force}) as work
      `;
      return jsonResponse(200,{
        status:'ok',
        contract:'shine-defence/reattestation-claim-v1',
        work:rows[0]?.work??null
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
      result:rows[0]?.result??null
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
