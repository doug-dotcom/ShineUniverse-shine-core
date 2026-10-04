// Canonical Gateway v2 body builder. Credentials belong in transport headers.
export function buildFoundationAccessRequest({
  appId, scope, purpose, resourceId, resourceCategory, context
}={}, {randomUUID=()=>crypto.randomUUID(), now=()=>new Date()}={}) {
  if(!/^shine\.[a-z0-9][a-z0-9-]*$/.test(appId??'')) throw new TypeError('invalid appId');
  if(typeof scope!=='string'||!scope||typeof purpose!=='string'||!purpose)
    throw new TypeError('scope and purpose are required');
  if(!resourceCategory&&!resourceId) throw new TypeError('resourceCategory or resourceId is required');
  return {
    gatewayRequest:'shine-foundation/gateway-request-v2',
    schemaVersion:'2.0.0',
    operation:'access.evaluate',
    traceId:randomUUID(),
    permission:{
      requestId:randomUUID(),appId,scope,purpose,
      ...(resourceId?{resourceId}:{}),
      ...(resourceCategory?{resourceCategory}:{}),
      requestedAt:now().toISOString(),
      ...(context===undefined?{}:{context})
    }
  };
}
