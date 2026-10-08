import {createVeteranCarePurposePermissionEvaluator} from './veteran-care-purpose-v1.mjs';
const UTC=/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
function canonicalTime(value){
  if(typeof value!=='string'||!UTC.test(value)) return null;
  const ms=Date.parse(value);
  return Number.isSafeInteger(ms)&&new Date(ms).toISOString()===value?ms:null;
}

// consentWindow must come from the immutable, independently persisted reviewed
// consent snapshot. Never fabricate it by copying current grant dates or UI data.
export function evaluateVeteranCareGrantWindow({grant,nowMs}={}){
  try{
    const window=grant?.consentWindow;
    if(!window||Object.getPrototypeOf(window)!==Object.prototype) return {status:'denied'};
    const d=Object.getOwnPropertyDescriptors(window);
    if(Reflect.ownKeys(d).length!==2||!Object.hasOwn(d,'startsAt')||!Object.hasOwn(d,'expiresAt')||
      !Object.hasOwn(d.startsAt,'value')||!Object.hasOwn(d.expiresAt,'value')) return {status:'denied'};
    const start=canonicalTime(d.startsAt.value),end=canonicalTime(d.expiresAt.value);
    if(start===null||end===null||end<=start||grant.notBefore!==d.startsAt.value||grant.expiresAt!==d.expiresAt.value||
      !Number.isSafeInteger(nowMs)||nowMs<0||nowMs<start||nowMs>=end) return {status:'denied'};
    return {status:'current',expiresAtMs:end};
  }catch{return {status:'denied'};}
}

export function createVeteranCareExpiringPermissionEvaluator(options={}){
  return createVeteranCarePurposePermissionEvaluator({...options,evaluateGrantWindow:evaluateVeteranCareGrantWindow});
}
