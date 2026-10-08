import {evaluateAccess} from '../integration-kit/permission-engine-v1.mjs';
import {createVeteranCareResourceScopeBuilder} from './veteran-care-resource-scope-v1.mjs';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const refuse=(status,reasonCode)=>({status,decision:'deny',reasonCode,executionPerformed:false});
function plainData(value){
  return !!value&&Object.getPrototypeOf(value)===Object.prototype&&
    Reflect.ownKeys(value).every(key=>typeof key==='string'&&Object.hasOwn(Object.getOwnPropertyDescriptor(value,key),'value'));
}

// Current server authority only: no caller grants, no execution or ticket minting.
// Generic grant semantics are reused; this exact VC path adds explicit Defence
// allow and a single unambiguous exact-version grant requirement.
export function createVeteranCarePermissionEvaluator({getPermissionContext,permissionClock=()=>Date.now(),resolvePurposeBinding,evaluateGrantWindow,...options}={}){
  if(typeof getPermissionContext!=='function'||typeof permissionClock!=='function')
    throw new TypeError('current permission authority and server clock are required');
  if(resolvePurposeBinding!==undefined&&typeof resolvePurposeBinding!=='function')
    throw new TypeError('purpose binding authority must be a function');
  if(evaluateGrantWindow!==undefined&&typeof evaluateGrantWindow!=='function')
    throw new TypeError('grant window policy must be a function');
  const buildScope=createVeteranCareResourceScopeBuilder(options);
  return async function evaluate(input){
    const scoped=await buildScope(input);
    if(scoped.status!=='scope-ready') return refuse(scoped.status,scoped.reasonCode);
    let request=scoped.request;
    try{
      if(resolvePurposeBinding){
        const resolved=await resolvePurposeBinding({request,purposeContext:input?.purposeContext});
        if(resolved?.status!=='bound') return refuse(resolved?.status==='unavailable'?'unavailable':'denied','vc-purpose-binding-unverified');
        const binding=resolved.binding;
        if(!plainData(binding)||Reflect.ownKeys(binding).length!==2||binding.kind!=='appointment-preparation'||
          typeof binding.preparationId!=='string'||!UUID.test(binding.preparationId))
          return refuse('denied','vc-purpose-binding-unverified');
        request=Object.freeze({...request,contract:'shine-foundation/veteran-care-purpose-request-v1',
          purposeBinding:Object.freeze({kind:binding.kind,preparationId:binding.preparationId.toLowerCase()})});
      }
      const context=await getPermissionContext(Object.freeze({request}));
      if(!plainData(context)||context.complete!==true||!plainData(context.appManifest)||!Array.isArray(context.grants)||context.grants.length>100)
        return refuse('denied','vc-permission-context-invalid');
      if(context.defenceDecision!=='allow') return refuse('denied','vc-defence-not-allowed');
      const grants=Array.from(context.grants);
      const ids=new Set();
      for(const grant of grants){
        if(!plainData(grant)||typeof grant.grantId!=='string'||!UUID.test(grant.grantId)||
          typeof grant.ownerShineId!=='string'||!UUID.test(grant.ownerShineId)||
          ['appId','scope','purpose','status'].some(key=>typeof grant[key]!=='string')||
          !plainData(grant.resourceSelector)) return refuse('denied','vc-permission-context-invalid');
        const id=grant.grantId.toLowerCase();
        if(ids.has(id)) return refuse('denied','vc-permission-ambiguous');
        ids.add(id);
      }
      const nowMs=permissionClock();
      if(!Number.isSafeInteger(nowMs)||nowMs<0) return refuse('unavailable','vc-permission-authority-unavailable');
      const now=new Date(nowMs).toISOString();
      const resource={resourceId:request.resourceId,ownerShineId:request.shineId,category:request.resourceCategory};
      const matches=[];
      for(const grant of grants){
        const selector=grant.resourceSelector;
        if(request.purposeBinding){
          const binding=grant.purposeBinding;
          if(!plainData(binding)||Reflect.ownKeys(binding).length!==2||binding.kind!==request.purposeBinding.kind||
            typeof binding.preparationId!=='string'||binding.preparationId.toLowerCase()!==request.purposeBinding.preparationId) continue;
        }
        // Category-wide or mixed selectors cannot substitute for exact consent.
        if(Reflect.ownKeys(selector).length!==2||typeof selector.resourceId!=='string'||
          !UUID.test(selector.resourceId)||selector.resourceId.toLowerCase()!==request.resourceId||
          selector.resourceVersion!==request.resourceVersion) continue;
        let expiresAtMs=null;
        if(evaluateGrantWindow){
          const window=evaluateGrantWindow({grant,nowMs});
          if(window?.status!=='current'||!Number.isSafeInteger(window.expiresAtMs)||window.expiresAtMs<=nowMs) continue;
          expiresAtMs=window.expiresAtMs;
        }
        const canonical={...grant,ownerShineId:grant.ownerShineId.toLowerCase(),resourceSelector:{...selector,resourceId:selector.resourceId.toLowerCase()}};
        const result=evaluateAccess({request,verifiedShineId:request.shineId,appManifest:context.appManifest,resource,grants:[canonical],now,defenceDecision:'allow'});
        if(result.decision==='allow') matches.push({grantId:grant.grantId.toLowerCase(),expiresAtMs});
      }
      if(!matches.length) return refuse('denied','vc-permission-missing');
      if(matches.length!==1) return refuse('denied','vc-permission-ambiguous');
      if(evaluateGrantWindow){
        const completedAt=permissionClock();
        if(!Number.isSafeInteger(completedAt)||completedAt<nowMs) return refuse('unavailable','vc-permission-authority-unavailable');
        if(completedAt>=matches[0].expiresAtMs) return refuse('denied','vc-grant-expired');
      }
      return {status:'permission-allowed',decision:'allow',reasonCode:'vc-exact-grant-match',
        authorizationApplied:true,executionPerformed:false,grantId:matches[0].grantId,request,
        ...(evaluateGrantWindow?{permissionValidUntil:new Date(matches[0].expiresAtMs).toISOString()}:{})};
    }catch{return refuse('unavailable','vc-permission-authority-unavailable');}
  };
}
