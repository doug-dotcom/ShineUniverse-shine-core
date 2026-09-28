const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TOKEN=/^[a-z0-9][a-z0-9._:-]*$/;

const response=(status,reasonCode,extra={})=>({
  capabilityTicketRedeemResponse:'shine-foundation/capability-ticket-redeem-response-v2',
  schemaVersion:'2.0.0',
  status,
  reasonCode,
  ...extra
});

export function createCapabilityTicketRedeemService({
  adapters,
  clock=()=>new Date().toISOString(),
  idFactory=()=>crypto.randomUUID()
}={}){
  if(typeof adapters?.redeemCapabilityInvocationTicket!=='function'){
    throw new TypeError('missing capability ticket redeem adapter');
  }

  return async function handle({envelope}={}){
    if(!envelope||
       envelope.capabilityTicketRedeem!=='shine-foundation/capability-ticket-redeem-v2'||
       envelope.schemaVersion!=='2.0.0'||
       !UUID.test(envelope.ticketId??'')||
       !UUID.test(envelope.stepId??'')||
       !TOKEN.test(envelope.capabilityId??'')){
      return response('invalid','invalid-capability-ticket-redeem');
    }

    try{
      const result=await adapters.redeemCapabilityInvocationTicket({
        eventId:idFactory(),
        ticketId:envelope.ticketId,
        stepId:envelope.stepId,
        capabilityId:envelope.capabilityId,
        occurredAt:clock()
      });
      if(!result) return response('unavailable','capability-ticket-redeem-unavailable');
      if(result.allowed===true){
        return response('allowed',result.reasonCode,{
          conciergeRequestId:result.conciergeRequestId,
          stepId:result.stepId,
          capabilityId:result.capabilityId,
          purpose:result.purpose,
          ownerShineId:result.ownerShineId,
          clientId:result.clientId,
          appId:result.appId,
          appSubjectId:result.appSubjectId??null,
          subjectBindingStatus:result.subjectBindingStatus??'missing'
        });
      }
      return response('denied',result.reasonCode);
    }catch{
      return response('unavailable','capability-ticket-redeem-unavailable');
    }
  };
}
