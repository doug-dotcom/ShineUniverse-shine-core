import {createClient} from 'npm:@supabase/supabase-js@2.117.1';
import postgres from 'npm:postgres@3.4.9';
import {createFoundationGateway} from '../../gateway/gateway-core-v1.mjs';
import {createFoundationHttpHandler} from '../../gateway/http-handler-v1.mjs';
import {createSupabaseRuntimeAdapters} from '../supabase-runtime-adapters-v1.mjs';
import {createFoundationRuntimeDefenceGateV1} from '../runtime-defence-gate-v1.mjs';

const requireEnv=(name:string)=>{
  const value=Deno.env.get(name);
  if(!value) throw new Error('Missing required environment variable: '+name);
  return value;
};

const supabaseUrl=requireEnv('SUPABASE_URL');
const supabaseKey=Deno.env.get('SUPABASE_PUBLISHABLE_KEY')??requireEnv('SUPABASE_ANON_KEY');
const databaseUrl=requireEnv('FOUNDATION_DATABASE_URL');

const sql=postgres(databaseUrl,{max:1,prepare:false,idle_timeout:20,connect_timeout:10});
const authClient=createClient(supabaseUrl,supabaseKey,{
  auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}
});

const adapters=createSupabaseRuntimeAdapters({
  sql,
  authClient,
  defenceGate:createFoundationRuntimeDefenceGateV1()
});

const gateway=createFoundationGateway({adapters});

const handler=createFoundationHttpHandler({
  gateway,
  maxBodyBytes:16*1024,
  authenticate:async(request:Request)=>{
    const authorization=request.headers.get('authorization')??'';
    const appToken=request.headers.get('x-shine-app-token')??'';
    if(!authorization.startsWith('Bearer ')||!appToken) throw new Error('missing runtime credentials');
    return {jwt:authorization.slice('Bearer '.length),appToken};
  }
});

Deno.serve((request:Request)=>handler(request));
