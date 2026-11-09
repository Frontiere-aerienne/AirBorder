import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { build } from 'esbuild';
import { Miniflare } from 'miniflare';
import worker from '../src/index.js';
const owner='a'.repeat(64);
const event=(id,extra={})=>({eventId:`00000000-0000-4000-8000-${String(id).padStart(12,'0')}`,expectedOwner:owner,expectedRevision:0,phase:'arrival',step:'landed',value:'done',...extra});
const request=(method,data)=>['https://journey.internal/',{method,headers:{'x-journey-owner':owner,'content-type':'application/json'},...(data?{body:JSON.stringify(data)}:{})}];
test('SQLite durable state serializes concurrent events and persists across restart',async t=>{
 const dir=await mkdtemp(join(tmpdir(),'airborder-journey-'));let mf;
 t.after(async()=>{if(mf)await mf.dispose();await rm(dir,{recursive:true,force:true});});
 const entry=join(dir,'entry.js'),bundle=join(dir,'worker.js');
 await writeFile(entry,`export { JourneyStore } from ${JSON.stringify(resolve('src/journey-store.js'))}; export default {fetch(){return new Response('ok')}};`);
 await build({entryPoints:[entry],outfile:bundle,bundle:true,format:'esm',platform:'browser'});
 const config={modules:true,script:await readFile(bundle,'utf8'),compatibilityDate:'2025-01-01',durableObjects:{JOURNEY_STORE:{className:'JourneyStore',useSQLite:true}},durableObjectsPersist:join(dir,'storage')};
 mf=new Miniflare(config);let ns=await mf.getDurableObjectNamespace('JOURNEY_STORE'),stub=ns.get(ns.idFromName('owner-trip-leg'));
 let r=await stub.fetch(...request('GET'));assert.equal((await r.json()).revision,0);
 const [a,b]=await Promise.all([stub.fetch(...request('POST',event(1))),stub.fetch(...request('POST',event(2)))]);assert.deepEqual([a.status,b.status].sort(),[200,409]);
 const win=a.status===200?event(1):event(2),result=await(a.status===200?a:b).json();assert.equal(result.revision,1);
 r=await stub.fetch(...request('POST',win));assert.deepEqual(await r.json(),result);
 r=await stub.fetch(...request('POST',{...win,value:'pending'}));assert.equal(r.status,409);assert.equal((await r.json()).error,'event_id_conflict');
 r=await stub.fetch(...request('POST',event(3,{expectedOwner:'b'.repeat(64)})));assert.equal(r.status,403);
 r=await stub.fetch(...request('POST',event(4,{expectedRevision:1,step:'landed',value:'not-needed'})));assert.equal(r.status,400);
 r=await stub.fetch(...request('POST',event(5,{expectedRevision:1,step:'passport',value:'not-needed'})));assert.equal(r.status,200);
 r=await stub.fetch(...request('POST',event(6,{expectedRevision:2,phase:'departure',step:null,value:null})));assert.equal(r.status,200);
 await mf.dispose();mf=new Miniflare(config);ns=await mf.getDurableObjectNamespace('JOURNEY_STORE');stub=ns.get(ns.idFromName('owner-trip-leg'));
 r=await stub.fetch(...request('GET'));const saved=await r.json();assert.equal(saved.revision,3);assert.equal(saved.phase,'departure');assert.equal(saved.status.arrival.passport,'not-needed');
 r=await ns.get(ns.idFromName('other-owner-or-leg')).fetch(...request('GET'));assert.equal((await r.json()).revision,0);
});
test('journey routes enforce auth, owner, limiter and bounded inputs',async()=>{
 const calls=[];const namespace={idFromName:n=>n,get:n=>({fetch:async()=>{calls.push(n);return new Response('{}');}})};
 const base={REQUEST_AUTH_MODE:'none',DEPLOYMENT_ENVIRONMENT:'development',REQUIRE_RATE_LIMITER:'true',API_RATE_LIMITER:{limit:async()=>({success:true})},JOURNEY_STORE:namespace};
 const path='https://example.test/v1/journeys/trip1/leg1';
 let r=await worker.fetch(new Request(path),{...base,REQUEST_AUTH_MODE:'cloudflare-access'});assert.equal(r.status,503);
 r=await worker.fetch(new Request(path),{...base,DEPLOYMENT_ENVIRONMENT:'production'});assert.equal(r.status,503);
 r=await worker.fetch(new Request(path),{...base,API_RATE_LIMITER:undefined});assert.equal(r.status,503);
 r=await worker.fetch(new Request(path),base);assert.equal(r.status,200);assert.match(calls[0],/^[a-f0-9]{64}$/);
 r=await worker.fetch(new Request(path,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(event(7))}),base);assert.equal(r.status,403);assert.equal(calls.length,1);
 r=await worker.fetch(new Request(path,{method:'POST',headers:{'content-type':'application/json'},body:'{'}),base);assert.equal(r.status,400);
 r=await worker.fetch(new Request(path,{method:'POST',headers:{'content-type':'application/json'},body:'x'.repeat(3000)}),base);assert.equal(r.status,413);
});

test('signed Access identities scope journeys and reject cross-account writes',async()=>{
 const key=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
 const jwk=await crypto.subtle.exportKey('jwk',key.publicKey);Object.assign(jwk,{kid:'journey-test-key',alg:'RS256',use:'sig'});
 const enc=x=>Buffer.from(typeof x==='string'?x:new Uint8Array(x)).toString('base64url');
 async function token(sub){const header=enc(JSON.stringify({alg:'RS256',kid:jwk.kid}));const payload=enc(JSON.stringify({iss:'https://journeytest.cloudflareaccess.com',aud:['journey-aud'],sub,exp:Math.floor(Date.now()/1000)+600}));const sig=await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key.privateKey,new TextEncoder().encode(`${header}.${payload}`));return `${header}.${payload}.${enc(sig)}`;}
 const [a,b]=await Promise.all([token('traveler-a'),token('traveler-b')]);const calls=[];
 const namespace={idFromName:n=>n,get:n=>({fetch:async req=>{calls.push({id:n,owner:req.headers.get('x-journey-owner')});return new Response('{}');}})};
 const env={REQUEST_AUTH_MODE:'cloudflare-access',CF_ACCESS_TEAM_DOMAIN:'journeytest.cloudflareaccess.com',CF_ACCESS_AUD:'journey-aud',REQUIRE_RATE_LIMITER:'true',API_RATE_LIMITER:{limit:async()=>({success:true})},JOURNEY_STORE:namespace};
 const original=globalThis.fetch;globalThis.fetch=async()=>new Response(JSON.stringify({keys:[jwk]}),{headers:{'content-type':'application/json'}});
 try{
  const path='https://example.test/v1/journeys/trip/leg';
  for(const jwt of [a,b]){const r=await worker.fetch(new Request(path,{headers:{'cf-access-jwt-assertion':jwt}}),env);assert.equal(r.status,200);}
  assert.notEqual(calls[0].owner,calls[1].owner);assert.notEqual(calls[0].id,calls[1].id);
  const cross=await worker.fetch(new Request(path,{method:'POST',headers:{'content-type':'application/json','cf-access-jwt-assertion':b},body:JSON.stringify(event(8,{expectedOwner:calls[0].owner}))}),env);
  assert.equal(cross.status,403);assert.equal(calls.length,2);
  const bad=await worker.fetch(new Request(path,{headers:{'cf-access-jwt-assertion':a+'x'}}),env);assert.equal(bad.status,401);
 }finally{globalThis.fetch=original;}
});
