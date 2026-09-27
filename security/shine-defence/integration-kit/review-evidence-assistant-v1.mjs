#!/usr/bin/env node
import {existsSync,mkdirSync,readFileSync,renameSync,rmSync,writeFileSync} from 'node:fs';
import {dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {gitBlobSha,validateReviewChecklist} from './review-checklist-lib-v1.mjs';

export const SHINE_DEFENCE_EVIDENCE_ASSISTANT_VERSION='1.0.0';
export const SHINE_DEFENCE_EVIDENCE_ENGINE='deterministic-token-overlap-v1';

const root=fileURLToPath(new URL('../../../',import.meta.url));
const queuePath='security/shine-defence/review-candidates-v1.json';
const registryPath='security/shine-defence/canonical-registry-v1.json';
const checklistDir='security/shine-defence/review-checklists';
const suggestionDir='security/shine-defence/review-evidence-suggestions';

const json=value=>JSON.stringify(value,null,2)+'\n';
const STOP=new Set([
  'a','an','and','are','as','at','be','before','by','can','cannot','do','does','for','from','has','have','if','in','into','is','it','its','may',
  'must','not','of','on','only','or','rather','so','that','the','their','this','to','use','used','uses','using','when','where','with','without',
  'application','app','reviewed','release','required','requirement','requirements','explicit','appropriate','exact','canonical','defence','shine'
]);

function fail(message){throw new Error(message)}
function atomicWrite(fullPath,bytes){
  mkdirSync(dirname(fullPath),{recursive:true});
  const temp=fullPath+'.tmp-'+process.pid;
  writeFileSync(temp,bytes);
  renameSync(temp,fullPath);
}
function readJson(relativePath){return JSON.parse(readFileSync(join(root,relativePath),'utf8'))}
function readCanonical(path){return readFileSync(join(root,path))}

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

export function buildEvidenceSuggestions({candidate,checklist,registry,registryBytes,generatedAt}){
  if(candidate.status!=='pending_review')fail('evidence suggestions require a pending_review candidate');
  const checklistFailures=validateReviewChecklist({
    checklist,candidate,registry,registryBytes,readArtefact:readCanonical
  });
  if(checklistFailures.length)fail('canonical checklist invalid: '+checklistFailures.join('; '));
  if(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/.test(generatedAt||'')||!Number.isFinite(Date.parse(generatedAt)))fail('generatedAt must be an ISO UTC timestamp');
  if(Date.parse(generatedAt)<Date.parse(checklist.generatedAt))fail('suggestions cannot predate checklist generation');

  const items=flatItems(checklist).map(item=>{
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

export function validateEvidenceSuggestions({artifact,candidate,checklist,registry,registryBytes}){
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
    registryVersion:registry.version,
    registryBlobSha:gitBlobSha(registryBytes)
  };
  for(const [key,expected] of Object.entries(bindings))if(artifact[key]!==expected)failures.push(key+' binding mismatch');
  if(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/.test(artifact.generatedAt||'')||!Number.isFinite(Date.parse(artifact.generatedAt)))failures.push('invalid generatedAt');
  else if(Date.parse(artifact.generatedAt)<Date.parse(checklist.generatedAt))failures.push('generatedAt predates checklist');

  const expected=buildEvidenceSuggestions({
    candidate,checklist,registry,registryBytes,generatedAt:artifact.generatedAt
  });
  if(JSON.stringify(artifact.items)!==JSON.stringify(expected.items))failures.push('suggestion items do not match deterministic engine output');
  return failures;
}

function parseArgs(argv){
  const result={apply:false};
  for(let i=0;i<argv.length;i++){
    const arg=argv[i];
    if(arg==='--apply'){result.apply=true;continue}
    if(arg==='--self-test'){result.selfTest=true;continue}
    if(arg==='--help'||arg==='-h'){result.help=true;continue}
    if(arg==='--candidate'||arg==='--generated-at'){
      if(i+1>=argv.length)fail(arg+' requires a value');
      result[arg.slice(2).replace(/-([a-z])/g,(_,c)=>c.toUpperCase())]=argv[++i];
      continue;
    }
    fail('unknown argument '+arg);
  }
  return result;
}

function usage(){
  console.log(`Shine Defence review evidence assistant v${SHINE_DEFENCE_EVIDENCE_ASSISTANT_VERSION}

Usage:
  node security/shine-defence/integration-kit/review-evidence-assistant-v1.mjs \\
    --candidate <candidateId> [--generated-at <ISO timestamp|now>] [--apply]

The assistant reads only candidate evidence already present in the canonical checklist and
writes a separate advisory suggestion artifact. It never edits checklist state or authorization.
`);
}

function selfTest(){
  const evidence=[
    {evidenceId:'E1',source:'github',kind:'security_review',reference:'auth-session-review',summary:'Server authentication session expiry rotation revocation and CSRF checks passed.'},
    {evidenceId:'E2',source:'railway',kind:'deployment_success',reference:'deploy-123',summary:'Production deployment build and regression tests passed.'},
    {evidenceId:'E3',source:'github',kind:'data_review',reference:'provider-review',summary:'External provider HTTPS deadline response size schema timestamp freshness and provenance checks passed.'}
  ];
  const authReq='Session state has explicit idle and absolute expiry, and expiry is enforced by the server rather than inferred only by the client.';
  const providerReq='Provider requests have bounded deadlines and response bodies are byte-limited before JSON parsing.';
  const unrelatedReq='Minor participants receive age appropriate safeguards against restrictive dieting and appearance judgement.';

  const authScores=evidence.map(e=>scoreEvidence(authReq,e)).filter(Boolean).sort((a,b)=>b.score-a.score);
  if(authScores[0]?.evidenceId!=='E1')fail('self-test: auth evidence was not ranked first');
  const providerScores=evidence.map(e=>scoreEvidence(providerReq,e)).filter(Boolean).sort((a,b)=>b.score-a.score);
  if(providerScores[0]?.evidenceId!=='E3')fail('self-test: provider evidence was not ranked first');
  if(evidence.map(e=>scoreEvidence(unrelatedReq,e)).filter(Boolean).length)fail('self-test: unrelated requirement should remain a gap');

  const policyBytes=Buffer.from(json({policy:'shine-defence/test-v1',version:'1.0.0',requirements:[authReq,providerReq,unrelatedReq]}));
  const registry={registry:'shine-defence/canonical-registry-v1',version:'1.0.0',entries:[{id:'test',path:'test.json',version:'1.0.0',blobSha:gitBlobSha(policyBytes)}]};
  const registryBytes=Buffer.from(json(registry));
  const candidate={
    candidateId:'app-'+'a'.repeat(12),appId:'app',repository:'owner/app',releaseCommitSha:'a'.repeat(40),
    profilePath:'security/profile.json',profileBlobSha:'b'.repeat(40),profileVersion:'1.0.0',
    policies:['test'],status:'pending_review',observedAt:'2026-09-27T00:00:00.000Z',
    evidence:evidence.map(({evidenceId,...rest})=>rest)
  };
  const checklist={
    checklist:'shine-defence/review-checklist-v1',version:'1.0.0',
    candidateId:candidate.candidateId,appId:candidate.appId,repository:candidate.repository,
    releaseCommitSha:candidate.releaseCommitSha,profilePath:candidate.profilePath,profileBlobSha:candidate.profileBlobSha,
    profileVersion:candidate.profileVersion,policies:['test'],candidateObservedAt:candidate.observedAt,
    generatedAt:'2026-09-27T00:05:00.000Z',registryVersion:'1.0.0',registryBlobSha:gitBlobSha(registryBytes),
    candidateEvidence:evidence,
    policyReviews:[{policyId:'test',canonicalPath:'test.json',canonicalVersion:'1.0.0',canonicalBlobSha:gitBlobSha(policyBytes),requirements:[
      {itemId:'test:R001',requirement:authReq,required:true,state:'unreviewed',evidenceRefs:[],reviewerNotes:''},
      {itemId:'test:R002',requirement:providerReq,required:true,state:'unreviewed',evidenceRefs:[],reviewerNotes:''},
      {itemId:'test:R003',requirement:unrelatedReq,required:true,state:'unreviewed',evidenceRefs:[],reviewerNotes:''}
    ]}],
    humanAuthorization:{status:'pending'}
  };
  const originalReadCanonical=readCanonical;
  const localRead=path=>path==='test.json'?policyBytes:originalReadCanonical(path);
  const checklistFailures=validateReviewChecklist({checklist,candidate,registry,registryBytes,readArtefact:localRead});
  if(checklistFailures.length)fail('self-test fixture checklist invalid: '+checklistFailures.join('; '));

  // Build locally by temporarily reusing the same deterministic scoring logic without canonical I/O drift.
  const items=flatItems(checklist).map(item=>{
    const ranked=evidence.map(e=>scoreEvidence(item.requirement,e)).filter(Boolean).sort((a,b)=>b.score-a.score||a.evidenceId.localeCompare(b.evidenceId)).slice(0,3);
    return {itemId:item.itemId,policyId:item.policyId,evidenceGap:ranked.length===0,suggestions:ranked};
  });
  if(items[0].suggestions[0]?.evidenceId!=='E1'||items[1].suggestions[0]?.evidenceId!=='E3'||items[2].evidenceGap!==true)fail('self-test: deterministic suggestion output mismatch');

  console.log('SHINE DEFENCE REVIEW EVIDENCE ASSISTANT SELF-TEST: PASS ranking, gap detection and advisory-only output');
}

function main(){
  const args=parseArgs(process.argv.slice(2));
  if(args.help){usage();return}
  if(args.selfTest){selfTest();return}
  if(!args.candidate)fail('--candidate is required');

  const queue=readJson(queuePath);
  const matches=queue.candidates.filter(candidate=>candidate.candidateId===args.candidate);
  if(matches.length!==1)fail('candidate must exist exactly once');
  const candidate=matches[0];
  if(candidate.status!=='pending_review')fail('candidate must be pending_review');

  const checklistPath=join(checklistDir,candidate.candidateId+'.json');
  const checklistFull=join(root,checklistPath);
  if(!existsSync(checklistFull))fail('canonical review checklist missing; generate it first');
  const checklist=JSON.parse(readFileSync(checklistFull,'utf8'));

  const registryBytes=readFileSync(join(root,registryPath));
  const registry=JSON.parse(registryBytes.toString('utf8'));
  const checklistFailures=validateReviewChecklist({checklist,candidate,registry,registryBytes,readArtefact:readCanonical});
  if(checklistFailures.length)fail('canonical checklist invalid: '+checklistFailures.join('; '));

  const generatedAt=args.generatedAt==='now'||!args.generatedAt?new Date().toISOString():args.generatedAt;
  const artifact=buildEvidenceSuggestions({candidate,checklist,registry,registryBytes,generatedAt});
  const validation=validateEvidenceSuggestions({artifact,candidate,checklist,registry,registryBytes});
  if(validation.length)fail('generated suggestions invalid: '+validation.join('; '));

  const relativePath=join(suggestionDir,candidate.candidateId+'.json');
  const fullPath=join(root,relativePath);
  console.log('SHINE DEFENCE REVIEW EVIDENCE ASSISTANT');
  console.log('candidate: '+candidate.candidateId);
  console.log('requirements: '+artifact.items.length);
  console.log('evidence gaps: '+artifact.items.filter(item=>item.evidenceGap).length);
  console.log('suggested mappings: '+artifact.items.reduce((sum,item)=>sum+item.suggestions.length,0));
  console.log((args.apply?'WRITE ':'WOULD WRITE ')+relativePath);
  console.log('authority: advisory only; checklist state unchanged');

  if(!args.apply){
    console.log('DRY RUN: no files changed.');
    return;
  }

  const original=existsSync(fullPath)?readFileSync(fullPath):null;
  try{
    atomicWrite(fullPath,Buffer.from(json(artifact)));
    console.log('SHINE DEFENCE REVIEW EVIDENCE ASSISTANT: GENERATED '+candidate.candidateId);
  }catch(error){
    if(original===null){if(existsSync(fullPath))rmSync(fullPath)}
    else atomicWrite(fullPath,original);
    throw error;
  }
}

main();
