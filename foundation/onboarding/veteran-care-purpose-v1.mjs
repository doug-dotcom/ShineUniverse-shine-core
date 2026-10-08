import {createVeteranCarePermissionEvaluator} from './veteran-care-permission-v1.mjs';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const refuse=(status,reasonCode)=>({status,decision:'deny',reasonCode,executionPerformed:false});
function capture(context){
  if(!context||Object.getPrototypeOf(context)!==Object.prototype) throw new TypeError();
  const d=Object.getOwnPropertyDescriptors(context);
  if(Reflect.ownKeys(d).length!==1||!Object.hasOwn(d,'preparationId')||!Object.hasOwn(d.preparationId,'value')||
    typeof d.preparationId.value!=='string'||!UUID.test(d.preparationId.value)) throw new TypeError();
  return Object.freeze({preparationId:d.preparationId.value.toLowerCase()});
}

// A persisted preparation record is purpose context, not proof of a booking,
// clinician verification or consent. Integrations owns the server projection.
export function createVeteranCarePurposePermissionEvaluator({getPreparationContext,...options}={}){
  if(typeof getPreparationContext!=='function') throw new TypeError('preparation context authority is required');
  const evaluate=createVeteranCarePermissionEvaluator({
    ...options,
    resolvePurposeBinding:async({request,purposeContext})=>{
      try{
        const context=await getPreparationContext(Object.freeze({
          preparationId:purposeContext.preparationId,ownerShineId:request.shineId,appId:request.appId,purpose:request.purpose
        }));
        if(!context||context.status!=='available'||typeof context.preparationId!=='string'||
          context.preparationId.toLowerCase()!==purposeContext.preparationId||
          typeof context.ownerShineId!=='string'||context.ownerShineId.toLowerCase()!==request.shineId||
          context.purpose!==request.purpose) return {status:'denied'};
        return {status:'bound',binding:{kind:'appointment-preparation',preparationId:purposeContext.preparationId}};
      }catch{return {status:'unavailable'};}
    }
  });
  return async function verify(input){
    let purposeContext;
    try{purposeContext=capture(input?.purposeContext);}
    catch{return refuse('denied','vc-purpose-context-invalid');}
    return evaluate({authContext:input?.authContext,request:input?.request,purposeContext});
  };
}
