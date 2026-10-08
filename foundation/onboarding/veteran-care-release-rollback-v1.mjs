import {randomUUID} from 'node:crypto';
const appId='shine.veteran-care',purpose='veteran-care.release-observation';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const SHA40=/^[0-9a-f]{40}$/,SHA64=/^[0-9a-f]{64}$/;
function capture(v,keys){
  if(!v||Object.getPrototypeOf(v)!==Object.prototype)throw new TypeError();
  const d=Object.getOwnPropertyDescriptors(v);
  if(Reflect.ownKeys(d).length!==keys.length||keys.some(k=>!Object.hasOwn(d,k)||!Object.hasOwn(d[k],'value')))throw new TypeError();
  return Object.freeze(Object.fromEntries(keys.map(k=>[k,d[k].value])));
}
const same=(a,b)=>Object.keys(a).every(k=>a[k]===b[k]);
const fail=(status='unavailable')=>({status,reasonCode:'vc-exact-release-unverified',observationsMatched:false,deploymentMutationPerformed:false,rollbackPerformed:false,permissionsRestored:false});
// Read-only observer. Exact source/artifact agreement never executes deployment
// or allows a rollback to replace current revocation or schema authority.
export function createVeteranCareReleaseRollbackVerifier({verifyReleaseOperator,getCurrentReleasePlan,getCurrentReleaseAuthority,getReleaseSchemaCompatibility,getDeploymentProviderObservation,getRuntimeReleaseObservation,releaseClock=()=>Date.now(),idFactory=randomUUID}={}){
  if([verifyReleaseOperator,getCurrentReleasePlan,getCurrentReleaseAuthority,getReleaseSchemaCompatibility,getDeploymentProviderObservation,getRuntimeReleaseObservation,releaseClock,idFactory].some(f=>typeof f!=='function'))throw new TypeError('protected exact release observers required');
  return async function inspect(input){
    let action,authContext;
    try{const i=capture(input,['action','authContext']);action=i.action;authContext=capture(i.authContext,['serviceToken']);if(!['release','rollback'].includes(action)||typeof authContext.serviceToken!=='string'||!authContext.serviceToken.length)throw new TypeError();}catch{return fail('denied');}
    try{
      let last=releaseClock();if(!Number.isSafeInteger(last)||last<0)throw new TypeError();
      const now=()=>{const n=releaseClock();if(!Number.isSafeInteger(n)||n<last)throw new TypeError();last=n;return n;};
      const liveUntil=s=>typeof s==='string'&&Number.isSafeInteger(Date.parse(s))&&now()<Date.parse(s);
      const operator=async()=>{
        const p=capture(await verifyReleaseOperator(Object.freeze({authContext,foundationAppId:appId,purpose})),['verified','foundationAppId','purpose','servicePrincipalId','revision','validUntil']);
        if(p.verified!==true||p.foundationAppId!==appId||p.purpose!==purpose||typeof p.servicePrincipalId!=='string'||!/^vc-release-[a-z0-9-]{1,64}$/.test(p.servicePrincipalId)||!Number.isSafeInteger(p.revision)||p.revision<1||!liveUntil(p.validUntil))return null;return p;
      };
      const firstOperator=await operator();if(!firstOperator)return fail('denied');
      const query=Object.freeze({foundationAppId:appId,action});
      const plan=async()=>{
        const p=capture(await getCurrentReleasePlan(query),['foundationAppId','action','environment','planId','revision','status','sourceCommitSha','artifactSha256','schemaRevision','authorityEpoch','minimumRevocationRevision','validUntil']);
        if(p.foundationAppId!==appId||p.action!==action||!['staging','production'].includes(p.environment)||['planId','sourceCommitSha','artifactSha256','authorityEpoch'].some(k=>typeof p[k]!=='string')||!UUID.test(p.planId)||!Number.isSafeInteger(p.revision)||p.revision<1||p.status!=='approved'||!SHA40.test(p.sourceCommitSha)||!SHA64.test(p.artifactSha256)||!Number.isSafeInteger(p.schemaRevision)||p.schemaRevision<1||!UUID.test(p.authorityEpoch)||!Number.isSafeInteger(p.minimumRevocationRevision)||p.minimumRevocationRevision<0||!liveUntil(p.validUntil))throw new TypeError();return p;
      };
      const first=await plan(),binding=Object.freeze({foundationAppId:appId,environment:first.environment});
      const authority=async()=>{
        const a=capture(await getCurrentReleaseAuthority(binding),['foundationAppId','environment','schemaRevision','authorityEpoch','revocationRevision','validUntil']);
        if(a.foundationAppId!==appId||a.environment!==first.environment||a.schemaRevision!==first.schemaRevision||a.authorityEpoch!==first.authorityEpoch||!Number.isSafeInteger(a.revocationRevision)||a.revocationRevision<first.minimumRevocationRevision||!liveUntil(a.validUntil))throw new TypeError();return a;
      };
      const firstAuthority=await authority();
      const compatibility=Object.freeze({...binding,action,sourceCommitSha:first.sourceCommitSha,artifactSha256:first.artifactSha256,schemaRevision:firstAuthority.schemaRevision});
      async function compatible(){const c=capture(await getReleaseSchemaCompatibility(compatibility),[...Object.keys(compatibility),'compatible']);return c.compatible===true&&Object.keys(compatibility).every(k=>c[k]===compatibility[k]);}
      if(!await compatible())return fail('denied');
      async function observe(){
        const requestId=idFactory();if(typeof requestId!=='string'||!UUID.test(requestId))throw new TypeError();
        const q=Object.freeze({...binding,requestId});
        const keys=[...Object.keys(q),'deploymentId','sourceCommitSha','artifactSha256','status','observedAt','evidenceMode'];
        const provider=capture(await getDeploymentProviderObservation(q),keys);
        const runtime=capture(await getRuntimeReleaseObservation(q),[...keys,'schemaRevision','authorityEpoch','revocationRevision']);
        for(const r of [provider,runtime]){
          const t=now(),observed=typeof r.observedAt==='string'?Date.parse(r.observedAt):NaN;
          if(Object.keys(q).some(k=>r[k]!==q[k])||typeof r.deploymentId!=='string'||!UUID.test(r.deploymentId)||r.status!=='active'||r.sourceCommitSha!==first.sourceCommitSha||r.artifactSha256!==first.artifactSha256||!['synthetic','live'].includes(r.evidenceMode)||!Number.isSafeInteger(observed)||observed>t||t-observed>=300000)throw new TypeError();
        }
        if(provider.deploymentId!==runtime.deploymentId||runtime.schemaRevision!==firstAuthority.schemaRevision||runtime.authorityEpoch!==firstAuthority.authorityEpoch||runtime.revocationRevision!==firstAuthority.revocationRevision)throw new TypeError();
        return {provider,runtime,deadline:Math.min(Date.parse(provider.observedAt),Date.parse(runtime.observedAt))+300000};
      }
      const initial=await observe(),final=await observe();
      if(initial.provider.deploymentId!==final.provider.deploymentId||!same(first,await plan())||!same(firstAuthority,await authority())||!await compatible())return fail();
      const finalOperator=await operator();if(!finalOperator||!same(firstOperator,finalOperator))return fail('denied');
      const deadline=Math.min(Date.parse(first.validUntil),Date.parse(firstAuthority.validUntil),Date.parse(finalOperator.validUntil),final.deadline);if(now()>=deadline)return fail();
      return {contract:'shine-foundation/veteran-care-exact-release-observation-v1',status:'exact-release-observed',action,observationsMatched:true,
        release:Object.freeze({planId:first.planId,planRevision:first.revision,environment:first.environment,deploymentId:final.provider.deploymentId,sourceCommitSha:first.sourceCommitSha,artifactSha256:first.artifactSha256,validUntil:new Date(deadline).toISOString()}),
        authority:Object.freeze({schemaRevision:firstAuthority.schemaRevision,authorityEpoch:firstAuthority.authorityEpoch,revocationRevision:firstAuthority.revocationRevision}),
        evidence:Object.freeze({providerMode:final.provider.evidenceMode,runtimeMode:final.runtime.evidenceMode,providerObservedAt:final.provider.observedAt,runtimeObservedAt:final.runtime.observedAt}),
        deploymentMutationPerformed:false,rollbackPerformed:false,permissionsRestored:false,requiresFreshReleaseObservation:true};
    }catch{return fail();}
  };
}
