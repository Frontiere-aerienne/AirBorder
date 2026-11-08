import {createRequire} from 'node:module';
import test from 'node:test';import assert from 'node:assert/strict';
const Sync=createRequire(import.meta.url)('../../journey-sync.js');
const owner='a'.repeat(64),record={owner,revision:0,phase:'transfer',status:{arrival:{},departure:{},transfer:{}}};
const storage=()=>{const m=new Map();return {getItem:k=>m.get(k),setItem:(k,v)=>m.set(k,v),removeItem:k=>m.delete(k)};};
test('offline outbox retries identical event and never silently rebases conflict',async()=>{
 let offline=false,conflict=false,requests=[];const s=new Sync({url:'/journey',storage:storage(),fetcher:async(url,init)=>{if(!init.method)return Response.json(record);requests.push(JSON.parse(init.body));if(offline)throw Error();return conflict?Response.json({}, {status:409}):Response.json({...record,revision:1});}});
 await s.start();offline=true;s.enqueue({phase:'arrival',step:'landed',value:'done'});await new Promise(r=>setTimeout(r,0));
 assert.equal(s.queue.length,1);offline=false;conflict=true;await s.flush();assert.equal(s.queue.length,1);assert.deepEqual(requests[0],requests[1]);
 conflict=false;await s.flush();assert.equal(s.queue.length,0);assert.equal(s.record.revision,1);
});
test('logout blocks an in-flight response from restoring progress',async()=>{
 let resolve,applied=0;const s=new Sync({url:'/journey',storage:storage(),onRecord:()=>applied++,fetcher:()=>new Promise(r=>resolve=r)});const pending=s.start();s.stop();resolve(Response.json(record));await pending;assert.equal(applied,0);assert.equal(s.owner,null);
});
test('confirmation during delayed initialization is sent after loading rather than overwritten',async()=>{
 let release,sent=[],published=[];const s=new Sync({url:'/slow',storage:storage(),onRecord:r=>published.push(r),fetcher:async(u,init)=>{if(!init.method)return new Promise(r=>release=r);const e=JSON.parse(init.body);sent.push(e);return Response.json({...record,revision:1,status:{...record.status,arrival:{landed:'done'}}});}});
 const start=s.start();s.enqueue({phase:'arrival',step:'landed',value:'done'});release(Response.json(record));await start;
 assert.equal(sent.length,1);assert.equal(sent[0].expectedRevision,0);assert.equal(published.at(-1).status.arrival.landed,'done');assert.equal(s.queue.length,0);
});
test('replayed historical acknowledgement retains and publishes the newer fetched revision',async()=>{
 const disk=storage();disk.setItem(`airborder-sync:${owner}:/replay`,JSON.stringify([{eventId:crypto.randomUUID(),expectedOwner:owner,expectedRevision:0,phase:'arrival',step:'landed',value:'done'}]));let published;
 const latest={...record,revision:2,phase:'departure'};
 const s=new Sync({url:'/replay',storage:disk,onRecord:r=>published=r,fetcher:async(u,init)=>Response.json(init.method?{...record,revision:1}:latest)});
 await s.start();assert.equal(s.record.revision,2);assert.equal(published.phase,'departure');assert.equal(s.queue.length,0);
});
