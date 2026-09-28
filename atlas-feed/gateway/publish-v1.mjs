const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const response=(envelope,status,reasonCode,extra={})=>({
  atlasFeedPublishResponse:'shine-universe/atlas-feed-publish-response-v1',
  schemaVersion:'1.0.0',
  requestId:envelope?.requestId??null,
  status,
  reasonCode,
  ...extra
});

const isObject=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);

export function canonicalJson(value){
  if(value===null||typeof value!=='object') return JSON.stringify(value);
  if(Array.isArray(value)) return '['+value.map(canonicalJson).join(',')+']';
  return '{'+Object.keys(value).sort().map(
    key=>JSON.stringify(key)+':'+canonicalJson(value[key])
  ).join(',')+'}';
}

export async function sha256CanonicalJson(value){
  const bytes=new TextEncoder().encode(canonicalJson(value));
  const digest=await crypto.subtle.digest('SHA-256',bytes);
  return [...new Uint8Array(digest)].map(b=>b.toString(16).padStart(2,'0')).join('');
}

export function createAtlasFeedPublishService({
  publisherAdmission,
  adapters,
  clock=()=>new Date().toISOString(),
  idFactory=()=>crypto.randomUUID()
}={}){
  if(typeof publisherAdmission!=='function') throw new TypeError('publisherAdmission is required');
  if(typeof adapters?.persistAtlasFeedEvent!=='function'){
    throw new TypeError('missing Atlas Feed persistence adapter: persistAtlasFeedEvent');
  }

  return async function publish({envelope,authContext}={}){
    if(!isObject(envelope)||
      envelope.atlasFeedPublishRequest!=='shine-universe/atlas-feed-publish-v1'||
      envelope.schemaVersion!=='1.0.0'||
      !UUID.test(envelope.requestId??'')||
      !isObject(envelope.event)||
      !Object.keys(envelope).every(key=>[
        'atlasFeedPublishRequest','schemaVersion','requestId','requestedAt','event','permissionContext'
      ].includes(key))){
      return response(envelope,'invalid','invalid-atlas-feed-publish-request');
    }

    const admissionEnvelope={
      atlasFeedPublishAdmissionRequest:'shine-universe/atlas-feed-publisher-admission-v1',
      schemaVersion:'1.0.0',
      requestId:envelope.requestId,
      requestedAt:envelope.requestedAt,
      event:envelope.event,
      ...(envelope.permissionContext?{permissionContext:envelope.permissionContext}:{})
    };

    let admission;
    try{
      admission=await publisherAdmission({envelope:admissionEnvelope,authContext});
    }catch{
      return response(envelope,'unavailable','publisher-admission-unavailable');
    }

    if(admission?.status!=='admitted'){
      const status=['denied','invalid','unavailable'].includes(admission?.status)
        ?admission.status:'unavailable';
      return response(
        envelope,
        status,
        admission?.reasonCode??'publisher-admission-unavailable',
        admission?.validationErrors?{validationErrors:admission.validationErrors}:{}
      );
    }

    const admissionSnapshot=admission.admission;
    if(!isObject(admissionSnapshot)||
      admissionSnapshot.eventId!==envelope.event.eventId||
      admissionSnapshot.appId!==envelope.event.source.appId||
      admissionSnapshot.capabilityId!==envelope.event.source.capabilityId||
      admissionSnapshot.capabilityState!=='live'||
      !UUID.test(admissionSnapshot.credentialId??'')){
      return response(envelope,'unavailable','publisher-admission-invalid');
    }

    const persistedAt=clock();
    const receiptId=idFactory();
    if(!UUID.test(receiptId)||!Number.isFinite(Date.parse(persistedAt))){
      return response(envelope,'unavailable','persistence-runtime-invalid');
    }

    let eventSha256,payloadSha256,receiptSha256,payloadSizeBytes;
    const receiptBase={
      atlasFeedPersistenceReceipt:'shine-universe/atlas-feed-persistence-receipt-v1',
      schemaVersion:'1.0.0',
      receiptId,
      requestId:envelope.requestId,
      eventId:envelope.event.eventId,
      publisherAppId:admissionSnapshot.appId,
      capabilityId:admissionSnapshot.capabilityId,
      capabilityVersion:admissionSnapshot.capabilityVersion,
      persistedAt
    };

    try{
      const payloadCanonical=canonicalJson(envelope.event.payload);
      payloadSizeBytes=new TextEncoder().encode(payloadCanonical).byteLength;
      [eventSha256,payloadSha256]=await Promise.all([
        sha256CanonicalJson(envelope.event),
        sha256CanonicalJson(envelope.event.payload)
      ]);
      receiptBase.eventSha256=eventSha256;
      receiptBase.payloadSha256=payloadSha256;
      receiptSha256=await sha256CanonicalJson(receiptBase);
    }catch{
      return response(envelope,'unavailable','persistence-hash-failed');
    }

    let result;
    try{
      result=await adapters.persistAtlasFeedEvent({
        requestId:envelope.requestId,
        event:envelope.event,
        admission:admissionSnapshot,
        eventSha256,
        payloadSha256,
        payloadSizeBytes,
        receipt:receiptBase,
        receiptSha256,
        persistedAt
      });
    }catch{
      return response(envelope,'unavailable','event-store-unavailable');
    }

    if(result?.outcome==='conflict'){
      return response(envelope,'conflict',result.reasonCode??'atlas-feed-persistence-conflict',{
        eventId:envelope.event.eventId
      });
    }

    if(!['persisted','already-persisted'].includes(result?.outcome)||
      !isObject(result?.receipt)||
      typeof result?.receiptSha256!=='string'){
      return response(envelope,'unavailable','event-store-invalid-response');
    }

    return response(envelope,result.outcome,result.reasonCode??(
      result.outcome==='persisted'?'atlas-feed-event-persisted':'atlas-feed-event-already-persisted'
    ),{
      eventId:envelope.event.eventId,
      receipt:result.receipt,
      receiptSha256:result.receiptSha256
    });
  };
}
