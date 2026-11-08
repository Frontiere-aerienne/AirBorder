import provider, { airportFacilities } from '../../Backend/src/index.js';

// Public routes return only public directory data or arithmetic over bounded
// durations. Provider, document, reminder, and entry routes keep native auth.
const PUBLIC_ROUTES = new Set(['/api/health', '/api/facilities', '/api/connection']);
const MAX_BODY = 2048;

function json(body, status=200, headers={}) {
  return new Response(JSON.stringify(body), {status, headers:{
    'content-type':'application/json; charset=utf-8',
    'cache-control':'no-store',
    'x-content-type-options':'nosniff',
    'referrer-policy':'no-referrer', ...headers
  }});
}

function explicitOrigin(origin, env) {
  return String(env.ALLOWED_ORIGINS||'').split(',').map(v=>v.trim()).filter(Boolean).includes(origin);
}

function publicOrigin(origin, env) {
  if(explicitOrigin(origin,env)) return true;
  try {
    const u = new URL(origin);
    const suffix = String(env.PUBLIC_FIGMA_PREVIEW_SUFFIX||'').toLowerCase();
    if(u.protocol!=='https:'||u.port||u.origin!==origin)return false;
    const runningPreview=suffix==='makeproxy-c.figma.site' &&
      /^app-[a-z0-9]+$/.test(u.hostname.slice(0,-suffix.length-1)) &&
      u.hostname.endsWith('.'+suffix);
    const cachedPreview=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}-figmacachedpreview\.figma\.site$/.test(u.hostname);
    return runningPreview||cachedPreview;
  } catch { return false; }
}

function withCors(response, origin) {
  const h = new Headers(response.headers);
  h.set('access-control-allow-origin',origin);
  h.set('vary','Origin');
  // Deliberately no Allow-Credentials; public routes use no cookies or tokens.
  return new Response(response.body,{status:response.status,headers:h});
}

async function quota(request,env) {
  if(!env.API_RATE_LIMITER?.limit) return json({error:'temporarily_unavailable'},503);
  const ip=request.headers.get('cf-connecting-ip')||'anonymous';
  const bytes=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(ip));
  const key='public:'+Array.from(new Uint8Array(bytes),b=>b.toString(16).padStart(2,'0')).join('');
  try {
    const result=await env.API_RATE_LIMITER.limit({key});
    return result.success?null:json({error:'too_many_requests'},429,{'retry-after':'60'});
  } catch {return json({error:'temporarily_unavailable'},503);}
}

async function readDurations(request) {
  const declared=Number(request.headers.get('content-length')||0);
  if(declared>MAX_BODY) throw {status:413,error:'request_too_large'};
  if((request.headers.get('content-type')||'').split(';')[0].trim()!=='application/json')
    throw {status:415,error:'json_required'};
  const reader=request.body?.getReader();
  if(!reader) throw {status:400,error:'invalid_request'};
  const decoder=new TextDecoder();let body='',length=0;
  while(true){
    const {done,value}=await reader.read();if(done)break;
    length+=value.byteLength;
    if(length>MAX_BODY){await reader.cancel();throw {status:413,error:'request_too_large'};}
    body+=decoder.decode(value,{stream:true});
  }
  body+=decoder.decode();
  let data;try{data=JSON.parse(body);}catch{throw {status:400,error:'invalid_request'};}
  if(!data||typeof data!=='object'||Array.isArray(data))throw {status:400,error:'invalid_request'};
  const fields=['availableMinutes','walkingMinutes','activityMinutes','bufferMinutes'];
  if(Object.keys(data).some(k=>!fields.includes(k)))throw {status:400,error:'unexpected_field'};
  for(const k of fields){
    if(typeof data[k]!=='number'||!Number.isFinite(data[k])||data[k]<0||data[k]>1440)
      throw {status:400,error:'invalid_duration'};
  }
  return data;
}

export function assessConnection(data){
  const requiredMinutes=data.walkingMinutes+data.activityMinutes+data.bufferMinutes;
  const spareMinutes=Math.floor(data.availableMinutes-requiredMinutes);
  // Arithmetic checks the supplied time budget. It cannot authorize entry or
  // guarantee connection safety, queues, real location, or flight accuracy.
  return {availableMinutes:data.availableMinutes,requiredMinutes,spareMinutes,
    nextAction:spareMinutes>0?'time_available':'return_to_gate',
    canFit:spareMinutes>0, method:'deterministic-time-budget-v1'};
}

async function publicFetch(request,env,url){
  const limited=await quota(request,env);if(limited)return limited;
  const expected=url.pathname==='/api/connection'?'POST':'GET';
  if(request.method!==expected)return json({error:'method_not_allowed'},405,{allow:expected});
  if(url.pathname==='/api/health')return json({status:'ok',service:'airborder',
    capabilities:{airportDirectory:true,connectionTiming:true,liveFlights:Boolean(env.FLIGHTAWARE_AEROAPI_KEY||env.AMADEUS_CLIENT_ID&&env.AMADEUS_CLIENT_SECRET)},
    checkedAt:new Date().toISOString()});
  if(url.pathname==='/api/facilities'){
    const airport=(url.searchParams.get('airport')||'HND').toUpperCase();
    if(!/^[A-Z]{3}$/.test(airport))return json({error:'invalid_airport'},400);
    return airportFacilities(airport);
  }
  if(url.pathname==='/api/connection'){
    try{return json({...assessConnection(await readDurations(request)),calculatedAt:new Date().toISOString()});}
    catch(e){return json({error:e?.error||'invalid_request'},e?.status||400);}
  }
  return json({error:'not_found'},404);
}

export default {
  async fetch(request,env,ctx){
    const url=new URL(request.url),isPublic=PUBLIC_ROUTES.has(url.pathname);
    const origin=request.headers.get('origin');
    const allowed=origin&&(isPublic?publicOrigin(origin,env):explicitOrigin(origin,env));
    if(origin&&!allowed)return json({error:'origin_not_allowed'},403);
    if(request.method==='OPTIONS'){
      if(!origin||!allowed)return json({error:'origin_not_allowed'},403);
      const method=request.headers.get('access-control-request-method')||'GET';
      const permitted=isPublic?(url.pathname==='/api/connection'?['POST']:['GET']):['GET','POST'];
      const requestedHeaders=(request.headers.get('access-control-request-headers')||'').toLowerCase().split(',').map(h=>h.trim()).filter(Boolean);
      const headers=isPublic?['content-type']:['content-type','cf-access-jwt-assertion'];
      if(!permitted.includes(method)||requestedHeaders.some(h=>!headers.includes(h)))
        return withCors(json({error:'preflight_not_allowed'},403),origin);
      return withCors(new Response(null,{status:204,headers:{
        'access-control-allow-methods':permitted.join(', '),
        'access-control-allow-headers':headers.join(', '),
        'access-control-max-age':'600'
      }}),origin);
    }
    let response;
    try{response=isPublic?await publicFetch(request,env,url):await provider.fetch(request,env,ctx);}
    catch{response=json({error:'temporarily_unavailable'},503);}
    return allowed?withCors(response,origin):response;
  }
};
