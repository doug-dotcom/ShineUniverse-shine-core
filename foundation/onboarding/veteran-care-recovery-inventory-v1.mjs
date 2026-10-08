export const VETERAN_CARE_RECOVERY_ASSETS=Object.freeze([
  ['release-source','Foundation','foundation-repository','restore'],
  ['database-schema','VC Integrations','veteran-care-project','restore'],
  ['database-records','VC Integrations','veteran-care-project','restore'],
  ['revocation-ledger','Foundation/Defence','foundation-authority','reconcile'],
  ['storage-objects','VC Integrations','veteran-care-storage','restore'],
  ['identity-configuration','VC Integrations/Security','veteran-care-auth','rebuild'],
  ['retry-checkpoints','VC Orchestration','veteran-care-orchestration','reconcile'],
  ['credential-custody','VC Integrations/Security','protected-credential-vault','reissue'],
  ['companion-memory','L','companion-project','restore']
].map(([assetId,owner,sourceBoundary,recoveryMethod])=>Object.freeze({assetId,owner,sourceBoundary,recoveryMethod})));
const appId='shine.veteran-care',purpose='veteran-care.recovery-inventory';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
function capture(v,keys){
  if(!v||Object.getPrototypeOf(v)!==Object.prototype)throw new TypeError();
  const d=Object.getOwnPropertyDescriptors(v);
  if(Reflect.ownKeys(d).length!==keys.length||keys.some(k=>!Object.hasOwn(d,k)||!Object.hasOwn(d[k],'value')))throw new TypeError();
  return Object.freeze(Object.fromEntries(keys.map(k=>[k,d[k].value])));
}
const fail=(status='unavailable')=>({status,reasonCode:'vc-recovery-inventory-unverified',inventoryReturned:false,restorePermitted:false,restoreVerified:false});
// Metadata inspection only: no download, restore, vault resolution or authority
// resurrection. Collector acknowledgements cannot certify a successful restore.
export function createVeteranCareRecoveryInventory({verifyRecoveryOperator,getCurrentRecoveryInventoryRevision,getRecoveryAssetEvidence,recoveryClock=()=>Date.now(),recoveryTargets}={}){
  if([verifyRecoveryOperator,getCurrentRecoveryInventoryRevision,getRecoveryAssetEvidence,recoveryClock].some(f=>typeof f!=='function'))throw new TypeError('protected operator and inventory adapters required');
  const targets=capture(recoveryTargets,VETERAN_CARE_RECOVERY_ASSETS.map(a=>a.assetId));
  if(Object.values(targets).some(v=>v!==null&&(!Number.isSafeInteger(v)||v<1)))throw new TypeError('approved backup age targets or explicit null required');
  return async function inspect(input){
    let authContext;
    try{const i=capture(input,['authContext']);authContext=capture(i.authContext,['serviceToken']);if(typeof authContext.serviceToken!=='string'||!authContext.serviceToken.length)throw new TypeError();}catch{return fail('denied');}
    try{
      let last=recoveryClock();if(!Number.isSafeInteger(last)||last<0)throw new TypeError();
      const now=()=>{const t=recoveryClock();if(!Number.isSafeInteger(t)||t<last)throw new TypeError();last=t;return t;};
      const operator=async()=>{
        const p=capture(await verifyRecoveryOperator(Object.freeze({authContext,foundationAppId:appId,purpose})),['verified','foundationAppId','purpose','servicePrincipalId','revision','validUntil']);
        if(p.verified!==true||p.foundationAppId!==appId||p.purpose!==purpose||typeof p.servicePrincipalId!=='string'||!/^vc-recovery-[a-z0-9-]{1,64}$/.test(p.servicePrincipalId)||!Number.isSafeInteger(p.revision)||p.revision<1||typeof p.validUntil!=='string'||!Number.isSafeInteger(Date.parse(p.validUntil))||now()>=Date.parse(p.validUntil))return null;
        return p;
      };
      const first=await operator();if(!first)return fail('denied');
      const query=Object.freeze({foundationAppId:appId});
      const revision=async()=>{const r=capture(await getCurrentRecoveryInventoryRevision(query),['foundationAppId','revision']);if(r.foundationAppId!==appId||!Number.isSafeInteger(r.revision)||r.revision<1)throw new TypeError();return r.revision;};
      const initial=await revision(),rows=[];
      for(const asset of VETERAN_CARE_RECOVERY_ASSETS){
        const q=Object.freeze({foundationAppId:appId,inventoryRevision:initial,...asset});
        const raw=await getRecoveryAssetEvidence(q);
        if(raw===null){rows.push(Object.freeze({...asset,status:'missing',evidenceMode:'unknown',maxBackupAgeMs:targets[asset.assetId],artifactRef:null,sha256:null,capturedAt:null,verifiedAt:null}));continue;}
        const r=capture(raw,[...Object.keys(q),'status','evidenceMode','artifactRef','sha256','capturedAt','verifiedAt']);
        if(Object.keys(q).some(k=>r[k]!==q[k])||!['available','missing','unverified'].includes(r.status)||!['live','synthetic','unknown'].includes(r.evidenceMode))throw new TypeError();
        const metadata=r.status==='available';
        if(metadata){if(r.evidenceMode==='unknown'||typeof r.artifactRef!=='string'||!UUID.test(r.artifactRef)||typeof r.sha256!=='string'||! /^[0-9a-f]{64}$/.test(r.sha256)||typeof r.capturedAt!=='string'||typeof r.verifiedAt!=='string'||!Number.isSafeInteger(Date.parse(r.capturedAt))||!Number.isSafeInteger(Date.parse(r.verifiedAt))||Date.parse(r.verifiedAt)<Date.parse(r.capturedAt)||Date.parse(r.verifiedAt)>now())throw new TypeError();}
        else if([r.artifactRef,r.sha256,r.capturedAt,r.verifiedAt].some(v=>v!==null))throw new TypeError();
        rows.push(Object.freeze({...asset,status:r.status,evidenceMode:r.evidenceMode,maxBackupAgeMs:targets[asset.assetId],artifactRef:r.artifactRef,sha256:r.sha256,capturedAt:r.capturedAt,verifiedAt:r.verifiedAt}));
      }
      if(await revision()!==initial)return fail();
      const final=await operator();if(!final||Object.keys(first).some(k=>first[k]!==final[k]))return fail('denied');
      const checkedAt=now();if(checkedAt>=Date.parse(final.validUntil))return fail('denied');
      const gaps=[];
      for(const r of rows){if(r.status!=='available')gaps.push(Object.freeze({assetId:r.assetId,reason:r.status}));if(r.maxBackupAgeMs===null)gaps.push(Object.freeze({assetId:r.assetId,reason:'target-unapproved'}));else if(r.status==='available'&&checkedAt-Date.parse(r.capturedAt)>=r.maxBackupAgeMs)gaps.push(Object.freeze({assetId:r.assetId,reason:'stale'}));}
      return {contract:'shine-foundation/veteran-care-recovery-inventory-result-v1',status:'recovery-inventory',inventoryReturned:true,inventoryRevision:initial,
        checkedAt:new Date(checkedAt).toISOString(),assets:Object.freeze(rows),gaps:Object.freeze(gaps),metadataCoverageComplete:gaps.length===0,
        restorePermitted:false,restoreVerified:false,liveRestoreVerified:false,requiresIsolatedRestoreProof:true};
    }catch{return fail();}
  };
}
