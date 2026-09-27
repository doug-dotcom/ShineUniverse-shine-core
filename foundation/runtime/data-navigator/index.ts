import postgres from 'npm:postgres@3.4.9';

const MAX_BODY_BYTES=4096;
const MAX_QUERY_CHARS=500;

const requireEnv=(name:string)=>{
  const value=Deno.env.get(name);
  if(!value) throw new Error('Missing required environment variable: '+name);
  return value;
};

const rawSql=postgres(requireEnv('SUPABASE_DB_URL'),{
  max:1,
  prepare:false,
  idle_timeout:20,
  connect_timeout:10
});

const sql:any=(strings:any,...values:any[])=>rawSql.begin(async(tx:any)=>{
  await tx.unsafe('set local role foundation_gateway');
  return tx(strings,...values);
});

const sha256Hex=async(value:string)=>{
  const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map(byte=>byte.toString(16).padStart(2,'0')).join('');
};

const json=(status:number,body:unknown)=>new Response(JSON.stringify(body),{
  status,
  headers:{
    'content-type':'application/json; charset=utf-8',
    'cache-control':'no-store'
  }
});

Deno.serve(async(request:Request)=>{
  if(request.method!=='POST') return json(405,{error:'method-not-allowed'});

  const contentLength=Number(request.headers.get('content-length')||'0');
  if(Number.isFinite(contentLength)&&contentLength>MAX_BODY_BYTES){
    return json(413,{error:'body-too-large'});
  }

  const appToken=request.headers.get('x-shine-app-token')??'';
  if(appToken.length<32||appToken.length>4096){
    return json(401,{error:'missing-or-invalid-app-credential'});
  }

  let raw='';
  try{raw=await request.text()}catch{return json(400,{error:'invalid-body'})}
  if(new TextEncoder().encode(raw).byteLength>MAX_BODY_BYTES){
    return json(413,{error:'body-too-large'});
  }

  let body:any;
  try{body=JSON.parse(raw)}catch{return json(400,{error:'invalid-json'})}

  const appId=typeof body?.appId==='string'?body.appId.trim():'';
  const query=typeof body?.query==='string'?body.query.trim():'';
  if(!appId||!query||query.length>MAX_QUERY_CHARS){
    return json(400,{error:'invalid-navigation-request'});
  }

  try{
    const tokenHash=await sha256Hex(appToken);
    const credentials=await sql`
      select credential_id::text,app_id
      from foundation.effective_app_credentials
      where token_hash=${tokenHash}
        and effective_status='active'
      limit 2
    `;
    if(!Array.isArray(credentials)||credentials.length!==1){
      return json(401,{error:'app-credential-unverified'});
    }
    if(String(credentials[0].app_id)!==appId){
      return json(403,{error:'app-caller-mismatch'});
    }

    const mappings=await sql`
      select app_key
      from universe.foundation_app_links
      where foundation_app_id=${appId}
        and connection_status='registered'
      limit 2
    `;
    if(!Array.isArray(mappings)||mappings.length!==1){
      return json(409,{error:'app-navigation-link-unavailable'});
    }

    const appKey=String(mappings[0].app_key);
    const routes=await sql`
      select dataset_key,display_name,owner_app_key,route_mode,capability_id,
             project_ref,canonical_schema,canonical_relation,data_class,
             freshness_model,recommended_use,route_note,related_dataset_keys,score
      from universe.resolve_data_route(${appKey},${query})
    `;

    return json(200,{
      navigatorResponse:'shine-universe/data-navigation-v1',
      schemaVersion:'1.1.0',
      requester:{appId,appKey},
      query,
      routes:Array.isArray(routes)?routes:[],
      accessNote:'Navigation results are metadata only. A returned capability or route does not grant access to underlying data.'
    });
  }catch{
    return json(503,{error:'navigation-unavailable'});
  }
});
