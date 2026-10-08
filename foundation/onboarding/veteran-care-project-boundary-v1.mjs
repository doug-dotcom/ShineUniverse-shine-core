import {VETERAN_CARE_ISSUER,createVeteranCareIdentityVerifier} from './veteran-care-identity-v1.mjs';

export const VETERAN_CARE_PROJECT_URL=VETERAN_CARE_ISSUER.slice(0,-'/auth/v1'.length);
const fields=['mode','issuer','authProjectUrl','databaseProjectUrl','storageProjectUrl'];
const blocked=()=>({status:'blocked',reasonCode:'vc-project-boundary-invalid'});

// Server-owned deployment descriptor only. No keys, tokens or browser claims.
// Matching this descriptor is a prerequisite, not proof of a deployed cutover.
export function assessVeteranCareProjectBoundary(configuration){
  try{
    if(!configuration||Object.getPrototypeOf(configuration)!==Object.prototype) return blocked();
    const descriptors=Object.getOwnPropertyDescriptors(configuration);
    const keys=Reflect.ownKeys(descriptors);
    if(keys.length!==fields.length||keys.some(key=>!fields.includes(key))) return blocked();
    if(fields.some(key=>!Object.hasOwn(descriptors,key)||!Object.hasOwn(descriptors[key],'value'))) return blocked();
    if(descriptors.mode.value!=='veteran_care'||descriptors.issuer.value!==VETERAN_CARE_ISSUER) return blocked();
    if(fields.slice(2).some(key=>descriptors[key].value!==VETERAN_CARE_PROJECT_URL)) return blocked();
    return {status:'ready',reasonCode:'vc-dedicated-project-configured'};
  }catch{return blocked();}
}

// Fail closed before constructing or calling authority adapters. Configuration is
// snapshotted at construction; a deployment change requires a fresh verifier.
// Foundation's own gateway URL is deliberately outside this VC data descriptor.
export function createVeteranCareBoundIdentityVerifier({configuration,...authority}={}){
  if(assessVeteranCareProjectBoundary(configuration).status!=='ready')
    return async()=>({status:'denied',reasonCode:'vc-project-boundary-invalid'});
  return createVeteranCareIdentityVerifier(authority);
}
