const SHA=/^[a-f0-9]{40}$/;
const APP=/^[a-z0-9][a-z0-9-]{0,63}$/;
const DISPLAY={
  reviewed_release:'Protected by Shine Defence',
  revoked_release:'Defence certification withdrawn',
  unreviewed_revision:'Defence review pending for this revision',
  profile_drift:'Defence profile changed since review',
  uncertified:'No reviewed Shine Defence release'
};

const publicResult=(state,app,extra={})=>({
  defenceStatus:'shine-defence/public-release-status-v1',
  schemaVersion:'1.0.0',
  appId:app?.id??extra.appId,
  state,
  badgeCurrent:state==='reviewed_release',
  display:DISPLAY[state],
  ...(app?{
    reviewedCommitSha:app.reviewCommitSha,
    reviewedProfileBlobSha:app.profileBlobSha,
    reviewedProfileVersion:app.profileVersion,
    policies:[...app.policies]
  }:{}),
  ...extra
});

export function createPublicDefenceStatusService({ledger,revocations}={}){
  if(ledger?.ledger!=='shine-defence/ecosystem-profile-ledger-v1'||!Array.isArray(ledger?.apps)){
    throw new TypeError('valid Defence ecosystem ledger is required');
  }
  if(revocations?.ledger!=='shine-defence/revocations-v1'||!Array.isArray(revocations?.revocations)){
    throw new TypeError('valid Defence revocation ledger is required');
  }
  const apps=new Map(ledger.apps.map(app=>[app.id,app]));

  return function evaluate({appId,releaseSha,profileBlobSha}={}){
    if(!APP.test(appId||'')||!SHA.test(releaseSha||'')||!SHA.test(profileBlobSha||'')){
      throw new TypeError('invalid Defence status query');
    }
    const app=apps.get(appId);
    if(!app)return publicResult('uncertified',null,{appId});

    const revoked=revocations.revocations.find(item=>
      item.appId===appId&&
      item.reviewCommitSha===releaseSha&&
      item.profileBlobSha===profileBlobSha
    );
    if(revoked){
      return publicResult('revoked_release',app,{
        revocation:{
          revocationId:revoked.revocationId,
          revokedAt:revoked.revokedAt,
          reasonCode:revoked.reasonCode,
          publicReason:revoked.publicReason,
          ...(revoked.replacementReviewCommitSha?{replacementReviewCommitSha:revoked.replacementReviewCommitSha}:{})
        }
      });
    }
    if(releaseSha!==app.reviewCommitSha)return publicResult('unreviewed_revision',app);
    if(profileBlobSha!==app.profileBlobSha)return publicResult('profile_drift',app);
    return publicResult('reviewed_release',app);
  };
}
