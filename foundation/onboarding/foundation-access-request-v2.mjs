// Canonical Gateway v2 body builder. Credentials belong in transport headers.
function checkJson(value, ancestors=new Set()) {
  if(value===null || typeof value==='string' || typeof value==='boolean') return;
  if(typeof value==='number' && Number.isFinite(value)) return;
  if(typeof value!=='object' || ancestors.has(value)) throw new TypeError('context must contain JSON values');
  if(!Array.isArray(value) && Object.getPrototypeOf(value)!==Object.prototype && Object.getPrototypeOf(value)!==null)
    throw new TypeError('context must contain plain JSON objects');
  ancestors.add(value);
  if(Object.getOwnPropertySymbols(value).length) throw new TypeError('context cannot contain symbol keys');
  for(const descriptor of Object.values(Object.getOwnPropertyDescriptors(value))) {
    if(!descriptor.enumerable) continue;
    if(!Object.hasOwn(descriptor,'value')) throw new TypeError('context cannot contain accessors');
    checkJson(descriptor.value,ancestors);
  }
  ancestors.delete(value);
}
export function buildFoundationAccessRequest({
  appId, scope, purpose, resourceId, resourceCategory, context
}={}, {randomUUID=()=>crypto.randomUUID(), now=()=>new Date()}={}) {
  if(typeof appId!=='string'||!/^shine\.[a-z0-9][a-z0-9-]*$/.test(appId)) throw new TypeError('invalid appId');
  for(const [name,value] of Object.entries({scope,purpose})) {
    if(typeof value!=='string'||!/^[a-z0-9][a-z0-9._:-]*$/.test(value)) throw new TypeError('invalid '+name);
  }
  if(resourceCategory===undefined && resourceId===undefined) throw new TypeError('resourceCategory or resourceId is required');
  if(resourceCategory!==undefined && (typeof resourceCategory!=='string'||!/^[a-z0-9][a-z0-9._-]*$/.test(resourceCategory)))
    throw new TypeError('invalid resourceCategory');
  if(resourceId!==undefined && (typeof resourceId!=='string'||!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(resourceId)))
    throw new TypeError('invalid resourceId');
  if(context!==undefined) {
    if(context===null || typeof context!=='object' || Array.isArray(context)) throw new TypeError('context must be an object');
    checkJson(context);
  }
  return {
    gatewayRequest:'shine-foundation/gateway-request-v2',
    schemaVersion:'2.0.0',
    operation:'access.evaluate',
    traceId:randomUUID(),
    permission:{
      requestId:randomUUID(),appId,scope,purpose,
      ...(resourceId===undefined?{}:{resourceId}),
      ...(resourceCategory===undefined?{}:{resourceCategory}),
      requestedAt:now().toISOString(),
      ...(context===undefined?{}:{context})
    }
  };
}
