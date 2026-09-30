export async function bindGithubOidcOperation({
  sql,
  identity,
  audience,
  operation,
  targetKey,
  request
}={}){
  if(!sql||typeof sql!=='function') throw new TypeError('postgres client required');
  if(!identity||typeof identity!=='object') throw new TypeError('verified OIDC identity required');
  if(typeof audience!=='string'||!audience) throw new TypeError('OIDC audience required');
  if(typeof operation!=='string'||!operation) throw new TypeError('OIDC operation required');
  if(typeof targetKey!=='string'||!targetKey) throw new TypeError('OIDC target key required');
  if(!request||typeof request!=='object'||Array.isArray(request)) throw new TypeError('OIDC request object required');

  const rows=await sql`
    select foundation.bind_github_oidc_operation_v1(
      ${identity.repository},
      ${identity.ref},
      ${identity.workflowRef},
      ${identity.runId},
      ${identity.runAttempt},
      ${identity.eventName},
      ${audience},
      ${operation},
      ${targetKey},
      ${sql.json(request)}
    ) as binding
  `;

  const binding=rows[0]?.binding??null;
  if(!binding||binding.githubOidcOperationBinding!=='shine-defence/github-oidc-operation-binding-v1'){
    throw new Error('OIDC replay binding unavailable');
  }
  return binding;
}

export const oidcReplayConflict=binding=>binding?.status==='rejected-conflict';
export const oidcExactReplay=binding=>binding?.status==='replayed-exact';
export const GITHUB_OIDC_OPERATION_BINDING_VERSION='1.0.0';
