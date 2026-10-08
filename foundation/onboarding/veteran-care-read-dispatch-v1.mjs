import {createVeteranCareGuardedRead} from './veteran-care-guarded-read-v1.mjs';
const refusal=()=>({status:'denied',reasonCode:'vc-read-route-operation-refused',preparationPerformed:false,resultReturned:false});

// Explicit server route boundary, not a general capability dispatcher. No
// mutating handler is registered and no operation is inferred from a grant.
// prepareResult still must use a genuinely read-only data adapter: this wrapper
// cannot undo writes performed by a misconfigured trusted callback.
export function createVeteranCareReadDispatcher(options){
  const read=createVeteranCareGuardedRead(options);
  return async function dispatch(envelope){
    let readRequest;
    try{
      if(!envelope||Object.getPrototypeOf(envelope)!==Object.prototype)return refusal();
      const descriptors=Object.getOwnPropertyDescriptors(envelope);
      if(Reflect.ownKeys(descriptors).length!==2||
        !Object.hasOwn(descriptors,'operation')||!Object.hasOwn(descriptors.operation,'value')||
        !Object.hasOwn(descriptors,'readRequest')||!Object.hasOwn(descriptors.readRequest,'value')||
        descriptors.operation.value!=='read')return refusal();
      readRequest=descriptors.readRequest.value;
    }catch{return refusal();}
    // The existing read gate synchronously captures nested input and performs
    // admission/revocation/freshness/expiry checks around private preparation.
    return read(readRequest);
  };
}
