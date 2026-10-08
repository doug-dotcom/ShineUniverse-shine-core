import {createVeteranCareFreshPermissionEvaluator} from './veteran-care-permission-freshness-v1.mjs';

// Read-only authority lookups only. No retry, cached allow, private preparation
// or execution callback. Abort is cooperative; late answers never settle the
// caller's already timed-out lookup or become authority for a later request.
function boundedLookup(adapter,timeoutMs){
  return query=>new Promise((resolve,reject)=>{
    const controller=new AbortController();
    let settled=false;
    const timer=setTimeout(()=>{
      if(settled)return;
      settled=true;controller.abort();reject(new Error('permission-authority-timeout'));
    },timeoutMs);
    Promise.resolve().then(()=>adapter(query,Object.freeze({signal:controller.signal}))).then(
      value=>{if(settled)return;settled=true;clearTimeout(timer);resolve(value);},
      ()=>{if(settled)return;settled=true;clearTimeout(timer);reject(new Error('permission-authority-unavailable'));}
    );
  });
}

export function createVeteranCareBoundedPermissionEvaluator({getPermissionContext,getCurrentPermissionRevision,authorityTimeoutMs=5000,...options}={}){
  if(typeof getPermissionContext!=='function'||typeof getCurrentPermissionRevision!=='function'||
    !Number.isSafeInteger(authorityTimeoutMs)||authorityTimeoutMs<1||authorityTimeoutMs>30000)
    throw new TypeError('read-only permission authorities and bounded timeout required');
  return createVeteranCareFreshPermissionEvaluator({...options,
    getPermissionContext:boundedLookup(getPermissionContext,authorityTimeoutMs),
    getCurrentPermissionRevision:boundedLookup(getCurrentPermissionRevision,authorityTimeoutMs)});
}
