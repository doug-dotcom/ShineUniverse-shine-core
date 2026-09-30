export const SHINE_DEFENCE_ACTIVE_AUTHORITY_VERIFIER_VERSION='1.1.0';
export const SHINE_DEFENCE_AUTHORITY_HEARTBEAT_MAX_AGE_SECONDS=5400;

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

  let rows;
  try{
    rows=await sql`
      select
        lower(a.authority_sha) as authority_sha,
        a.authority_ref,
        lower(a.workflow_blob_sha) as workflow_blob_sha,
        a.activation_sequence,
        a.activation_kind,
        a.activated_at,
        foundation.get_defence_attestation_authority_sync_summary_v1(
          now(),
          ${SHINE_DEFENCE_AUTHORITY_HEARTBEAT_MAX_AGE_SECONDS}
        ) as sync_summary
      from foundation.current_defence_attestation_authority a
    `;
  }catch{
    throw new Error('OIDC active attestation authority heartbeat unavailable');
  }

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

  const summary=current.sync_summary;
  const latest=summary?.latestReceipt;
  const summaryCurrent=summary?.currentAuthority;
  const receiptAge=Number(summary?.receiptAgeSeconds);
  if(
    !summary||
    summary.state!=='pass'||
    summary.reasonCode!=='attestation-authority-sync-current'||
    !latest||
    !summaryCurrent||
    !Number.isFinite(receiptAge)||
    receiptAge<0||
    receiptAge>SHINE_DEFENCE_AUTHORITY_HEARTBEAT_MAX_AGE_SECONDS||
    String(summaryCurrent.authoritySha??'').toLowerCase()!==String(current.authority_sha).toLowerCase()||
    String(summaryCurrent.authorityRef??'')!==String(current.authority_ref)||
    Number(summaryCurrent.lineageSequence)!==Number(latest.lineageSequence)||
    String(latest.authoritySha??'').toLowerCase()!==String(current.authority_sha).toLowerCase()
  ){
    throw new Error('OIDC attestation authority heartbeat stale or mismatched');
  }

  return Object.freeze({
    authoritySha:String(current.authority_sha).toLowerCase(),
    authorityRef:String(current.authority_ref),
    workflowBlobSha:String(current.workflow_blob_sha??'').toLowerCase(),
    activationSequence:Number(current.activation_sequence),
    activationKind:String(current.activation_kind??''),
    activatedAt:String(current.activated_at??''),
    syncReceiptId:String(latest.receiptId??''),
    syncReceiptAgeSeconds:receiptAge,
    syncPublisherCommitSha:String(latest.publisherCommitSha??'').toLowerCase(),
    syncGithubRunId:String(latest.githubRunId??''),
    syncGithubRunAttempt:String(latest.githubRunAttempt??'')
  });
}
