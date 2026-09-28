import postgres from 'npm:postgres@3.4.9';

const AUDIENCE='shine-defence-rollback-readiness';
const EXPECTED_ISSUER='https://token.actions.githubusercontent.com';
const EXPECTED_WORKFLOW_PATH='.github/workflows/shine-defence-release-head.yml';
const EXPECTED_WORKFLOW_BRANCH='main';
const MAX_BODY_BYTES=64*1024;
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

  const repo=String(payload.repository);
  const expectedWorkflowRef=repo+'/'+EXPECTED_WORKFLOW_PATH+'@refs/heads/'+EXPECTED_WORKFLOW_BRANCH;
  if(payload.ref!=='refs/heads/'+EXPECTED_WORKFLOW_BRANCH) throw new Error('OIDC ref mismatch');
  if(payload.workflow_ref!==expectedWorkflowRef) throw new Error('OIDC workflow mismatch');

  return {
    runId:String(payload.run_id??''),
    runAttempt:String(payload.run_attempt??''),
    eventName:String(payload.event_name),
    actor:String(payload.actor??''),
    repository:repo
  };
}

const jsonResponse=(status:number,body:unknown)=>new Response(JSON.stringify(body),{
  status,
  headers:{'content-type':'application/json','cache-control':'no-store'}
});

async function verifyTargetBinding(target:string,repo:string){
  const rows=await sql`
    select
      provider,
      metadata->>'sourceRepository' as source_repository
    from foundation.defence_estate_targets
    where target_id=${target}
      and lifecycle='active'
      and required_for_estate
  `;
  const row=rows[0];
  return Boolean(
    row&&
    row.provider==='railway'&&
    String(row.source_repository??'').toLowerCase()===repo.toLowerCase()
  );
}

Deno.serve(async(req:Request)=>{
  try{
    if(req.method!=='POST') return jsonResponse(405,{error:'method-not-allowed'});
    const contentLength=Number(req.headers.get('content-length')||0);
    if(contentLength>MAX_BODY_BYTES) return jsonResponse(413,{error:'body-too-large'});

    const auth=req.headers.get('authorization')??'';
    if(!auth.startsWith('Bearer ')) return jsonResponse(401,{error:'missing-oidc-token'});
    const identity=await verifyGithubOidc(auth.slice(7));

    const raw=await req.text();
    if(raw.length>MAX_BODY_BYTES) return jsonResponse(413,{error:'body-too-large'});
    const body=JSON.parse(raw||'{}');

    if(body?.action==='claim'){
      if(!targetId(body?.targetId)) return jsonResponse(400,{error:'invalid-target'});
      if(!(await verifyTargetBinding(body.targetId,identity.repository))){
        return jsonResponse(401,{error:'rollback-oidc-source-mismatch'});
      }
      const rows=await sql`
        select foundation.get_defence_rollback_claim_v1(${body.targetId}) as claim
      `;
      const claim=rows[0]?.claim??null;
      if(!claim) return jsonResponse(400,{error:'rollback-claim-unavailable'});
      return jsonResponse(200,{
        status:'ok',
        contract:'shine-defence/rollback-readiness-claim-response-v1',
        claim
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

    if(!(await verifyTargetBinding(submission.targetId,identity.repository))){
      return jsonResponse(401,{error:'rollback-oidc-source-mismatch'});
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
          githubRepository:identity.repository
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
      result
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
