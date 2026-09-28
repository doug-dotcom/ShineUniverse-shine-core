import postgres from 'npm:postgres@3.4.9';

const CONTRACT='shine-defence/supabase-runtime-receipt-v1';
const PROJECT_REF=/^[a-z]{20}$/;
const DEPLOYMENT=/^([a-z]{20})_([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})_([0-9]+)$/i;

const supabaseUrl=Deno.env.get('SUPABASE_URL')??'';
const dbUrl=Deno.env.get('SUPABASE_DB_URL')??'';
const region=Deno.env.get('SB_REGION')??'unknown';
const deploymentId=Deno.env.get('DENO_DEPLOYMENT_ID')??'';
const executionId=Deno.env.get('SB_EXECUTION_ID')??'';

const projectRef=(()=>{
  try{
    const host=new URL(supabaseUrl).hostname;
    const match=host.match(/^([a-z]{20})\.supabase\.co$/);
    return match?.[1]??null;
  }catch{return null}
})();

const sql=postgres(dbUrl,{
  max:1,
  prepare:false,
  connect_timeout:3,
  idle_timeout:20
});

const json=(status:number,body:unknown)=>new Response(JSON.stringify(body),{
  status,
  headers:{
    'content-type':'application/json',
    'cache-control':'no-store',
    'x-content-type-options':'nosniff'
  }
});

Deno.serve(async(req:Request)=>{
  if(req.method!=='GET'&&req.method!=='HEAD') return json(405,{error:'method-not-allowed'});

  const deploymentMatch=deploymentId.match(DEPLOYMENT);
  const identityOk=Boolean(
    projectRef&&PROJECT_REF.test(projectRef)&&
    deploymentMatch&&deploymentMatch[1]===projectRef
  );

  let databaseReachable=false;
  let serverVersion:string|null=null;
  let databaseName:string|null=null;
  let dbErrorCode:string|null=null;

  try{
    const rows=await sql`
      select
        current_setting('server_version')::text as server_version,
        current_database()::text as database_name
    `;
    serverVersion=String(rows[0]?.server_version??'');
    databaseName=String(rows[0]?.database_name??'');
    databaseReachable=Boolean(serverVersion&&databaseName);
  }catch(error){
    const code=error&&typeof error==='object'&&'code' in error?String((error as any).code):'db-unavailable';
    dbErrorCode=code.slice(0,64);
  }

  const body={
    contract:CONTRACT,
    schemaVersion:'1.0.0',
    provider:'supabase',
    projectRef,
    function:{
      deploymentId:deploymentId||null,
      functionId:deploymentMatch?.[2]?.toLowerCase()??null,
      version:deploymentMatch?Number(deploymentMatch[3]):null,
      region,
      executionId:executionId||null
    },
    database:{
      reachable:databaseReachable,
      serverVersion,
      databaseName,
      errorCode:dbErrorCode
    },
    identityOk,
    observedAt:new Date().toISOString()
  };

  const status=identityOk&&databaseReachable?200:503;
  if(req.method==='HEAD') return new Response(null,{status,headers:{'cache-control':'no-store'}});
  return json(status,body);
});
