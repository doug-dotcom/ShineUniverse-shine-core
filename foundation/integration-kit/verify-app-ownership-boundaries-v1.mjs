export function verifyAppOwnershipBoundaries(contract, registryRows) {
  if (contract?.version !== "1.0.0" || contract.authority !== "catalogue-contract-only")
    throw new Error("ownership-contract-invalid");
  if (contract.policy?.catalogueMembershipGrantsAccess !== false ||
      contract.policy?.sharedRepositoryGrantsAccess !== false)
    throw new Error("ownership-implicit-access-prohibited");
  const seen = new Set(), gatewayIds = new Set();
  for (const app of contract.apps) {
    if (seen.has(app.app_key)) throw new Error("ownership-app-duplicate");
    seen.add(app.app_key);
    if (!/^[^/]+\/[^/]+$/.test(app.canonical_repo) ||
        app.codeOwner !== app.canonical_repo.split("/")[0] ||
        !app.integrationBoundary || !app.responsibility)
      throw new Error("ownership-boundary-incomplete");
    if (app.gatewayAppId !== null) {
      if (gatewayIds.has(app.gatewayAppId)) throw new Error("ownership-gateway-duplicate");
      gatewayIds.add(app.gatewayAppId);
    }
    const row = registryRows.find(r => r.app_key === app.app_key);
    if (!row || row.canonical_repo !== app.canonical_repo || row.category !== app.category)
      throw new Error("ownership-registry-drift");
  }
  if (seen.size !== registryRows.length ||
      registryRows.some(r => !seen.has(r.app_key)))
    throw new Error("ownership-registry-coverage-gap");
  return {state:"verified", appCount:seen.size, gatewayMappingCount:gatewayIds.size,
    grantsAccess:false, runtimeEnforced:false};
}
