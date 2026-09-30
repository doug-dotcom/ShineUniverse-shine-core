const EXPECTED_ISSUER='https://token.actions.githubusercontent.com';
const DEFAULT_JWKS_TTL_MS=5*60*1000;
const MAX_TOKEN_LENGTH=16*1024;
const CLOCK_SKEW_SECONDS=30;
const DEFAULT_MAX_TOKEN_AGE_SECONDS=600;
const encoder=new TextEncoder();
const decoder=new TextDecoder();

const oidcError=message=>new Error('OIDC '+message);
const cleanString=(value,max=1024)=>typeof value==='string'&&value.length>0&&value.length<=max&&!/[\u0000-\u001f\u007f]/.test(value);
const repositoryClaim=value=>typeof value==='string'&&/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(value);
const workflowPath=value=>typeof value==='string'&&/^\.github\/workflows\/[A-Za-z0-9_.-]+\.ya?ml$/.test(value);
const branchName=value=>typeof value==='string'&&/^[A-Za-z0-9._/-]{1,128}$/.test(value)&&!value.includes('..');
const numericId=value=>typeof value==='string'&&/^[0-9]{1,20}$/.test(value);
const sha40=value=>typeof value==='string'&&/^[a-f0-9]{40}$/i.test(value);

const base64urlBytes=value=>{
  if(typeof value!=='string'||!/^[A-Za-z0-9_-]*$/.test(value)) throw oidcError('token encoding invalid');
  try{
    const padded=value.replace(/-/g,'+').replace(/_/g,'/')+'='.repeat((4-value.length%4)%4);
    const binary=atob(padded);
    return Uint8Array.from(binary,c=>c.charCodeAt(0));
  }catch{
    throw oidcError('token encoding invalid');
  }
};

const parsePart=(value,label)=>{
  try{
    const parsed=JSON.parse(decoder.decode(base64urlBytes(value)));
    if(!parsed||typeof parsed!=='object'||Array.isArray(parsed)) throw new Error('not-object');
    return parsed;
  }catch{
    throw oidcError(label+' invalid');
  }
};

const validatePolicy=policy=>{
  if(!policy||typeof policy!=='object') throw oidcError('verification policy missing');
  if(!cleanString(policy.audience,256)) throw oidcError('verification audience invalid');
  if(!Array.isArray(policy.allowedEvents)||policy.allowedEvents.length===0||policy.allowedEvents.some(value=>!cleanString(value,64))) throw oidcError('verification event policy invalid');
  if(policy.expectedRepository!==undefined&&!repositoryClaim(policy.expectedRepository)) throw oidcError('verification repository policy invalid');
  if(policy.expectedRef!==undefined&&!cleanString(policy.expectedRef,256)) throw oidcError('verification ref policy invalid');
  if(policy.expectedWorkflowRef!==undefined&&!cleanString(policy.expectedWorkflowRef,1024)) throw oidcError('verification workflow policy invalid');
  if(policy.expectedWorkflow!==undefined){
    if(!policy.expectedWorkflow||!workflowPath(policy.expectedWorkflow.path)||!branchName(policy.expectedWorkflow.branch)) throw oidcError('verification workflow policy invalid');
  }
  if(policy.expectedWorkflowRef!==undefined&&policy.expectedWorkflow!==undefined) throw oidcError('verification workflow policy ambiguous');
  if(policy.expectedRepositoryId!==undefined&&!numericId(String(policy.expectedRepositoryId))) throw oidcError('verification repository id policy invalid');
  if(policy.expectedRepositoryOwner!==undefined&&!cleanString(policy.expectedRepositoryOwner,128)) throw oidcError('verification repository owner policy invalid');
  if(policy.expectedRepositoryOwnerId!==undefined&&!numericId(String(policy.expectedRepositoryOwnerId))) throw oidcError('verification repository owner id policy invalid');
  if(policy.expectedRefType!==undefined&&!['branch','tag'].includes(policy.expectedRefType)) throw oidcError('verification ref type policy invalid');
  if(policy.expectedRunnerEnvironment!==undefined&&!['github-hosted','self-hosted'].includes(policy.expectedRunnerEnvironment)) throw oidcError('verification runner environment policy invalid');
  if(policy.subjectMode!==undefined&&policy.subjectMode!=='repository-ref') throw oidcError('verification subject policy invalid');
  if(policy.expectedJobWorkflowRef!==undefined&&!cleanString(policy.expectedJobWorkflowRef,1024)) throw oidcError('verification job workflow ref policy invalid');
  if(policy.expectedJobWorkflowSha!==undefined&&!sha40(String(policy.expectedJobWorkflowSha))) throw oidcError('verification job workflow sha policy invalid');
  if(policy.maxTokenAgeSeconds!==undefined&&(!Number.isInteger(policy.maxTokenAgeSeconds)||policy.maxTokenAgeSeconds<60||policy.maxTokenAgeSeconds>3600)) throw oidcError('verification freshness policy invalid');
};

