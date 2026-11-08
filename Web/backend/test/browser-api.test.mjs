import test from 'node:test';
import assert from 'node:assert/strict';
import worker from '../index.mjs';

const origin='https://app-abcd1234.makeproxy-c.figma.site';
const env={PUBLIC_FIGMA_PREVIEW_SUFFIX:'makeproxy-c.figma.site',REQUEST_AUTH_MODE:'cloudflare-access',
 DEPLOYMENT_ENVIRONMENT:'production',REQUIRE_RATE_LIMITER:'true',API_RATE_LIMITER:{limit:async()=>({success:true})}};
const request=(path,init={})=>new Request('https://worker.test'+path,{...init,headers:{origin,...init.headers}});

test('Figma can read the non-sensitive health response without cookies',async()=>{
 const r=await worker.fetch(request('/api/health'),env);assert.equal(r.status,200);
 assert.equal(r.headers.get('access-control-allow-origin'),origin);
 assert.equal(r.headers.get('access-control-allow-credentials'),null);
 assert.equal((await r.json()).capabilities.liveFlights,false);
});
test('lookalike and non-Figma origins are rejected',async()=>{
 for(const bad of ['https://app-a.makeproxy-c.figma.site.evil.test','http://app-a.makeproxy-c.figma.site','https://evil.test','null']){
  const r=await worker.fetch(request('/api/facilities',{headers:{origin:bad}}),env);assert.equal(r.status,403);assert.equal(r.headers.get('access-control-allow-origin'),null);
 }
});
test('the observed Figma cached-preview hostname can read public data only',async()=>{
 const headers={origin:'https://9b8ca9d2-8ce6-4257-b1d5-e745080d57c9-figmacachedpreview.figma.site'};
 assert.equal((await worker.fetch(request('/api/facilities',{headers}),env)).status,200);
 assert.equal((await worker.fetch(request('/v1/flights/search',{headers}),env)).status,403);
 headers.origin='https://9b8ca9d2-8ce6-4257-b1d5-e745080d57c9-figmacachedpreview.figma.site.evil.test';
 assert.equal((await worker.fetch(request('/api/facilities',{headers}),env)).status,403);
});
test('provider routes remain protected and do not inherit public Figma CORS',async()=>{
 assert.equal((await worker.fetch(request('/v1/flights/search'),env)).status,403);
 const r=await worker.fetch(new Request('https://worker.test/v1/flights/search'),env);
 assert.equal(r.status,503);assert.equal((await r.json()).error,'authentication_not_configured');
});
test('only the intended JSON preflight is allowed',async()=>{
 const init={method:'OPTIONS',headers:{'access-control-request-method':'POST','access-control-request-headers':'content-type'}};
 assert.equal((await worker.fetch(request('/api/connection',init),env)).status,204);
 init.headers['access-control-request-headers']='authorization';
 assert.equal((await worker.fetch(request('/api/connection',init),env)).status,403);
});
test('connection calculation distinguishes spare time, exact cutoff, and urgent return',async()=>{
 for(const [available,canFit,spare] of [[325,true,268],[57,false,0],[25,false,-32]]){
  const r=await worker.fetch(request('/api/connection',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({availableMinutes:available,walkingMinutes:12,activityMinutes:25,bufferMinutes:20})}),env);
  const data=await r.json();assert.equal(r.status,200);assert.equal(data.canFit,canFit);assert.equal(data.spareMinutes,spare);
 }
});
test('oversized bodies, personal-data fields, malformed and invalid durations are rejected',async()=>{
 for(const body of ['x'.repeat(3000),'{bad',JSON.stringify({passportNumber:'redacted'}),JSON.stringify({availableMinutes:-1,walkingMinutes:12,activityMinutes:25,bufferMinutes:20})]){
  const r=await worker.fetch(request('/api/connection',{method:'POST',headers:{'content-type':'application/json'},body}),env);assert.ok([400,413].includes(r.status));
 }
});
test('facility results preserve native registry sources and access zones',async()=>{
 const r=await worker.fetch(request('/api/facilities?airport=HND'),env);const data=await r.json();
 assert.equal(r.status,200);assert.equal(data.airportCode,'HND');assert.equal(data.facilities.length,7);
 assert.equal(data.facilities.find(f=>f.id==='hnd-work-boxes').accessZone,'airportLandside');
 assert.ok(data.facilities.every(f=>f.officialRecordURL.startsWith('https://')));
 const other=await worker.fetch(request('/api/facilities?airport=NRT'),env);assert.equal((await other.json()).availability,'registryUnavailable');
});
test('rate limits and absent bindings fail closed',async()=>{
 assert.equal((await worker.fetch(request('/api/health'),{...env,API_RATE_LIMITER:undefined})).status,503);
 const r=await worker.fetch(request('/api/health'),{...env,API_RATE_LIMITER:{limit:async()=>({success:false})}});
 assert.equal(r.status,429);assert.equal(r.headers.get('retry-after'),'60');
});

test('limiter exceptions fail closed and missing or null durations remain unknown',async()=>{
 const failed=await worker.fetch(request('/api/health'),{...env,API_RATE_LIMITER:{limit:async()=>{throw new Error('unavailable');}}});
 assert.equal(failed.status,503);
 for(const data of [{availableMinutes:60,walkingMinutes:2,activityMinutes:3}, {availableMinutes:60,walkingMinutes:null,activityMinutes:3,bufferMinutes:4}]){
  const r=await worker.fetch(request('/api/connection',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(data)}),env);
  assert.equal(r.status,400);assert.equal((await r.json()).error,'invalid_duration');
 }
});
