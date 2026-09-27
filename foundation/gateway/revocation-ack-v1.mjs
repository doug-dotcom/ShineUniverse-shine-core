const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const APP=/^shine\.[a-z0-9][a-z0-9-]*$/;

const response=(envelope,status,reasonCode,extra={})=>({
  revocationAckResponse:'shine-foundation/revocation-ack-response-v1',
  schemaVersion:'1.0.0',
  requestId:envelope?.requestId??null,
  status,
  reasonCode,
  ...extra
});

const valid=envelope=>{
  if(!envelope||envelope.revocationAck!=='shine-foundation/revocation-ack-v1') return false;
  if(envelope.schemaVersion!=='1.0.0') return false;
  if(!UUID.test(envelope.requestId??'')) return false;
  if(!UUID.test(envelope.deliveryId??'')) return false;
  if(!APP.test(envelope.appId??'')) return false;
  if(!Number.isSafeInteger(envelope.sequenceNo)||envelope.sequenceNo<=0) return false;
  if(!Number.isFinite(Date.parse(envelope.requestedAt??''))) return false;
  return true;
};

const requireFunction=(adapters,name)=>{
  if(typeof adapters?.[name]!=='function') throw new TypeError('missing revocation ack adapter: '+name);
};

/** @param {{adapters:any,clock?:()=>string,idFactory?:()=>string}} [options] */
export function createRevocationAckService({
  adapters,
  clock=()=>new Date().toISOString(),
  idFactory=()=>crypto.randomUUID()
}={}){
  for(const name of ['verifyAppCaller','acknowledgeAppRevocations']) requireFunction(adapters,name);

  return async function handleRevocationAck({envelope,authContext}={}){
    if(!valid(envelope)) return response(envelope,'invalid','invalid-revocation-ack-request');

    const requestedAt=Date.parse(envelope.requestedAt);
    const now=Date.parse(clock());
    if(!Number.isFinite(requestedAt)||!Number.isFinite(now)||
       requestedAt<now-10*60*1000||requestedAt>now+5*60*1000){
      return response(envelope,'invalid','stale-revocation-ack-request');
    }

    let verifiedApp;
    try{
      verifiedApp=await adapters.verifyAppCaller({authContext,claimedAppId:envelope.appId});
    }catch{
      return response(envelope,'unavailable','foundation-dependency-unavailable');
    }
    if(!verifiedApp?.appId) return response(envelope,'denied','app-caller-unverified');
    if(verifiedApp.appId!==envelope.appId) return response(envelope,'denied','app-caller-mismatch');

    let result;
    try{
      result=await adapters.acknowledgeAppRevocations({
        ackId:idFactory(),
        requestId:envelope.requestId,
        deliveryId:envelope.deliveryId,
        appId:envelope.appId,
        sequenceNo:envelope.sequenceNo,
        occurredAt:clock()
      });
    }catch{
      return response(envelope,'unavailable','revocation-ack-write-failed');
    }

    if(!result?.outcome||!result?.reasonCode){
      return response(envelope,'unavailable','revocation-ack-write-failed');
    }
    if(result.outcome==='advanced'){
      return response(envelope,'acknowledged',result.reasonCode,{checkpointSequence:result.checkpointSequence});
    }
    if(result.outcome==='already-acked'){
      return response(envelope,'already-acknowledged',result.reasonCode,{checkpointSequence:result.checkpointSequence});
    }
    return response(envelope,'denied',result.reasonCode,{checkpointSequence:result.checkpointSequence});
  };
}