export function createGithubActionsOidcVerifier({
  fetchImpl=globalThis.fetch,
  cryptoImpl=globalThis.crypto,
  now=()=>Date.now(),
  jwksTtlMs=DEFAULT_JWKS_TTL_MS
}={}){
  if(typeof fetchImpl!=='function') throw new Error('fetch implementation required');
  if(!cryptoImpl?.subtle) throw new Error('WebCrypto implementation required');
  if(typeof now!=='function') throw new Error('clock implementation required');
  if(!Number.isFinite(jwksTtlMs)||jwksTtlMs<0) throw new Error('jwksTtlMs invalid');

  let metadataPromise=null;
  let jwksCache=null;
  let jwksPromise=null;

  const getMetadata=()=>metadataPromise??=(async()=>{
    const response=await fetchImpl(EXPECTED_ISSUER+'/.well-known/openid-configuration',{redirect:'error'});
    if(!response?.ok) throw oidcError('metadata unavailable');
    const body=await response.json();
    if(body?.issuer!==EXPECTED_ISSUER) throw oidcError('metadata issuer mismatch');
    if(!cleanString(body?.jwks_uri,1024)) throw oidcError('jwks_uri missing');
    let url;
    try{url=new URL(body.jwks_uri)}catch{throw oidcError('jwks_uri invalid')}
    if(url.protocol!=='https:'||url.origin!==new URL(EXPECTED_ISSUER).origin) throw oidcError('jwks_uri origin mismatch');
    return {jwksUri:url.toString()};
  })();

  const getJwks=async(force=false)=>{
    const currentTime=now();
    if(!force&&jwksCache&&currentTime-jwksCache.fetchedAt<jwksTtlMs) return jwksCache;
    if(!force&&jwksPromise) return jwksPromise;
    const request=(async()=>{
      const metadata=await getMetadata();
      const response=await fetchImpl(metadata.jwksUri,{redirect:'error'});
      if(!response?.ok) throw oidcError('JWKS unavailable');
      const body=await response.json();
      if(!Array.isArray(body?.keys)||body.keys.length===0||body.keys.length>100) throw oidcError('JWKS invalid');
      const cache={keys:body.keys,fetchedAt:now()};
      jwksCache=cache;
      return cache;
    })();
    jwksPromise=request;
    try{return await request}finally{if(jwksPromise===request) jwksPromise=null}
  };

  const findSigningKey=async kid=>{
    let set=await getJwks(false);
    let jwk=set.keys.find(key=>key&&key.kid===kid);
    if(!jwk){
      set=await getJwks(true);
      jwk=set.keys.find(key=>key&&key.kid===kid);
    }
    if(!jwk) throw oidcError('signing key not found after refresh');
    if(jwk.kty!=='RSA') throw oidcError('signing key type invalid');
    if(jwk.use!==undefined&&jwk.use!=='sig') throw oidcError('signing key use invalid');
    if(jwk.alg!==undefined&&jwk.alg!=='RS256') throw oidcError('signing key algorithm invalid');
    return jwk;
  };

  const verify=async(token,policy)=>{
    validatePolicy(policy);
    if(!cleanString(token,MAX_TOKEN_LENGTH)) throw oidcError('token missing or too large');
    const parts=token.split('.');
    if(parts.length!==3) throw oidcError('token format invalid');
    const header=parsePart(parts[0],'header');
    const payload=parsePart(parts[1],'payload');
    if(header.alg!=='RS256'||!cleanString(header.kid,256)) throw oidcError('signing header unsupported');

    const jwk=await findSigningKey(header.kid);
    let key;
    try{
      key=await cryptoImpl.subtle.importKey('jwk',jwk,{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['verify']);
    }catch{
      throw oidcError('signing key import failed');
    }
    const signatureValid=await cryptoImpl.subtle.verify(
      {name:'RSASSA-PKCS1-v1_5'},
      key,
      base64urlBytes(parts[2]),
      encoder.encode(parts[0]+'.'+parts[1])
    );
    if(!signatureValid) throw oidcError('signature verification failed');

    const nowSeconds=Math.floor(now()/1000);
    const audiences=Array.isArray(payload.aud)?payload.aud:[payload.aud];
    if(payload.iss!==EXPECTED_ISSUER) throw oidcError('issuer mismatch');
    if(!audiences.includes(policy.audience)) throw oidcError('audience mismatch');
    if(typeof payload.exp!=='number'||payload.exp<nowSeconds-CLOCK_SKEW_SECONDS) throw oidcError('token expired');
    if(typeof payload.nbf==='number'&&payload.nbf>nowSeconds+CLOCK_SKEW_SECONDS) throw oidcError('token not active');
    if(typeof payload.iat!=='number'||!Number.isFinite(payload.iat)) throw oidcError('issued-at claim missing');
    if(payload.iat>nowSeconds+CLOCK_SKEW_SECONDS) throw oidcError('issued-at time invalid');
    const maxTokenAgeSeconds=policy.maxTokenAgeSeconds??DEFAULT_MAX_TOKEN_AGE_SECONDS;
    if(payload.iat<nowSeconds-maxTokenAgeSeconds-CLOCK_SKEW_SECONDS) throw oidcError('token too old');
    if(!repositoryClaim(payload.repository)) throw oidcError('repository claim invalid');
    if(!numericId(String(payload.repository_id??''))) throw oidcError('repository id claim invalid');
    if(!cleanString(payload.repository_owner,128)) throw oidcError('repository owner claim invalid');
    if(!numericId(String(payload.repository_owner_id??''))) throw oidcError('repository owner id claim invalid');
    if(String(payload.repository).split('/')[0]!==String(payload.repository_owner)) throw oidcError('repository owner mismatch');
    if(!/^[0-9]{1,32}$/.test(String(payload.run_id??''))) throw oidcError('run id claim invalid');
    if(!/^[0-9]{1,16}$/.test(String(payload.run_attempt??''))) throw oidcError('run attempt claim invalid');
    if(!cleanString(payload.ref,256)||!cleanString(payload.workflow_ref,1024)) throw oidcError('workflow claims missing');
    if(!['branch','tag'].includes(String(payload.ref_type??''))) throw oidcError('ref type claim invalid');
    if(!['github-hosted','self-hosted'].includes(String(payload.runner_environment??''))) throw oidcError('runner environment claim invalid');
    if(!sha40(String(payload.workflow_sha??''))) throw oidcError('workflow sha claim invalid');
    if(payload.job_workflow_ref!==undefined&&!cleanString(payload.job_workflow_ref,1024)) throw oidcError('job workflow ref claim invalid');
    if(payload.job_workflow_sha!==undefined&&!sha40(String(payload.job_workflow_sha))) throw oidcError('job workflow sha claim invalid');
    if(!cleanString(payload.sub,1024)) throw oidcError('subject claim invalid');
    if(!policy.allowedEvents.includes(String(payload.event_name))) throw oidcError('event not allowed');
    if(policy.expectedRepository!==undefined&&payload.repository!==policy.expectedRepository) throw oidcError('repository mismatch');
    if(policy.expectedRepositoryId!==undefined&&String(payload.repository_id)!==String(policy.expectedRepositoryId)) throw oidcError('repository id mismatch');
    if(policy.expectedRepositoryOwner!==undefined&&payload.repository_owner!==policy.expectedRepositoryOwner) throw oidcError('repository owner mismatch');
    if(policy.expectedRepositoryOwnerId!==undefined&&String(payload.repository_owner_id)!==String(policy.expectedRepositoryOwnerId)) throw oidcError('repository owner id mismatch');
    if(policy.expectedRef!==undefined&&payload.ref!==policy.expectedRef) throw oidcError('ref mismatch');
    if(policy.expectedRefType!==undefined&&payload.ref_type!==policy.expectedRefType) throw oidcError('ref type mismatch');
    if(policy.expectedRunnerEnvironment!==undefined&&payload.runner_environment!==policy.expectedRunnerEnvironment) throw oidcError('runner environment mismatch');
    if(policy.expectedJobWorkflowRef!==undefined&&payload.job_workflow_ref!==policy.expectedJobWorkflowRef) throw oidcError('job workflow ref mismatch');
    if(policy.expectedJobWorkflowSha!==undefined&&payload.job_workflow_sha!==policy.expectedJobWorkflowSha) throw oidcError('job workflow sha mismatch');

    let expectedWorkflowRef=policy.expectedWorkflowRef;
    if(policy.expectedWorkflow){
      expectedWorkflowRef=String(payload.repository)+'/'+policy.expectedWorkflow.path+'@refs/heads/'+policy.expectedWorkflow.branch;
    }
    if(expectedWorkflowRef!==undefined&&payload.workflow_ref!==expectedWorkflowRef) throw oidcError('workflow mismatch');

    if(policy.subjectMode==='repository-ref'){
      const [owner,repositoryName]=String(payload.repository).split('/');
      const legacy='repo:'+payload.repository+':ref:'+payload.ref;
      const immutable='repo:'+owner+'@'+payload.repository_owner_id+'/'+repositoryName+'@'+payload.repository_id+':ref:'+payload.ref;
      if(payload.sub!==legacy&&payload.sub!==immutable) throw oidcError('subject mismatch');
    }

    const sha=String(payload.sha??'');
    return {
      kid:String(header.kid),
      repository:String(payload.repository),
      repositoryId:String(payload.repository_id),
      repositoryOwner:String(payload.repository_owner),
      repositoryOwnerId:String(payload.repository_owner_id),
      ref:String(payload.ref),
      refType:String(payload.ref_type),
      workflowRef:String(payload.workflow_ref),
      jobWorkflowRef:payload.job_workflow_ref===undefined?'':String(payload.job_workflow_ref),
      jobWorkflowSha:payload.job_workflow_sha===undefined?'':String(payload.job_workflow_sha),
      runId:String(payload.run_id??''),
      runAttempt:String(payload.run_attempt??''),
      eventName:String(payload.event_name),
      actor:String(payload.actor??''),
      actorId:String(payload.actor_id??''),
      runnerEnvironment:String(payload.runner_environment),
      sha,
      workflowSha:String(payload.workflow_sha),
      subject:String(payload.sub),
      issuedAt:payload.iat
    };
  };

  return {verify,clearCache(){jwksCache=null;jwksPromise=null;metadataPromise=null}};
}

const defaultVerifier=createGithubActionsOidcVerifier();

export const verifyGithubActionsOidc=(token,policy)=>defaultVerifier.verify(token,policy);
export const GITHUB_ACTIONS_OIDC_ISSUER=EXPECTED_ISSUER;
export const GITHUB_ACTIONS_OIDC_VERIFIER_VERSION='1.3.0';
