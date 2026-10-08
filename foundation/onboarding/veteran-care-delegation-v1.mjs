import {createVeteranCareSessionIdentityVerifier} from './veteran-care-session-v1.mjs';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const uuid=v=>typeof v==='string'&&UUID.test(v);
const plain=v=>!!v&&Object.getPrototypeOf(v)===Object.prototype&&Reflect.ownKeys(v).every(k=>typeof k==='string'&&Object.hasOwn(Object.getOwnPropertyDescriptor(v,k),'value'));
const outcome=(status,reasonCode)=>({status,reasonCode,executionPermitted:false,authorizationApplied:false});

// Server-only metadata binding. A role label is never authority. This contract
// intentionally cannot be fed to the veteran's self-access permission path.
export function createVeteranCareDelegatedScopeBuilder({getDelegationContext,delegationClock=()=>Date.now(),...options}={}){
  if(typeof getDelegationContext!=='function'||typeof delegationClock!=='function')throw new TypeError('current delegation authority and clock required');
  const verify=createVeteranCareSessionIdentityVerifier(options);
  const appId=options.appId,slug=appId.slice(6);
  return async function build(input){
    try{
      if(!plain(input)||Reflect.ownKeys(input).length!==2||!plain(input.authContext)||!plain(input.selection))return outcome('denied','vc-delegation-request-invalid');
      const s=input.selection;
      if(Reflect.ownKeys(s).length!==4||!uuid(s.ownerShineId)||!uuid(s.recordId)||!uuid(s.preparationId)||!Number.isSafeInteger(s.recordVersion)||s.recordVersion<1)return outcome('denied','vc-delegation-request-invalid');
      const selected=Object.freeze({ownerShineId:s.ownerShineId.toLowerCase(),recordId:s.recordId.toLowerCase(),recordVersion:s.recordVersion,preparationId:s.preparationId.toLowerCase()});
      const authContext=Object.freeze({...input.authContext});
      const verified=await verify({authContext});
      if(verified.status!=='verified')return outcome(verified.status,verified.reasonCode);
      const actorShineId=verified.identity.shineId.toLowerCase();
      if(actorShineId===selected.ownerShineId)return outcome('denied','vc-delegation-self-access');
      const started=delegationClock();
      if(!Number.isSafeInteger(started)||started<0)return outcome('unavailable','vc-delegation-authority-unavailable');
      const query=Object.freeze({appId,actorShineId,...selected,operation:'read',scope:slug+'.record.read',purpose:slug+'.appointment-preparation'});
      const context=await getDelegationContext(query);
      const ended=delegationClock();
      if(!Number.isSafeInteger(ended)||ended<started)return outcome('unavailable','vc-delegation-authority-unavailable');
      if(!plain(context)||context.complete!==true||!plain(context.delegation)||!plain(context.resource))return outcome('denied','vc-delegation-unverified');
      const d=context.delegation,r=context.resource;
      if(!uuid(d.delegationId)||d.status!=='active'||!['carer','provider'].includes(d.relationship)||
        !Number.isSafeInteger(d.revision)||d.revision<1||!Number.isSafeInteger(d.expiresAtMs)||d.expiresAtMs<=ended||
        Object.entries(query).some(([k,v])=>d[k]!==v)||
        r.resourceId!==selected.recordId||r.resourceVersion!==selected.recordVersion||r.ownerShineId!==selected.ownerShineId||r.category!==slug+'.record')return outcome('denied','vc-delegation-unverified');
      return {status:'delegated-scope-ready',authorizationApplied:false,executionPermitted:false,
        request:Object.freeze({contract:'shine-foundation/veteran-care-delegated-scope-v1',appId,
          actorShineId,ownerShineId:selected.ownerShineId,resourceId:selected.recordId,resourceVersion:selected.recordVersion,
          preparationId:selected.preparationId,operation:'read',scope:query.scope,purpose:query.purpose,
          delegationId:d.delegationId.toLowerCase(),delegationRevision:d.revision,relationship:d.relationship,validUntilMs:d.expiresAtMs})};
    }catch{return outcome('unavailable','vc-delegation-authority-unavailable');}
  };
}
