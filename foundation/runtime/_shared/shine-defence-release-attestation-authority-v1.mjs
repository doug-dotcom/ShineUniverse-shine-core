export const SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY_VERSION='1.0.0';

export const SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY=Object.freeze({
  repository:'doug-dotcom/ShineUniverse-shine-core',
  repositoryId:'1072897952',
  workflowPath:'.github/workflows/shine-defence-release-attestation-v1.yml',
  authoritySha:'7bfd7fe685b4b2da814ac53dafdbfac2350591c8'
});

export const SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY_REF=
  SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY.repository+
  '/'+SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY.workflowPath+
  '@'+SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY.authoritySha;

export const SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY_SHA=
  SHINE_DEFENCE_RELEASE_ATTESTATION_AUTHORITY.authoritySha;
