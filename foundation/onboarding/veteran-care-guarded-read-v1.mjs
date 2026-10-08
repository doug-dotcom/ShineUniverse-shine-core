import {createVeteranCareFreshPermissionEvaluator} from './veteran-care-permission-freshness-v1.mjs';
function data(v,keys){
  if(!v||Object.getPrototypeOf(v)!==Object.prototype)throw new TypeError();
  const d=Object.getOwnPropertyDescriptors(v);
  if(Reflect.ownKeys(d).length!==keys.length||keys.some(k=>!Object.hasOwn(d,k)||!Object.hasOwn(d[k],'value')))throw new TypeError();
  return Object.freeze(Object.fromEntries(keys.map(k=>[k,d[k].value])));
}
function capture(v){
  const input=data(v,['authContext','request','purposeContext']);
  const authContext=data(input.authContext,['appToken','jwt']);
  if(typeof authContext.appToken!=='string'||typeof authContext.jwt!=='string')throw new TypeError();
  const request=data(input.request,['capabilityId','input']);
  const selected=data(request.input,['recordId','recordVersion']);
  const purposeContext=data(input.purposeContext,['preparationId']);
  if(typeof request.capabilityId!=='string'||typeof selected.recordId!=='string'||typeof selected.recordVersion!=='number'||typeof purposeContext.preparationId!=='string')throw new TypeError();
  return Object.freeze({authContext,request:Object.freeze({...request,input:selected}),purposeContext});
}
const refuse=(status,reasonCode,preparationPerformed=false)=>({status,reasonCode,preparationPerformed,resultReturned:false});
function same(a,b){
  return a.grantId===b.grantId&&a.permissionValidUntil===b.permissionValidUntil&&
    ['appId','shineId','capabilityId','operation','scope','purpose','resourceId','resourceVersion','resourceCategory'].every(k=>a.request[k]===b.request[k])&&
    a.request.purposeBinding.kind===b.request.purposeBinding.kind&&a.request.purposeBinding.preparationId===b.request.purposeBinding.preparationId;
}

// prepareResult is trusted server-private work. It must not send bytes, issue
// usable links, call an external model or expose data before the final gate.
export function createVeteranCareGuardedRead({prepareResult,releaseClock=()=>Date.now(),...options}={}){
  if(typeof prepareResult!=='function'||typeof releaseClock!=='function')throw new TypeError('private preparation and release clock are required');
  const evaluate=createVeteranCareFreshPermissionEvaluator(options);
  return async function guardedRead(input){
    let captured;
    try{captured=capture(input);}catch{return refuse('denied','vc-guarded-read-input-invalid');}
    const first=await evaluate(captured);
    if(first.decision!=='allow')return refuse(first.status,first.reasonCode);
    let startedAt;
    try{
      startedAt=releaseClock();
      if(!Number.isSafeInteger(startedAt)||startedAt<0)throw new TypeError();
      if(startedAt>=Date.parse(first.permissionValidUntil))return refuse('denied','vc-grant-expired');
    }catch{return refuse('unavailable','vc-release-clock-unavailable');}
    let result;
    try{result=await prepareResult(Object.freeze({request:first.request,grantId:first.grantId}));}
    catch{return refuse('unavailable','vc-private-preparation-unavailable',true);}
    const final=await evaluate(captured);
    if(final.decision!=='allow')return refuse(final.status,final.reasonCode,true);
    if(!same(first,final))return refuse('denied','vc-in-flight-authority-changed',true);
    try{
      const now=releaseClock();
      if(!Number.isSafeInteger(now)||now<startedAt)throw new TypeError();
      if(now>=Date.parse(final.permissionValidUntil))return refuse('denied','vc-grant-expired',true);
    }catch{return refuse('unavailable','vc-release-clock-unavailable',true);}
    return {contract:'shine-foundation/veteran-care-guarded-read-result-v1',schemaVersion:'1.0.0',
      status:'release-ready',preparationPerformed:true,resultReturned:true,result};
  };
}
