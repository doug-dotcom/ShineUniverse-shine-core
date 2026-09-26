const JSON_HEADERS={
  'content-type':'application/json; charset=utf-8',
  'cache-control':'no-store'
};

const json=(status,body)=>new Response(JSON.stringify(body),{status,headers:JSON_HEADERS});
const healthPath=p=>p==='/health'||p.endsWith('/foundation-gateway/health');
const evaluatePath=p=>p==='/v1/access/evaluate'||p.endsWith('/foundation-gateway/v1/access/evaluate');

/** @param {{gateway:any, authenticate:any, maxBodyBytes?:number}} [options] */\nexport function createFoundationHttpHandler({gateway,authenticate,maxBodyBytes=16*1024}={}){
  if(typeof gateway!=='function') throw new TypeError('gateway must be a function');
  if(typeof authenticate!=='function') throw new TypeError('authenticate must be a function');

  return async function handle(request){
    const url=new URL(request.url);
    if(request.method==='GET'&&healthPath(url.pathname)){
      return json(200,{service:'shine-foundation-gateway',status:'ok',schemaVersion:'1.0.0'});
    }
    if(!evaluatePath(url.pathname)) return json(404,{error:'not-found'});
    if(request.method!=='POST') return json(405,{error:'method-not-allowed'});

    const contentType=request.headers.get('content-type')??'';
    if(!contentType.toLowerCase().startsWith('application/json')){
      return json(415,{error:'unsupported-media-type'});
    }

    const declared=Number(request.headers.get('content-length'));
    if(Number.isFinite(declared)&&declared>maxBodyBytes) return json(413,{error:'request-too-large'});

    let raw;
    try{ raw=await request.text(); }catch{ return json(400,{error:'invalid-body'}); }
    if(new TextEncoder().encode(raw).byteLength>maxBodyBytes) return json(413,{error:'request-too-large'});

    let envelope;
    try{ envelope=JSON.parse(raw); }catch{ return json(400,{error:'invalid-json'}); }

    let authContext;
    try{ authContext=await authenticate(request); }catch{ return json(401,{error:'unauthenticated'}); }

    const result=await gateway({envelope,authContext});
    const status={allowed:200,denied:403,invalid:400,unavailable:503}[result.status]??500;
    return json(status,result);
  };
}
