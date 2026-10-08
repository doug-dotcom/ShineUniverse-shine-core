const messages=Object.freeze({
  'access-not-confirmed':Object.freeze({message:'Access could not be confirmed for this request.',nextAction:'review-access'}),
  'sign-in-required':Object.freeze({message:'Sign in again before trying this request.',nextAction:'sign-in'}),
  'temporarily-unavailable':Object.freeze({message:'Access cannot be checked right now. Please try again later.',nextAction:'retry-later'}),
  'request-not-supported':Object.freeze({message:'This request is not supported by this read-only service.',nextAction:'review-request'})
});
const envelope=code=>Object.freeze({contract:'shine-foundation/veteran-care-public-denial-v1',schemaVersion:'1.0.0',
  status:'blocked',code,...messages[code]});

// Projection for trusted server outcomes. Never pass a raw denial/error through
// to a browser. Resource-missing, wrong-owner and grant-missing are deliberately
// indistinguishable; this response does not confirm record existence.
export function projectVeteranCareDenial(result){
  let status,reason;
  try{
    if(!result||Object.getPrototypeOf(result)!==Object.prototype)return envelope('access-not-confirmed');
    const d=Object.getOwnPropertyDescriptors(result);
    if(!Object.hasOwn(d,'status')||!Object.hasOwn(d.status,'value'))return envelope('access-not-confirmed');
    status=d.status.value;
    if(Object.hasOwn(d,'decision')&&!Object.hasOwn(d.decision,'value'))return envelope('access-not-confirmed');
    if(Object.hasOwn(d,'decision')&&d.decision.value==='allow')return null;
    // This denial-only projection must never become a success serializer.
    if(['permission-allowed','release-ready','verified','scope-ready','delegated-scope-ready'].includes(status))return null;
    if(status!=='denied'&&status!=='unavailable')return envelope('access-not-confirmed');
    if(Object.hasOwn(d,'reasonCode')&&Object.hasOwn(d.reasonCode,'value'))reason=d.reasonCode.value;
  }catch{return envelope('access-not-confirmed');}
  if(status==='unavailable')return envelope('temporarily-unavailable');
  if(reason==='vc-session-not-current')return envelope('sign-in-required');
  if(reason==='vc-read-route-operation-refused')return envelope('request-not-supported');
  return envelope('access-not-confirmed');
}
