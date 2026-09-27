import {gitBlobSha,validateReviewChecklist} from './review-checklist-lib-v1.mjs';

export const SHINE_DEFENCE_EVIDENCE_ENGINE='deterministic-token-overlap-v1';

const STOP=new Set([
  'a','an','and','are','as','at','be','before','by','can','cannot','do','does','for','from','has','have','if','in','into','is','it','its','may',
  'must','not','of','on','only','or','rather','so','that','the','their','this','to','use','used','uses','using','when','where','with','without',
  'application','app','reviewed','release','required','requirement','requirements','explicit','appropriate','exact','canonical','defence','shine'
]);

function fail(message){throw new Error(message)}

function stem(token){
  if(token.length>6&&token.endsWith('ing'))return token.slice(0,-3);
  if(token.length>5&&token.endsWith('ed'))return token.slice(0,-2);
  if(token.length>5&&token.endsWith('es'))return token.slice(0,-2);
  if(token.length>4&&token.endsWith('s'))return token.slice(0,-1);
  return token;
}

function tokens(text){
  const values=String(text||'').toLowerCase().match(/[a-z0-9]+/g)||[];
  return [...new Set(values.map(stem).filter(token=>token.length>=3&&!STOP.has(token)))];
}

function evidenceText(evidence){
  return [evidence.source,evidence.kind,evidence.reference,evidence.summary].filter(Boolean).join(' ');
}

function confidence(score,matchedCount){
  if(score>=0.45&&matchedCount>=3)return 'high';
  if(score>=0.25&&matchedCount>=2)return 'medium';
  return 'low';
}

export function scoreEvidence(requirement,evidence){
  const req=tokens(requirement);
  const ev=tokens(evidenceText(evidence));
  if(!req.length||!ev.length)return null;
  const evSet=new Set(ev);
  const matched=req.filter(token=>evSet.has(token)).sort();
  if(!matched.length)return null;

  const coverage=matched.length/req.length;
  const density=matched.length/Math.min(req.length,ev.length);
  const raw=(coverage*0.7)+(density*0.3);
  const score=Math.round(Math.min(1,raw)*1000)/1000;
  if(score<0.08)return null;

  return {
    evidenceId:evidence.evidenceId,
    score,
    confidence:confidence(score,matched.length),
    matchedTerms:matched,
    reason:'Matched '+matched.length+' requirement term'+(matched.length===1?'':'s')+': '+matched.join(', ')+'.'
  };
}

function flatItems(checklist){
  return (checklist.policyReviews||[]).flatMap(policy=>
    (policy.requirements||[]).map(item=>({policyId:policy.policyId,...item}))
  );
}

export function deriveSuggestionItems(checklist){
  return flatItems(checklist).map(item=>{
    const ranked=(checklist.candidateEvidence||[])
      .map(evidence=>scoreEvidence(item.requirement,evidence))
      .filter(Boolean)
      .sort((a,b)=>b.score-a.score||a.evidenceId.localeCompare(b.evidenceId))
      .slice(0,3);
    return {
      itemId:item.itemId,
      policyId:item.policyId,
      evidenceGap:ranked.length===0,
      suggestions:ranked
    };
  });
}

export function buildEvidenceSuggestions({candidate,checklist,registry,registryBytes,generatedAt,readArtefact}){
  if(candidate.status!=='pending_review')fail('evidence suggestions require a pending_review candidate');
  if(typeof readArtefact!=='function')fail('readArtefact callback is required');
  const checklistFailures=validateReviewChecklist({checklist,candidate,registry,registryBytes,readArtefact});
  if(checklistFailures.length)fail('canonical checklist invalid: '+checklistFailures.join('; '));
  if(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/.test(generatedAt||'')||!Number.isFinite(Date.parse(generatedAt)))fail('generatedAt must be an ISO UTC timestamp');
  if(Date.parse(generatedAt)<Date.parse(checklist.generatedAt))fail('suggestions cannot predate checklist generation');

  const items=deriveSuggestionItems(checklist);

  return {
    artifact:'shine-defence/review-evidence-suggestions-v1',
    version:'1.0.0',
    engine:SHINE_DEFENCE_EVIDENCE_ENGINE,
    candidateId:candidate.candidateId,
    appId:candidate.appId,
    repository:candidate.repository,
    releaseCommitSha:candidate.releaseCommitSha,
    profileBlobSha:candidate.profileBlobSha,
    profileVersion:candidate.profileVersion,
    checklistGeneratedAt:checklist.generatedAt,
    registryVersion:registry.version,
    registryBlobSha:gitBlobSha(registryBytes),
    generatedAt,
    items
  };
}

