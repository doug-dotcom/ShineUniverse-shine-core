#!/usr/bin/env node
import {spawnSync} from 'node:child_process';
import {validatePromotedReleaseResponse} from './promoted-release-response-v1.mjs';

const FIXED_AT='2026-09-30T03:26:26.478533+00:00';
const SOURCE_SHA='1a8148a8eb748a19ac03107d9e9ec7313297384b';
const ARTIFACT_SHA='3294e28293df667224ed9ab2551e2e5a6a88bab6f6805791bec14e7d22512692';

function queryJson(sql,label){
  const result=spawnSync(
    'psql',
    ['-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-c',sql],
    {encoding:'utf8',env:process.env}
  );

  if(result.status!==0){
    process.stderr.write(result.stdout||'');
    process.stderr.write(result.stderr||'');
    throw new Error(label+' producer query failed');
  }

  const lines=(result.stdout||'')
    .split('\n')
    .map(line=>line.trim())
    .filter(Boolean);

  if(lines.length!==1){
    throw new Error(label+' producer returned '+lines.length+' JSON rows');
  }

  try{
    return JSON.parse(lines[0]);
  }catch(error){
    throw new Error(label+' producer returned invalid JSON: '+error.message);
  }
}

const promotedSql=[
  'begin;',
  '',
  "create or replace function foundation.get_foundation_release_promotion_closure_status_v1(",
  "  p_environment text default 'production',",
  "  p_as_of timestamptz default now()",
  ')',
  'returns jsonb',
  'language sql',
  'stable',
  'security definer',
  "set search_path = ''",
  'as $parity_closed$',
  '  select jsonb_build_object(',
  "    'foundationReleasePromotionClosureStatusResponse','shine-foundation/release-promotion-closure-status-response-v1',",
  "    'schemaVersion','1.0.0',",
  "    'environment',p_environment,",
  "    'evaluatedAt',p_as_of,",
  "    'state','closed',",
  "    'reasonCode','canonical-source-truth-closed',",
  "    'releaseClosed',true,",
  "    'integrityVerified',true,",
  "    'receiptCurrent',true,",
  "    'runtimeReadinessClaimed',false,",
  "    'mutatesAuthoritativeTruth',false,",
  "    'binding',jsonb_build_object(",
  "      'bindingId','187d5232-83b5-4c2f-acc6-62da7a9a9515',",
  "      'foundationLayer',58,",
  "      'releaseRef','foundation:layer-58:1a8148a8',",
  "      'sourceRef','github://doug-dotcom/ShineUniverse-shine-core/commit/"+SOURCE_SHA+"',",
  "      'runtimeVersion','90',",
  "      'artifactSha256','"+ARTIFACT_SHA+"'",
  '    ),',
  "    'receipt',jsonb_build_object(",
  "      'closureId','df864db1-abe4-4a28-b784-7a1d7b83dc5d',",
  "      'closureSha256','38b479bb951e69e53438b8cf13637b4c67dba5f7965f6d520f90344721bc2b87',",
  "      'canonicalSourceTruthFingerprint','3e7ce8f50385b3fadddddc247d3573bf',",
  "      'closedAt','2026-09-30T03:16:26.554513+00:00'",
  '    )',
  '  );',
  '$parity_closed$;',
  '',
  "select foundation.get_foundation_promoted_release_v1('production','"+FIXED_AT+"'::timestamptz)::text;",
  '',
  'rollback;'
].join('\n');

const holdSql=[
  'begin;',
  '',
  "create or replace function foundation.get_foundation_release_promotion_closure_status_v1(",
  "  p_environment text default 'production',",
  "  p_as_of timestamptz default now()",
  ')',
  'returns jsonb',
  'language sql',
  'stable',
  'security definer',
  "set search_path = ''",
  'as $parity_hold$',
  '  select jsonb_build_object(',
  "    'foundationReleasePromotionClosureStatusResponse','shine-foundation/release-promotion-closure-status-response-v1',",
  "    'schemaVersion','1.0.0',",
  "    'environment',p_environment,",
  "    'evaluatedAt',p_as_of,",
  "    'state','stale',",
  "    'reasonCode','promotion-closure-no-longer-current',",
  "    'releaseClosed',false,",
  "    'integrityVerified',true,",
  "    'receiptCurrent',false,",
  "    'runtimeReadinessClaimed',false,",
  "    'mutatesAuthoritativeTruth',false,",
  "    'binding',jsonb_build_object(",
  "      'bindingId','187d5232-83b5-4c2f-acc6-62da7a9a9515',",
  "      'foundationLayer',58,",
  "      'releaseRef','foundation:layer-58:1a8148a8'",
  '    ),',
  "    'receipt',null",
  '  );',
  '$parity_hold$;',
  '',
  "select foundation.get_foundation_promoted_release_v1('production','"+FIXED_AT+"'::timestamptz)::text;",
  '',
  'rollback;'
].join('\n');

const promoted=queryJson(promotedSql,'promoted');
const promotedValidation=validatePromotedReleaseResponse(promoted);
if(!promotedValidation.ok){
  throw new Error(
    'actual SQL promoted response violates pinned consumer contract: '
    +promotedValidation.errors.join('; ')
  );
}

if(
  promoted.state!=='promoted'
  || promoted.available!==true
  || promoted.promotedRelease?.sourceCommitSha!==SOURCE_SHA
  || promoted.promotedRelease?.artifactSha256!==ARTIFACT_SHA
  || promoted.runtimeReadinessClaimed!==false
  || promoted.mutatesAuthoritativeTruth!==false
){
  throw new Error('actual SQL promoted response lost Layer-61 semantic invariants');
}

const hold=queryJson(holdSql,'hold');
const holdValidation=validatePromotedReleaseResponse(hold);
if(!holdValidation.ok){
  throw new Error(
    'actual SQL hold response violates pinned consumer contract: '
    +holdValidation.errors.join('; ')
  );
}

if(
  hold.state!=='hold'
  || hold.available!==false
  || hold.promotedRelease!==null
  || 'promotedReleaseSha256' in hold
  || hold.reasonCode!=='promotion-closure-no-longer-current'
  || hold.runtimeReadinessClaimed!==false
  || hold.mutatesAuthoritativeTruth!==false
){
  throw new Error('actual SQL hold response lost fail-closed semantics');
}

console.log(
  'FOUNDATION PROMOTED RELEASE PRODUCER/CONSUMER PARITY: PASS '
  +'promoted='+promoted.promotedRelease.releaseRef+' '
  +'hold='+hold.reasonCode
);
