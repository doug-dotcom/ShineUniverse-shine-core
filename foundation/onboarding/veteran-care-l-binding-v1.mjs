import {createVeteranCareSessionIdentityVerifier} from './veteran-care-session-v1.mjs';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
function capture(v,keys){
  if(!v||Object.getPrototypeOf(v)!==Object.prototype)throw new TypeError();
  const d=Object.getOwnPropertyDescriptors(v);
  if(Reflect.ownKeys(d).length!==keys.length||keys.some(k=>!Object.hasOwn(d,k)||!Object.hasOwn(d[k],'value')))throw new TypeError();
  return Object.freeze(Object.fromEntries(keys.map(k=>[k,d[k].value])));
}
const deny=(status='denied',reasonCode='vc-l-binding-unverified')=>({status,reasonCode,executionPermitted:false});
// App authentication alone is insufficient. L owns verification of its user
// credential and identity mapping; Foundation owns the current approved link.
export function createVeteranCareLAppBinder({verifyIntegrationClient,verifyCompanionUser,getCurrentVCCompanionLink,bindingClock=()=>Date.now(),...options}={}){
  if(options.appId!=='shine.veteran-care'||[verifyIntegrationClient,verifyCompanionUser,getCurrentVCCompanionLink,bindingClock].some(f=>typeof f!=='function'))throw new TypeError('VC identity, L app/user verification and current link authority required');
  const verify=createVeteranCareSessionIdentityVerifier(options);
  return async function bind(input){
    let authContext,companionAuthContext;
    try{
      const q=capture(input,['authContext','companionAuthContext']);
      authContext=capture(q.authContext,['appToken','jwt']);
      companionAuthContext=capture(q.companionAuthContext,['clientToken','userToken']);
      if([...Object.values(authContext),...Object.values(companionAuthContext)].some(v=>typeof v!=='string'||!v.length))throw new TypeError();
    }catch{return deny('denied','vc-l-binding-input-invalid');}
    try{
      const started=bindingClock();if(!Number.isSafeInteger(started)||started<0)throw new TypeError();
      const vc=await verify({authContext});if(vc.status!=='verified')return deny(vc.status,vc.reasonCode);
      const actorShineId=vc.identity.shineId.toLowerCase(),clientId='shine.companion';
      const client=await verifyIntegrationClient({authContext:companionAuthContext,claimedClientId:clientId});
      if(!client||client.clientId!==clientId||client.clientKind!=='first-party-companion')return deny();
      const user=capture(await verifyCompanionUser({authContext:companionAuthContext,clientId}),['verified','clientId','shineId']);
      if(user.verified!==true||user.clientId!==clientId||user.shineId!==actorShineId)return deny();
      const query=Object.freeze({foundationAppId:options.appId,clientId,actorShineId});
      const link=capture(await getCurrentVCCompanionLink(query),['foundationAppId','clientId','ownerShineId','linkId','status','revision','validUntil']);
      const expires=Date.parse(link.validUntil),now=bindingClock();
      if(link.foundationAppId!==query.foundationAppId||link.clientId!==clientId||link.ownerShineId!==actorShineId||link.status!=='active'||typeof link.linkId!=='string'||!UUID.test(link.linkId)||!Number.isSafeInteger(link.revision)||link.revision<1||typeof link.validUntil!=='string'||!Number.isSafeInteger(expires)||!Number.isSafeInteger(now)||now<started||now>=expires)return deny();
      return {status:'l-app-bound',executionPermitted:false,memoryReadPermitted:false,memoryWritePermitted:false,binding:Object.freeze({
        contract:'shine-foundation/veteran-care-l-app-binding-v1',schemaVersion:'1.0.0',foundationAppId:query.foundationAppId,
        companionClientId:clientId,actorShineId,ownerShineId:actorShineId,linkId:link.linkId,linkRevision:link.revision,validUntil:new Date(expires).toISOString(),
        executionPermitted:false,memoryReadPermitted:false,memoryWritePermitted:false,requiresFreshExecutionCheck:true})};
    }catch{return deny('unavailable','vc-l-binding-authority-unavailable');}
  };
}