export function validateEvidenceSuggestions({artifact,candidate,checklist,registry,registryBytes,readArtefact}){
  const failures=[];
  if(!artifact||typeof artifact!=='object'||Array.isArray(artifact)){failures.push('suggestion artifact must be an object');return failures}
  if(artifact.artifact!=='shine-defence/review-evidence-suggestions-v1'||artifact.version!=='1.0.0')failures.push('unsupported suggestion artifact');
  if(artifact.engine!==SHINE_DEFENCE_EVIDENCE_ENGINE)failures.push('unsupported suggestion engine');
  if(typeof readArtefact!=='function')failures.push('readArtefact callback is required');
  if(failures.length)return failures;

  const bindings={
    candidateId:candidate.candidateId,
    appId:candidate.appId,
    repository:candidate.repository,
    releaseCommitSha:candidate.releaseCommitSha,
    profileBlobSha:candidate.profileBlobSha,
    profileVersion:candidate.profileVersion,
    checklistGeneratedAt:checklist.generatedAt,
    registryVersion:registry.version,
    registryBlobSha:gitBlobSha(registryBytes)
  };
  for(const [key,expected] of Object.entries(bindings))if(artifact[key]!==expected)failures.push(key+' binding mismatch');
  if(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/.test(artifact.generatedAt||'')||!Number.isFinite(Date.parse(artifact.generatedAt)))failures.push('invalid generatedAt');
  else if(Date.parse(artifact.generatedAt)<Date.parse(checklist.generatedAt))failures.push('generatedAt predates checklist');

  let checklistFailures=[];
  try{
    checklistFailures=validateReviewChecklist({checklist,candidate,registry,registryBytes,readArtefact});
  }catch(error){
    failures.push(String(error.message||error));
    return failures;
  }
  for(const failure of checklistFailures)failures.push('checklist: '+failure);
  if(checklistFailures.length)return failures;

  const expectedItems=deriveSuggestionItems(checklist);
  if(JSON.stringify(artifact.items)!==JSON.stringify(expectedItems))failures.push('suggestion items do not match deterministic engine output');
  return failures;
}


export function validateHistoricalEvidenceSuggestions({artifact,candidate,checklist}){
  const failures=[];
  if(!artifact||typeof artifact!=='object'||Array.isArray(artifact)){failures.push('suggestion artifact must be an object');return failures}
  if(artifact.artifact!=='shine-defence/review-evidence-suggestions-v1'||artifact.version!=='1.0.0')failures.push('unsupported suggestion artifact');
  if(artifact.engine!==SHINE_DEFENCE_EVIDENCE_ENGINE)failures.push('unsupported suggestion engine');

  const bindings={
    candidateId:candidate.candidateId,
    appId:candidate.appId,
    repository:candidate.repository,
    releaseCommitSha:candidate.releaseCommitSha,
    profileBlobSha:candidate.profileBlobSha,
    profileVersion:candidate.profileVersion,
    checklistGeneratedAt:checklist.generatedAt,
    registryVersion:checklist.registryVersion,
    registryBlobSha:checklist.registryBlobSha
  };
  for(const [key,expected] of Object.entries(bindings))if(artifact[key]!==expected)failures.push(key+' historical binding mismatch');

  if(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/.test(artifact.generatedAt||'')||!Number.isFinite(Date.parse(artifact.generatedAt)))failures.push('invalid generatedAt');
  else if(Date.parse(artifact.generatedAt)<Date.parse(checklist.generatedAt))failures.push('generatedAt predates checklist');

  const expectedItems=deriveSuggestionItems(checklist);
  if(JSON.stringify(artifact.items)!==JSON.stringify(expectedItems))failures.push('suggestion items do not match deterministic historical output');
  return failures;
}
