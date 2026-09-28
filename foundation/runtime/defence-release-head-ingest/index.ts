import postgres from 'npm:postgres@3.4.9';

const AUDIENCE='shine-defence-release-head';
const EXPECTED_ISSUER='https://token.actions.githubusercontent.com';
const EXPECTED_WORKFLOW_PATH='.github/workflows/shine-defence-release-head.yml';
const EXPECTED_WORKFLOW_BRANCH='main';
const MAX_BODY_BYTES=96*1024;
const MAX_OBSERVATIONS=50;
const encoder=new TextEncoder();
const decoder=new TextDecoder();

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

const base64urlBytes=(value:string)=>{
  const padded=value.replace(/-/g,'+').replace(/_/g,'/')+'='.repeat((4-value.length%4)%4);
  const binary=atob(padded);
  return Uint8Array.from(binary,c=>c.charCodeAt(0));
};

const parsePart=(value:string)=>JSON.parse(decoder.decode(base64urlBytes(value)));
const clean=(value:unknown,max=512)=>typeof value==='string'&&value.length>0&&value.length<=max&&!/[\u0000-\u001f\u007f]/.test(value);
const sha40=(value:unknown)=>typeof value==='string'&&/^[a-f0-9]{40}$/i.test(value);
const targetId=(value:unknown)=>typeof value==='string'&&/^railway:[a-z0-9][a-z0-9-]*$/.test(value);
const repository=(value:unknown)=>typeof value==='string'&&/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(value);

let oidcMetadataPromise:Promise<{jwks_uri:string}>|null=null;
let jwksPromise:Promise<{keys:JsonWebKey[]}>|null=null;

const getOidcMetadata=()=>oidcMetadataPromise??=(async()=>{
  const response=await fetch(EXPECTED_ISSUER+'/.well-known/openid-configuration');
  if(!response.ok) throw new Error('GitHub OIDC metadata unavailable');
  const body=await response.json();
  if(!clean(body?.jwks_uri,1024)) throw new Error('GitHub OIDC jwks_uri missing');
  return {jwks_uri:body.jwks_uri};
})();

const getJwks=()=>jwksPromise??=(async()=>{
  const metadata=await getOidcMetadata();
  const response=await fetch(metadata.jwks_uri);
  if(!response.ok) throw new Error('GitHub OIDC JWKS unavailable');
  const body=await response.json();
  if(!Array.isArray(body?.keys)) throw new Error('GitHub OIDC JWKS invalid');
  return {keys:body.keys};
})();

async function verifyGithubOidc(token:string){
  const parts=token.split('.');
  if(parts.length!==3) throw new Error('invalid OIDC token format');
  const header=parsePart(parts[0]);
  const payload=parsePart(parts[1]);
  if(header?.alg!=='RS256'||!clean(header?.kid,256)) throw new Error('unsupported OIDC signing header');

  const jwks=await getJwks();
  const jwk=jwks.keys.find((key:any)=>key.kid===header.kid);
  if(!jwk) throw new Error('OIDC signing key not found');

  const key=await crypto.subtle.importKey(
    'jwk',jwk,{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['verify']
  );
  const ok=await crypto.subtle.verify(
    {name:'RSASSA-PKCS1-v1_5'},
    key,
    base64urlBytes(parts[2]),
    encoder.encode(parts[0]+'.'+parts[1])
  );
  if(!ok) throw new Error('OIDC signature verification failed');

  const now=Math.floor(Date.now()/1000);
  const aud=Array.isArray(payload.aud)?payload.aud:[payload.aud];
  if(payload.iss!==EXPECTED_ISSUER) throw new Error('OIDC issuer mismatch');
  if(!aud.includes(AUDIENCE)) throw new Error('OIDC audience mismatch');
  if(typeof payload.exp!=='number'||payload.exp<now-30) throw new Error('OIDC token expired');
  if(typeof payload.nbf==='number'&&payload.nbf>now+30) throw new Error('OIDC token not active');
  if(!repository(payload.repository)) throw new Error('OIDC repository claim invalid');
  if(!clean(payload.ref,256)||!clean(payload.workflow_ref,1024)) throw new Error('OIDC workflow claims missing');
  if(!['schedule','workflow_dispatch','push'].includes(String(payload.event_name))) throw new Error('OIDC event not allowed');

  return {
    runId:String(payload.run_id??''),
    runAttempt:String(payload.run_attempt??''),
    eventName:String(payload.event_name),
    actor:String(payload.actor??''),
    repository:String(payload.repository),
    ref:String(payload.ref),
    workflowRef:String(payload.workflow_ref)
  };
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

    const auth=req.headers.get('authorization')??'';
    if(!auth.startsWith('Bearer ')) return jsonResponse(401,{error:'missing-oidc-token'});
    const identity=await verifyGithubOidc(auth.slice(7));

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
    const validUntil=new Date(observedAt.getTime()+90*60*1000);
    let accepted=0;

    for(const observation of body.observations){
      const targetRows=await sql`
        select
          provider,
          metadata->>'sourceRepository' as source_repository,
          metadata->>'sourceBranch' as source_branch
        from foundation.defence_estate_targets
        where target_id=${observation?.targetId}
          and lifecycle='active'
      `;
      const target=targetRows[0];
      if(!target||target.provider!=='railway'){
        return jsonResponse(400,{error:'release-head-target-not-allowed'});
      }

      const expectedWorkflowRef=
        identity.repository+'/'+EXPECTED_WORKFLOW_PATH+'@refs/heads/'+EXPECTED_WORKFLOW_BRANCH;

      if(
        identity.ref!=='refs/heads/'+EXPECTED_WORKFLOW_BRANCH||
        identity.workflowRef!==expectedWorkflowRef||
        String(identity.repository).toLowerCase()!==String(target.source_repository??'').toLowerCase()||
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
        Number.isNaN(Date.parse(observation.headCommittedAt))
      ){
        return jsonResponse(400,{error:'invalid-release-head-observation'});
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
            githubRef:identity.ref,
            githubWorkflowRef:identity.workflowRef
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
