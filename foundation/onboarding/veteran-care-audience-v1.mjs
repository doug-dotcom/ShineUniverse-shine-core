import {VETERAN_CARE_ISSUER} from './veteran-care-identity-v1.mjs';
import {createVeteranCareBoundIdentityVerifier} from './veteran-care-project-boundary-v1.mjs';

const deny=reasonCode=>({status:'denied',reasonCode});
const unavailable=()=>({status:'unavailable',reasonCode:'vc-token-authority-unavailable'});
const TOKEN_AUDIENCE='authenticated';

// Server-only Supabase Auth instance for the dedicated VC project. getClaims
// must verify the explicit JWT using the supported SDK; decode/getSession are
// not substitutes. The consumer owns client setup and live acceptance.
export function createVeteranCareAudienceIdentityVerifier({auth,...options}={}){
  if(typeof auth?.getClaims!=='function') throw new TypeError('verified token claims authority is required');
  const getClaims=auth.getClaims.bind(auth);
  const verifyIdentity=createVeteranCareBoundIdentityVerifier(options);
  const appId=options.appId;
  return async function verify({authContext}={}){
    // Snapshot the exact proof before awaiting either authority; caller-supplied
    // audience/app/claims fields never enter the authority request.
    const proof=Object.freeze({appToken:authContext?.appToken,jwt:authContext?.jwt,userToken:authContext?.userToken});
    const identity=await verifyIdentity({authContext:proof});
    if(identity.status!=='verified') return identity;
    try{
      const result=await getClaims(proof.jwt);
      if(result?.error||!result?.data?.claims) return deny('vc-token-unverified');
      const claims=result.data.claims;
      if(claims.iss!==VETERAN_CARE_ISSUER) return deny('vc-token-issuer-mismatch');
      const aud=claims.aud;
      if(aud!==TOKEN_AUDIENCE&&!(Array.isArray(aud)&&aud.length===1&&aud[0]===TOKEN_AUDIENCE))
        return deny('vc-token-audience-mismatch');
      if(claims.role!=='authenticated'||claims.sub!==identity.identity.authSubject)
        return deny('vc-token-identity-mismatch');
      // Server context only, not a portable credential or a resource grant.
      return {...identity,audience:{appId,issuer:VETERAN_CARE_ISSUER,tokenAudience:TOKEN_AUDIENCE}};
    }catch{return unavailable();}
  };
}
