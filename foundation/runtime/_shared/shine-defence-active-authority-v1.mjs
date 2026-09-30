export const SHINE_DEFENCE_ACTIVE_AUTHORITY_VERIFIER_VERSION='1.0.0';

const sha40=value=>typeof value==='string'&&/^[a-f0-9]{40}$/i.test(value);
const clean=value=>typeof value==='string'&&value.length>0&&value.length<=1024&&!/[\u0000-\u001f\u007f]/.test(value);

export async function verifyLiveDefenceAttestationAuthority({sql,identity}={}){
  if(typeof sql!=='function') throw new TypeError('postgres client required');
  if(!identity||typeof identity!=='object') throw new TypeError('verified OIDC identity required');

  const jobWorkflowSha=String(identity.jobWorkflowSha??'');
  const jobWorkflowRef=String(identity.jobWorkflowRef??'');
  if(!sha40(jobWorkflowSha)||!clean(jobWorkflowRef)){
    throw new Error('OIDC reusable workflow authority claims missing');
  }

  const rows=await sql`
    select
      lower(authority_sha) as authority_sha,
      authority_ref,
      lower(workflow_blob_sha) as workflow_blob_sha,
      activation_sequence,
      activation_kind,
      activated_at
    from foundation.current_defence_attestation_authority
  `;
  const current=rows?.[0];
  if(!current||!sha40(String(current.authority_sha??''))||!clean(current.authority_ref)){
    throw new Error('OIDC active attestation authority missing');
  }

  if(
    jobWorkflowSha.toLowerCase()!==String(current.authority_sha).toLowerCase()||
    jobWorkflowRef!==String(current.authority_ref)
  ){
    throw new Error('OIDC attestation authority mismatch');
  }

  return Object.freeze({
    authoritySha:String(current.authority_sha).toLowerCase(),
    authorityRef:String(current.authority_ref),
    workflowBlobSha:String(current.workflow_blob_sha??'').toLowerCase(),
    activationSequence:Number(current.activation_sequence),
    activationKind:String(current.activation_kind??''),
    activatedAt:String(current.activated_at??'')
  });
}
