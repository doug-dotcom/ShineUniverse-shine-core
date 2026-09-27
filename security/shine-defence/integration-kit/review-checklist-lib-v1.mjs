import {createHash} from 'node:crypto';

export const REVIEW_CHECKLIST_CONTRACT='shine-defence/review-checklist-v1';
export const REVIEW_CHECKLIST_VERSION='1.0.0';

const ID=/^[a-z0-9][a-z0-9._-]{0,127}$/;
const ISO=/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/;
const SHA=/^[a-f0-9]{40}$/;
const secretLike=/(?:bearer\s+[a-z0-9._-]{12,}|sk-[a-z0-9_-]{12,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(?:token|secret|password)\s*[=:]\s*[^\s]{8,})/i;

const clone=value=>JSON.parse(JSON.stringify(value));
const sameArray=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
export const gitBlobSha=bytes=>createHash('sha1').update(Buffer.from('blob '+bytes.length+'\0')).update(bytes).digest('hex');

function cleanText(value,max){return typeof value==='string'&&value.trim().length>0&&value.length<=max&&!secretLike.test(value)}
function cleanOptional(value,max){return value===''||(typeof value==='string'&&value.length<=max&&!secretLike.test(value))}
function push(failures,message){failures.push(message)}
function canonicalMap(registry){return new Map((registry.entries||[]).map(entry=>[entry.id,entry]))}

function normaliseRequirement(policyId,requirement,index){
  if(requirement&&typeof requirement==='object'&&!Array.isArray(requirement)){
    const requirementId=typeof requirement.id==='string'&&requirement.id.trim()?requirement.id.trim():'R'+String(index+1).padStart(3,'0');
    const text=typeof requirement.name==='string'&&requirement.name.trim()
      ? requirement.name.trim()
      : JSON.stringify(requirement);
    return {
      itemId:policyId+':'+requirementId,
      requirement:text,
      required:requirement.required!==false
    };
  }
  return {
    itemId:policyId+':R'+String(index+1).padStart(3,'0'),
    requirement:String(requirement),
    required:true
  };
}

export function derivePolicyReviews({candidate,registry,readArtefact}){
  if(!candidate||!Array.isArray(candidate.policies))throw new Error('candidate policies are required');
  if(!registry||registry.registry!=='shine-defence/canonical-registry-v1'||!Array.isArray(registry.entries))throw new Error('unsupported canonical registry');
  if(typeof readArtefact!=='function')throw new Error('readArtefact callback is required');

  const canonical=canonicalMap(registry);
  return candidate.policies.map(policyId=>{
    const entry=canonical.get(policyId);
    if(!entry)throw new Error('unknown canonical policy '+policyId);
    const bytes=readArtefact(entry.path);
    if(!Buffer.isBuffer(bytes))throw new Error(policyId+': canonical artefact bytes unavailable');
    const actual=gitBlobSha(bytes);
    if(actual!==entry.blobSha)throw new Error(policyId+': canonical artefact blob drift '+actual+' != '+entry.blobSha);

    let requirements=[];
    if(entry.path.endsWith('.json')){
      let parsed;
      try{parsed=JSON.parse(bytes.toString('utf8'))}catch{throw new Error(policyId+': canonical artefact invalid JSON')}
      if(parsed.version!==entry.version)throw new Error(policyId+': canonical artefact version drift');
      if(Array.isArray(parsed.requirements)&&parsed.requirements.length){
        requirements=parsed.requirements.map((requirement,index)=>({
          ...normaliseRequirement(policyId,requirement,index),
          state:'unreviewed',
          evidenceRefs:[],
          reviewerNotes:''
        }));
      }
    }

    if(!requirements.length){
      requirements=[{
        itemId:policyId+':ARTEFACT',
        requirement:'Verify canonical artefact '+entry.path+' version '+entry.version+' / blob '+entry.blobSha+' is correctly pinned and the candidate release provides appropriate app-specific evidence for its use.',
        required:true,
        state:'unreviewed',
        evidenceRefs:[],
        reviewerNotes:''
      }];
    }

    return {
      policyId,
      canonicalPath:entry.path,
      canonicalVersion:entry.version,
      canonicalBlobSha:entry.blobSha,
      requirements
    };
  });
}

export function buildReviewChecklist({candidate,generatedAt,registry,registryBytes,readArtefact}){
  if(!candidate||candidate.status!=='pending_review')throw new Error('review checklist generation requires one pending_review candidate');
  if(!ISO.test(generatedAt||'')||!Number.isFinite(Date.parse(generatedAt)))throw new Error('generatedAt must be an ISO UTC timestamp');
  if(Date.parse(generatedAt)<Date.parse(candidate.observedAt))throw new Error('generatedAt cannot predate candidate observation');
  if(!Buffer.isBuffer(registryBytes))throw new Error('registry bytes are required');
  const registrySha=gitBlobSha(registryBytes);
  const policyReviews=derivePolicyReviews({candidate,registry,readArtefact});
  const candidateEvidence=(candidate.evidence||[]).map((evidence,index)=>({
    evidenceId:'E'+String(index+1),
    ...clone(evidence)
  }));

  return {
    checklist:REVIEW_CHECKLIST_CONTRACT,
    version:REVIEW_CHECKLIST_VERSION,
    candidateId:candidate.candidateId,
    appId:candidate.appId,
    repository:candidate.repository,
    releaseCommitSha:candidate.releaseCommitSha,
    profilePath:candidate.profilePath,
    profileBlobSha:candidate.profileBlobSha,
    profileVersion:candidate.profileVersion,
    policies:clone(candidate.policies),
    candidateObservedAt:candidate.observedAt,
    generatedAt,
    registryVersion:registry.version,
    registryBlobSha:registrySha,
    candidateEvidence,
    policyReviews,
    humanAuthorization:{status:'pending'}
  };
}

function expectedEvidence(candidate){
  return (candidate.evidence||[]).map((evidence,index)=>({evidenceId:'E'+String(index+1),...clone(evidence)}));
}

export function validateReviewChecklist({checklist,candidate,registry,registryBytes,readArtefact,requireApproved=false}){
  const failures=[];
  if(!checklist||typeof checklist!=='object'||Array.isArray(checklist)){push(failures,'checklist must be an object');return failures}
  if(checklist.checklist!==REVIEW_CHECKLIST_CONTRACT||checklist.version!==REVIEW_CHECKLIST_VERSION)push(failures,'unsupported review checklist');
  if(!candidate)push(failures,'candidate unavailable');
  if(!registry||registry.registry!=='shine-defence/canonical-registry-v1')push(failures,'canonical registry unavailable');
  if(!Buffer.isBuffer(registryBytes))push(failures,'registry bytes unavailable');
  if(failures.length)return failures;

  const bindings={
    candidateId:candidate.candidateId,
    appId:candidate.appId,
    repository:candidate.repository,
    releaseCommitSha:candidate.releaseCommitSha,
    profilePath:candidate.profilePath,
    profileBlobSha:candidate.profileBlobSha,
    profileVersion:candidate.profileVersion,
    candidateObservedAt:candidate.observedAt,
    registryVersion:registry.version,
    registryBlobSha:gitBlobSha(registryBytes)
  };
  for(const [key,expected] of Object.entries(bindings))if(checklist[key]!==expected)push(failures,key+' does not match candidate/canonical state');
  if(!sameArray(checklist.policies,candidate.policies))push(failures,'policies do not match candidate');
  if(!ISO.test(checklist.generatedAt||'')||!Number.isFinite(Date.parse(checklist.generatedAt)))push(failures,'invalid generatedAt');
  else if(Date.parse(checklist.generatedAt)<Date.parse(candidate.observedAt))push(failures,'generatedAt predates candidate observation');

  const expectedEvidenceValue=expectedEvidence(candidate);
  if(!sameArray(checklist.candidateEvidence,expectedEvidenceValue))push(failures,'candidate evidence copy does not match candidate');
  const evidenceIds=new Set(expectedEvidenceValue.map(item=>item.evidenceId));

  let expectedReviews=[];
  try{expectedReviews=derivePolicyReviews({candidate,registry,readArtefact})}catch(error){push(failures,String(error.message||error));return failures}
  if(!Array.isArray(checklist.policyReviews)||checklist.policyReviews.length!==expectedReviews.length){
    push(failures,'policy review count mismatch');
  }else{
    for(let i=0;i<expectedReviews.length;i++){
      const expected=expectedReviews[i],actual=checklist.policyReviews[i];
      if(!actual||actual.policyId!==expected.policyId||actual.canonicalPath!==expected.canonicalPath||actual.canonicalVersion!==expected.canonicalVersion||actual.canonicalBlobSha!==expected.canonicalBlobSha){
        push(failures,expected.policyId+': canonical policy binding mismatch');
        continue;
      }
      if(!Array.isArray(actual.requirements)||actual.requirements.length!==expected.requirements.length){
        push(failures,expected.policyId+': requirement count mismatch');
        continue;
      }
      for(let j=0;j<expected.requirements.length;j++){
        const template=expected.requirements[j],item=actual.requirements[j];
        if(!item||item.itemId!==template.itemId||item.requirement!==template.requirement||item.required!==template.required){
          push(failures,expected.policyId+': requirement template drift at '+j);
          continue;
        }
        if(!['unreviewed','satisfied','not_satisfied'].includes(item.state))push(failures,item.itemId+': invalid review state');
        if(!Array.isArray(item.evidenceRefs)||new Set(item.evidenceRefs).size!==item.evidenceRefs.length)push(failures,item.itemId+': invalid evidence refs');
        else for(const ref of item.evidenceRefs)if(!evidenceIds.has(ref))push(failures,item.itemId+': unknown evidence ref '+ref);
        if(!cleanOptional(item.reviewerNotes,1000))push(failures,item.itemId+': invalid or secret-like reviewer notes');
        if(item.state==='satisfied'&&(!item.evidenceRefs.length&&!String(item.reviewerNotes||'').trim()))push(failures,item.itemId+': satisfied item needs evidence or reviewer notes');
      }
    }
  }

  const auth=checklist.humanAuthorization;
  if(!auth||typeof auth!=='object'||Array.isArray(auth)){push(failures,'humanAuthorization missing');return failures}
  const allowedAuthKeys=new Set(['status','reviewerId','reviewedAt','summary']);
  for(const key of Object.keys(auth))if(!allowedAuthKeys.has(key))push(failures,'unknown humanAuthorization field '+key);
  if(!['pending','approved','rejected'].includes(auth.status))push(failures,'invalid humanAuthorization status');

  const allItems=(checklist.policyReviews||[]).flatMap(policy=>Array.isArray(policy.requirements)?policy.requirements:[]);
  if(auth.status==='pending'){
    if(Object.keys(auth).some(key=>key!=='status'))push(failures,'pending authorization must not contain reviewer metadata');
  }else{
    if(!ID.test(auth.reviewerId||''))push(failures,'invalid human reviewer id');
    if(!ISO.test(auth.reviewedAt||'')||!Number.isFinite(Date.parse(auth.reviewedAt)))push(failures,'invalid human reviewedAt');
    else{
      if(Date.parse(auth.reviewedAt)<Date.parse(checklist.generatedAt))push(failures,'human reviewedAt predates checklist generation');
      if(Date.parse(auth.reviewedAt)<Date.parse(candidate.observedAt))push(failures,'human reviewedAt predates candidate observation');
    }
    if(!cleanText(auth.summary,500))push(failures,'invalid or secret-like human review summary');
    if(auth.status==='approved'&&allItems.some(item=>item.state!=='satisfied'))push(failures,'approved checklist requires every item satisfied');
    if(auth.status==='rejected'&&!allItems.some(item=>item.state==='not_satisfied'))push(failures,'rejected checklist requires at least one not_satisfied item');
  }

  if(requireApproved&&auth.status!=='approved')push(failures,'explicit human approval is required');
  return failures;
}

export function assertApprovedReviewChecklist(args){
  const failures=validateReviewChecklist({...args,requireApproved:true});
  if(failures.length)throw new Error('review checklist approval invalid: '+failures.join('; '));
  return {
    reviewerId:args.checklist.humanAuthorization.reviewerId,
    reviewedAt:args.checklist.humanAuthorization.reviewedAt,
    summary:args.checklist.humanAuthorization.summary
  };
}
