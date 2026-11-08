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
