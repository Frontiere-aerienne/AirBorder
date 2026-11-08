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
test('confirmation during conflict recovery waits for GET before posting and publishing',async()=>{
 let release,loading=false,posts=0,published=[];
 const s=new Sync({url:'/recover',storage:storage(),onRecord:r=>published.push(r),fetcher:async(u,init)=>{
  if(!init.method)return loading?new Promise(r=>release=r):Response.json(record);
  posts++;return Response.json({...record,revision:1,status:{...record.status,arrival:{landed:'done'}}});
 }});
 await s.start();loading=true;const recovery=s.useSaved();s.enqueue({phase:'arrival',step:'landed',value:'done'});
 assert.equal(posts,0);release(Response.json(record));await recovery;
 assert.equal(posts,1);assert.equal(s.record.revision,1);assert.equal(published.at(-1).status.arrival.landed,'done');assert.equal(s.queue.length,0);
});
test('failed recovery drains staged confirmations before later updates',async()=>{
 let reject,recover=false,sent=[],snapshot=structuredClone(record);
 const s=new Sync({url:'/failed-recovery',storage:storage(),fetcher:async(u,init)=>{
  if(!init.method)return recover?new Promise((_,r)=>reject=r):Response.json(snapshot);
  const e=JSON.parse(init.body);sent.push(e);snapshot={...snapshot,revision:snapshot.revision+1,status:structuredClone(snapshot.status)};snapshot.status[e.phase][e.step]=e.value;return Response.json(snapshot);
 }});
 await s.start();recover=true;const recovery=s.useSaved();s.enqueue({phase:'arrival',step:'landed',value:'done'});reject(Error('offline'));await recovery;
 s.enqueue({phase:'arrival',step:'passport',value:'done'});await new Promise(r=>setTimeout(r,0));await s.flush();
 assert.deepEqual(sent.map(e=>e.step),['landed','passport']);assert.equal(s.record.status.arrival.landed,'done');assert.equal(s.record.status.arrival.passport,'done');assert.equal(s.queue.length,0);
});
test('unavailable storage does not drop staged edits',async()=>{
 let release,sent=[];const s=new Sync({url:'/no-storage',storage:{getItem(){return null;},setItem(){throw Error('quota');}},fetcher:async(u,i)=>{if(!i.method)return new Promise(r=>release=r);sent.push(JSON.parse(i.body));return Response.json({...record,revision:sent.length});}});
 const load=s.start();s.enqueue({phase:'arrival',step:'landed',value:'done'});s.enqueue({phase:'arrival',step:'passport',value:'done'});release(Response.json(record));await load;assert.deepEqual(sent.map(e=>e.step),['landed','passport']);
});
test('expired authentication preserves owner outbox until same-owner reauthentication',async()=>{
 const disk=storage();let expired=true;const s=new Sync({url:'/auth',storage:disk,fetcher:async(u,i)=>Response.json(!i.method?record:expired?{}:{...record,revision:1},{status:i.method&&expired?401:200})});
 await s.start();s.enqueue({phase:'arrival',step:'landed',value:'done'});await new Promise(r=>setTimeout(r,0));assert.equal(s.queue.length,1);assert.equal(JSON.parse(disk.getItem(s.key())).length,1);expired=false;await s.start();assert.equal(s.queue.length,0);assert.equal(s.record.revision,1);
});
test('saved and pending steps are restored even when replay is offline or conflicts',async()=>{
 for(const conflict of [false,true]){const disk=storage(),ownerRecord={...record,revision:5,phase:'arrival',status:{arrival:{landed:'done',passport:'done'},departure:{},transfer:{}}};
 disk.setItem(`airborder-sync:${owner}:/restore`,JSON.stringify([{eventId:crypto.randomUUID(),expectedOwner:owner,expectedRevision:4,phase:'arrival',step:'bags',value:'done'}]));let published;
 const s=new Sync({url:'/restore',storage:disk,onRecord:r=>published=r,fetcher:async(u,i)=>{if(!i.method)return Response.json(ownerRecord);if(conflict)return Response.json({}, {status:409});throw Error('offline');}});
 await s.start();assert.equal(published.phase,'arrival');assert.deepEqual(published.status.arrival,{landed:'done',passport:'done',bags:'done'});assert.equal(s.queue.length,1);assert.equal(s.record.revision,5);
 }
});
