import {createVeteranCareExpiringPermissionEvaluator} from './veteran-care-grant-expiry-v1.mjs';
const plain=v=>!!v&&Object.getPrototypeOf(v)===Object.prototype&&Reflect.ownKeys(v).every(k=>typeof k==='string'&&Object.hasOwn(Object.getOwnPropertyDescriptor(v,k),'value'));
function revision(v,request){
  return plain(v)&&Reflect.ownKeys(v).length===3&&v.appId===request.appId&&v.ownerShineId===request.shineId&&
    Number.isSafeInteger(v.revision)&&v.revision>=0;
}
// Capture bounded plain JSON data before awaiting independent authority. This
// prevents mutation of a cached grant object during revision lookup.
function capture(value){
  let nodes=0;
  function copy(v,depth=0){
    if(++nodes>5000||depth>10)throw new TypeError();
    if(v===null||typeof v==='boolean'||typeof v==='string')return v;
    if(typeof v==='number'&&Number.isFinite(v))return v;
    if(Array.isArray(v)){
      if(Object.getPrototypeOf(v)!==Array.prototype||v.length>100)throw new TypeError();
      const d=Object.getOwnPropertyDescriptors(v);
      if(Reflect.ownKeys(d).length!==v.length+1)throw new TypeError();
      return Object.freeze(Array.from({length:v.length},(_,i)=>{
        if(!Object.hasOwn(d,String(i))||!Object.hasOwn(d[i],'value'))throw new TypeError();
        return copy(d[i].value,depth+1);
      }));
    }
    if(!plain(v))throw new TypeError();
    return Object.freeze(Object.fromEntries(Object.entries(v).map(([k,item])=>[k,copy(item,depth+1)])));
  }
  return copy(value);
}

// permissionSnapshot is a revision of the complete authority context, not a
// feed acknowledgement, wall-clock TTL or caller-provided cache timestamp.
export function createVeteranCareFreshPermissionEvaluator({getCurrentPermissionRevision,...options}={}){
  if(typeof getCurrentPermissionRevision!=='function')throw new TypeError('uncached current permission revision authority is required');
  return createVeteranCareExpiringPermissionEvaluator({...options,verifyPermissionFreshness:async({request,context})=>{
    try{
      const snapshot=capture(context);
      if(!revision(snapshot.permissionSnapshot,request))return {status:'unavailable'};
      const current=await getCurrentPermissionRevision(Object.freeze({appId:request.appId,ownerShineId:request.shineId}));
      if(!revision(current,request))return {status:'unavailable'};
      if(current.revision!==snapshot.permissionSnapshot.revision)return {status:'stale'};
      return {status:'current',context:snapshot};
    }catch{return {status:'unavailable'};}
  }});
}
