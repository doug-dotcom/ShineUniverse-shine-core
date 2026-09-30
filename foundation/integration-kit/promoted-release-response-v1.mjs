const CONTRACT_ID='shine-foundation/promoted-release-response-v1';
const SCHEMA_VERSION='1.0.0';
const ENV=/^[a-z0-9][a-z0-9._-]*$/;
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const RELEASE=/^foundation:layer-[0-9]+:[a-f0-9]{8}$/;
const SOURCE=/^github:\/\/[^/]+\/[^/]+\/commit\/[a-fA-F0-9]{40}$/;
const SHA40=/^[a-f0-9]{40}$/;
const SHA64=/^[a-f0-9]{64}$/;
const FP32=/^[a-f0-9]{32}$/;
const CLOSURE_STATES=new Set(['closed','open','stale','invalid','blocked']);
const TOP_LEVEL=new Set([
  'foundationPromotedReleaseResponse','schemaVersion','environment',
  'evaluatedAt','available','state','reasonCode','promotionClosureState',
  'promotedRelease','promotedReleaseSha256','runtimeReadinessClaimed',
  'mutatesAuthoritativeTruth'
]);
const RELEASE_KEYS=new Set([
  'bindingId','releaseRef','foundationLayer','sourceRef','sourceCommitSha',
  'runtimeVersion','artifactSha256','closureId','closureSha256',
  'canonicalSourceTruthFingerprint','closedAt'
]);

function plain(value){
  return value!==null&&typeof value==='object'&&!Array.isArray(value);
}

function exact(value,allowed,path,errors){
  if(!plain(value)){
    errors.push(path+' must be an object');
    return false;
  }
  for(const key of Object.keys(value)){
    if(!allowed.has(key)) errors.push(path+'.'+key+' is not allowed');
  }
  return true;
}

function required(value,fields,path,errors){
  for(const field of fields){
    if(!(field in value)) errors.push(path+'.'+field+' is required');
  }
}

function dateTime(value,path,errors){
  if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}T/.test(value)||!Number.isFinite(Date.parse(value))){
    errors.push(path+' must be a valid ISO date-time');
  }
}

function nonEmpty(value,path,max,errors){
  if(typeof value!=='string'||value.length===0){
    errors.push(path+' must be a non-empty string');
    return;
  }
  if(value.length>max) errors.push(path+' exceeds '+max+' characters');
}

function validateRelease(value,errors){
  if(!exact(value,RELEASE_KEYS,'response.promotedRelease',errors)) return;
  required(value,[...RELEASE_KEYS],'response.promotedRelease',errors);
  if(typeof value.bindingId!=='string'||!UUID.test(value.bindingId)) errors.push('response.promotedRelease.bindingId must be a UUID');
  if(typeof value.releaseRef!=='string'||!RELEASE.test(value.releaseRef)) errors.push('response.promotedRelease.releaseRef is invalid');
  if(!Number.isInteger(value.foundationLayer)||value.foundationLayer<1) errors.push('response.promotedRelease.foundationLayer must be a positive integer');
  if(typeof value.sourceRef!=='string'||!SOURCE.test(value.sourceRef)) errors.push('response.promotedRelease.sourceRef is invalid');
  if(typeof value.sourceCommitSha!=='string'||!SHA40.test(value.sourceCommitSha)) errors.push('response.promotedRelease.sourceCommitSha must be lowercase SHA-1');
  nonEmpty(value.runtimeVersion,'response.promotedRelease.runtimeVersion',128,errors);
  if(typeof value.artifactSha256!=='string'||!SHA64.test(value.artifactSha256)) errors.push('response.promotedRelease.artifactSha256 must be lowercase SHA-256');
  if(typeof value.closureId!=='string'||!UUID.test(value.closureId)) errors.push('response.promotedRelease.closureId must be a UUID');
  if(typeof value.closureSha256!=='string'||!SHA64.test(value.closureSha256)) errors.push('response.promotedRelease.closureSha256 must be lowercase SHA-256');
  if(typeof value.canonicalSourceTruthFingerprint!=='string'||!FP32.test(value.canonicalSourceTruthFingerprint)) errors.push('response.promotedRelease.canonicalSourceTruthFingerprint must be lowercase 32-hex');
  dateTime(value.closedAt,'response.promotedRelease.closedAt',errors);
}

export function validatePromotedReleaseResponse(response){
  const errors=[];
  if(!exact(response,TOP_LEVEL,'response',errors)) return {ok:false,errors};
  required(response,[
    'foundationPromotedReleaseResponse','schemaVersion','environment',
    'evaluatedAt','available','state','reasonCode','promotionClosureState',
    'promotedRelease','runtimeReadinessClaimed','mutatesAuthoritativeTruth'
  ],'response',errors);

  if(response.foundationPromotedReleaseResponse!==CONTRACT_ID) errors.push('response.foundationPromotedReleaseResponse is unsupported');
  if(response.schemaVersion!==SCHEMA_VERSION) errors.push('response.schemaVersion is unsupported');
  if(typeof response.environment!=='string'||!ENV.test(response.environment)) errors.push('response.environment is invalid');
  dateTime(response.evaluatedAt,'response.evaluatedAt',errors);
  if(typeof response.available!=='boolean') errors.push('response.available must be boolean');
  if(!['promoted','hold'].includes(response.state)) errors.push('response.state is invalid');
  nonEmpty(response.reasonCode,'response.reasonCode',160,errors);
  if(!CLOSURE_STATES.has(response.promotionClosureState)) errors.push('response.promotionClosureState is invalid');
  if(response.runtimeReadinessClaimed!==false) errors.push('response.runtimeReadinessClaimed must be false');
  if(response.mutatesAuthoritativeTruth!==false) errors.push('response.mutatesAuthoritativeTruth must be false');

  if(response.state==='promoted'){
    if(response.available!==true) errors.push('promoted response must be available');
    if(response.reasonCode!=='promotion-closure-current') errors.push('promoted response reasonCode is invalid');
    if(response.promotionClosureState!=='closed') errors.push('promoted response requires closed promotion');
    validateRelease(response.promotedRelease,errors);
    if(typeof response.promotedReleaseSha256!=='string'||!SHA64.test(response.promotedReleaseSha256)){
      errors.push('promoted response requires promotedReleaseSha256');
    }
  }

  if(response.state==='hold'){
    if(response.available!==false) errors.push('hold response must not be available');
    if(response.promotedRelease!==null) errors.push('hold response promotedRelease must be null');
    if('promotedReleaseSha256' in response) errors.push('hold response must not carry promotedReleaseSha256');
  }

  if(response.available===true&&response.state!=='promoted') errors.push('available response must be promoted');
  if(response.available===false&&response.state!=='hold') errors.push('unavailable response must be hold');

  return {ok:errors.length===0,errors};
}

export function assertPromotedReleaseResponse(response){
  const result=validatePromotedReleaseResponse(response);
  if(!result.ok) throw new TypeError(result.errors.join('; '));
  return structuredClone(response);
}

export const PROMOTED_RELEASE_RESPONSE_CONTRACT=Object.freeze({
  id:CONTRACT_ID,
  schemaVersion:SCHEMA_VERSION
});
