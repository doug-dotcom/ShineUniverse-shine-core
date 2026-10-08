import {createVeteranCareLAppBinder} from './veteran-care-l-binding-v1.mjs';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const scope='veteran-care.memory.read',purpose='veteran-care.appointment-preparation',category='veteran-care.context';
function capture(v,keys){
  if(!v||Object.getPrototypeOf(v)!==Object.prototype)throw new TypeError();
  const d=Object.getOwnPropertyDescriptors(v);
  if(Reflect.ownKeys(d).length!==keys.length||keys.some(k=>!Object.hasOwn(d,k)||!Object.hasOwn(d[k],'value')))throw new TypeError();
  return Object.freeze(Object.fromEntries(keys.map(k=>[k,d[k].value])));
}
const deny=(status='denied')=>({status,reasonCode:'vc-memory-scope-unverified',executionPermitted:false});
const grantFields=['grantId','status','foundationAppId','clientId','ownerShineId','linkId','linkRevision','memoryId','memoryVersion','scope','operation','purpose','preparationId','notBefore','expiresAt','consentStartsAt','consentExpiresAt'];
// Selected memory metadata only. Record grants and approved links never imply
// permission to search, disclose or mutate the user's wider L memory store.
export function createVeteranCareMemoryScopeEvaluator({getMemoryDescriptor,getMemoryPermissionContext,getCurrentMemoryPermissionRevision,getPreparationContext,memoryClock=()=>Date.now(),...options}={}){
  if([getMemoryDescriptor,getMemoryPermissionContext,getCurrentMemoryPermissionRevision,getPreparationContext,memoryClock].some(f=>typeof f!=='function'))throw new TypeError('selected memory, purpose and current consent authority required');
  const bind=createVeteranCareLAppBinder(options);
  return async function evaluate(input){
    let authContext,companionAuthContext,request;
    try{
      const q=capture(input,['authContext','companionAuthContext','request']);
      authContext=capture(q.authContext,['appToken','jwt']);companionAuthContext=capture(q.companionAuthContext,['clientToken','userToken']);
      request=capture(q.request,['operation','memoryId','memoryVersion','preparationId']);
      if(request.operation!=='read'||typeof request.memoryId!=='string'||!UUID.test(request.memoryId)||typeof request.preparationId!=='string'||!UUID.test(request.preparationId)||!Number.isSafeInteger(request.memoryVersion)||request.memoryVersion<1)throw new TypeError();
    }catch{return deny();}
    try{
      const started=memoryClock();if(!Number.isSafeInteger(started)||started<0)throw new TypeError();
      const first=await bind({authContext,companionAuthContext});if(first.status!=='l-app-bound')return deny(first.status);
      const b=first.binding,query=Object.freeze({foundationAppId:b.foundationAppId,clientId:b.companionClientId,ownerShineId:b.ownerShineId,linkId:b.linkId,linkRevision:b.linkRevision,...request,scope,purpose});
      const descriptor=capture(await getMemoryDescriptor(query),['memoryId','memoryVersion','ownerShineId','category','status']);
      if(descriptor.memoryId!==request.memoryId||descriptor.memoryVersion!==request.memoryVersion||descriptor.ownerShineId!==b.ownerShineId||descriptor.category!==category||descriptor.status!=='available')return deny();
      const prep=capture(await getPreparationContext(query),['status','preparationId','ownerShineId','purpose']);
      if(prep.status!=='available'||prep.preparationId!==request.preparationId||prep.ownerShineId!==b.ownerShineId||prep.purpose!==purpose)return deny();
      const context=capture(await getMemoryPermissionContext(query),['complete','revision','grants']);
      if(context.complete!==true||!Number.isSafeInteger(context.revision)||context.revision<0||!Array.isArray(context.grants)||Object.getPrototypeOf(context.grants)!==Array.prototype||context.grants.length>100)return deny();
      const descriptors=Object.getOwnPropertyDescriptors(context.grants);
      if(Reflect.ownKeys(descriptors).length!==context.grants.length+1) return deny();
      const grants=Array.from({length:context.grants.length},(_,i)=>{if(!Object.hasOwn(descriptors,i)||!Object.hasOwn(descriptors[i],'value'))throw new TypeError();return capture(descriptors[i].value,grantFields);});
      const current=capture(await getCurrentMemoryPermissionRevision(Object.freeze({foundationAppId:b.foundationAppId,clientId:b.companionClientId,ownerShineId:b.ownerShineId})),['foundationAppId','clientId','ownerShineId','revision']);
      if(current.foundationAppId!==b.foundationAppId||current.clientId!==b.companionClientId||current.ownerShineId!==b.ownerShineId||current.revision!==context.revision)return deny();
      const matches=grants.filter(g=>g.status==='active'&&typeof g.grantId==='string'&&UUID.test(g.grantId)&&Object.entries(query).every(([k,v])=>g[k]===v));
      if(matches.length!==1)return deny();
      const g=matches[0],starts=Date.parse(g.notBefore),expires=Date.parse(g.expiresAt);
      if(typeof g.notBefore!=='string'||typeof g.expiresAt!=='string'||g.notBefore!==g.consentStartsAt||g.expiresAt!==g.consentExpiresAt||!Number.isSafeInteger(starts)||!Number.isSafeInteger(expires)||starts>=expires)return deny();
      const final=await bind({authContext,companionAuthContext});if(final.status!=='l-app-bound')return deny(final.status);
      if(['foundationAppId','companionClientId','actorShineId','ownerShineId','linkId','linkRevision','validUntil'].some(k=>final.binding[k]!==b[k]))return deny();
      const finalRevision=capture(await getCurrentMemoryPermissionRevision(Object.freeze({foundationAppId:b.foundationAppId,clientId:b.companionClientId,ownerShineId:b.ownerShineId})),['foundationAppId','clientId','ownerShineId','revision']);
      if(Object.keys(current).some(k=>finalRevision[k]!==current[k]))return deny();
      const now=memoryClock(),deadline=Math.min(expires,Date.parse(b.validUntil));
      if(!Number.isSafeInteger(now)||now<started||now<starts||now>=deadline)return deny();
      return {status:'memory-scope-allowed',decision:'allow-selected-memory-read',executionPermitted:false,modelDisclosurePermitted:false,memoryWritePermitted:false,
        envelope:Object.freeze({contract:'shine-foundation/veteran-care-memory-scope-v1',schemaVersion:'1.0.0',...query,actorShineId:b.actorShineId,category,grantId:g.grantId,permissionRevision:current.revision,validUntil:new Date(deadline).toISOString(),executionPermitted:false,modelDisclosurePermitted:false,memoryWritePermitted:false,requiresFreshExecutionCheck:true})};
    }catch{return deny('unavailable');}
  };
}
