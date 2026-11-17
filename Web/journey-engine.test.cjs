const {test}=require('node:test'),assert=require('node:assert/strict'),J=require('./journey-engine.js'),Demo=require('./demo-journey.js');
test('additive, unique, ordered, removable plans',()=>{const s=Demo.create();J.add(s,'coffee');J.add(s,'rest');J.add(s,'coffee');assert.equal(s.stops.length,2);J.move(s,'stop-rest',-1);assert.equal(s.stops[0].facilityId,'rest');J.remove(s,'stop-rest');assert.equal(s.stops[0].facilityId,'coffee');});
test('gate update preserves selections, full suffix and rejects duplicates and old updates',()=>{const d=Demo.driver('gate'),before=JSON.stringify(d.state.stops);d.step();assert.equal(d.state.gate,'108A');assert.equal(JSON.stringify(d.state.stops),before);const rev=d.state.dataRevision;assert.equal(J.observe(d.state,Demo.fixtures.gate.events[0]),false);J.observe(d.state,{id:'old',at:0,type:'gate',entityId:'flight-demo',value:'105'});assert.equal(d.state.gate,'108A');assert.equal(d.state.dataRevision,rev);});
test('weather only proposes removing selected outdoor stop',()=>{const indoor=Demo.driver('indoorRain');indoor.step();assert.deepEqual(J.recommendations(indoor.state),[]);const deck=Demo.driver('deckRain');deck.step();assert.equal(J.recommendations(deck.state)[0].stopId,'stop-deck');});
test('unknown and stale queues cannot produce confident recommendations',()=>{const d=Demo.driver('unknown');d.step();assert.equal(J.estimate(d.state).known,false);assert.deepEqual(J.recommendations(d.state),[]);const q=Demo.driver('queue');q.step();q.advance(20);assert.equal(J.estimate(q.state).known,false);});
test('apply validates revision, recomputes route and supports undo',()=>{const d=Demo.driver('queue');d.step();const s=d.state,r=J.recommendations(s)[0],before=J.estimate(s);assert.ok(r);assert.equal(J.apply(s,r),true);assert.equal(J.estimate(s).arrival,r.after);assert.ok(J.estimate(s).arrival<before.arrival);assert.equal(J.apply(s,r),false);assert.equal(J.undo(s),true);assert.equal(s.stops.length,2);const stale=J.recommendations(s)[0];J.add(s,'work');assert.equal(J.apply(s,stale),false);});
test('event updates and elapsed time invalidate outstanding Apply',()=>{const d=Demo.driver('queue');d.step();const r=J.recommendations(d.state)[0];d.advance(1);assert.equal(J.apply(d.state,r),false);});
test('replay reset is deterministic',()=>{const d=Demo.driver('queue');d.step();const first=JSON.stringify(d.state);d.reset();d.step();assert.equal(JSON.stringify(d.state),first);});
test('removing an off-route stop recomputes travel, required stops retained',()=>{const s=Demo.create();s.deadline=10;J.add(s,'deck');J.add(s,'coffee');const before=J.estimate(s);const r=J.recommendations(s).find(r=>r.stopId==='stop-deck');assert.ok(r.saved>20);s.stops[0].required=true;assert.ok(!J.recommendations(s).some(r=>r.stopId==='stop-deck'));assert.ok(before.travel>12);});
test('missing queue, unknown deadline and unknown gate remain unknown',()=>{for(const mutate of [s=>delete s.observations['queue:coffee'],s=>s.deadline=null,s=>s.gate='109B']){const s=Demo.create();J.add(s,'coffee');mutate(s);assert.equal(J.estimate(s).known,false);assert.deepEqual(J.recommendations(s),[]);}});
test('negative and nonfinite queue updates are rejected',()=>{for(const value of [-1,Infinity,NaN]){const s=Demo.create();assert.equal(J.observe(s,{id:'invalid',at:1,type:'queue',entityId:'coffee',value,expiresAt:60}),false);}});
test('completed stops do not affect route or recommendations',()=>{const s=Demo.create();J.add(s,'deck');s.stops[0].status='completed';s.deadline=1;assert.equal(J.estimate(s).travel,12);assert.deepEqual(J.recommendations(s),[]);});
test('only used transfers change timing',()=>{const a=Demo.driver('transferUsed'),b=Demo.driver('transferUnused');const beforeA=J.estimate(a.state).travel,beforeB=J.estimate(b.state).travel;a.step();b.step();assert.equal(J.estimate(a.state).travel-beforeA,20);assert.equal(J.estimate(b.state).travel,beforeB);});
test('canonical candidate target cannot be forged',()=>{const d=Demo.driver('queue');d.step();const r=J.recommendations(d.state)[0],other=d.state.stops.find(s=>s.id!==r.stopId).id;assert.equal(J.apply(d.state,{...r,stopId:other}),true);assert.ok(d.state.stops.some(s=>s.id===other));assert.ok(!d.state.stops.some(s=>s.id===r.stopId));});
test('flight delay does not move deadline',()=>{const s=Demo.create(),deadline=s.deadline;J.observe(s,{id:'delay',at:1,type:'flight-delay',entityId:'flight-demo',value:90});assert.equal(s.deadline,deadline);});
test('expired gate observation cannot support a confident route',()=>{const d=Demo.driver('gate');d.step();assert.equal(J.estimate(d.state).known,true);d.advance(59);assert.equal(J.estimate(d.state).known,false);assert.deepEqual(J.recommendations(d.state),[]);});
test('explicit completion preserves the plan and recomputes from the visited stop',()=>{const s=Demo.create();J.add(s,'coffee');J.add(s,'rest');s.deadline=20;const prior=J.recommendations(s)[0],revision=s.revision,now=s.now;assert.equal(J.complete(s,'stop-coffee'),true);assert.equal(s.revision,revision+1);assert.equal(s.now,now);assert.equal(s.position,s.catalog.coffee.position);assert.equal(s.stops[0].status,'completed');assert.equal(s.stops[1].status,'pending');assert.equal(J.estimate(s).dwell,45);assert.equal(J.estimate(s).travel,11);assert.ok(J.recommendations(s).every(r=>r.stopId!=='stop-coffee'));assert.equal(J.apply(s,prior),false);assert.equal(J.complete(s,'stop-coffee'),false);assert.equal(J.complete(s,'missing'),false);});

test('another itinerary supplies its own gate, clock, route costs and flight event identity',()=>{
 const s=J.create({
  flightId:'BA784',gate:'B36',gatePositions:{B36:18,C17B:24},position:0,deadline:50,
  catalog:{lounge:{name:'Lounge',minutes:5,minimum:3,position:7}},
  observations:{'queue:lounge':{value:2,expiresAt:20}}
 });
 assert.equal(J.estimate(s).arrival,18);
 assert.equal(J.add(s,'coffee'),false);
 assert.equal(J.add(s,'lounge'),true);
 assert.equal(J.estimate(s).arrival,25);
 assert.equal(J.observe(s,{id:'wrong',type:'gate',entityId:'flight-demo',at:1,value:'105',expiresAt:30}),false);
 assert.equal(J.observe(s,{id:'right',type:'gate',entityId:'BA784',at:1,value:'C17B',expiresAt:30}),true);
 assert.equal(J.estimate(s).arrival,31);
 assert.equal(J.observe(s,{id:'other',type:'gate',entityId:'BA784',at:2,value:'D9',expiresAt:30}),true);
 assert.equal(J.estimate(s).arrival,null);
 assert.deepEqual(J.recommendations(s),[]);
});
test('an empty route has no implicit airport, gate, stops, or deadline',()=>{
 const s=J.create();
 assert.equal(s.gate,null);
 assert.deepEqual(s.catalog,{});
 assert.equal(J.estimate(s).known,false);
 assert.equal(J.estimate(s).arrival,null);
});

const {readFileSync}=require('node:fs'),vm=require('node:vm');
async function browserView({host,directory,at='2027-02-22T10:55:00Z'}={}){
 const requests=[],items=new Map(),timers=[];
 let now=Date.parse(at);
 const node=selector=>{
  if(!items.has(selector))items.set(selector,{innerHTML:'',addEventListener(){}});
  return items.get(selector);
 };
 const document={addEventListener(){},querySelector:node,querySelectorAll(){return [];}};
 const sandbox=vm.createContext({document,location:{hostname:'localhost',search:'?presenter=1'},URLSearchParams,URL,AbortSignal,
  Date:class extends Date{static now(){return now;}},console,
  setInterval:fn=>{timers.push(fn);},sessionStorage:{getItem:()=>null,setItem:()=>{}},
  fetch:async path=>{requests.push(path);return {ok:true,headers:{get:()=> 'application/json'},json:async()=>{
   if(path.startsWith('/api/facilities'))return directory??{airportCode:new URLSearchParams(path.split('?')[1]).get('airport'),availability:'registryUnavailable',facilities:[]};
   return {canFit:true,spareMinutes:5};
  }};}
 });
 sandbox.window=sandbox;
 if(host!==undefined)sandbox.AIRBORDER_ITINERARY=host;
 for(const file of ['journey-engine.js','demo-journey.js','app.js'])
  vm.runInContext(readFileSync(require.resolve('./'+file),'utf8'),sandbox);
 await new Promise(resolve=>setImmediate(resolve));
 return {requests,screen:()=>node('#app').innerHTML,eval:js=>vm.runInContext(js,sandbox),advance:minutes=>{now+=minutes*60000;timers.forEach(fn=>fn());}};
}
const nonTokyoAirport={code:'LHR',name:'London Heathrow',zone:'GMT',country:'GB',timeZone:'Europe/London'};
const nonTokyoTrip={inbound:{id:'BA 203',from:{code:'BOS',name:'Boston'},to:nonTokyoAirport},onward:{id:'BA 578',from:nonTokyoAirport,to:{code:'FCO',name:'Rome Fiumicino'},departure:'12:30',arrival:'16:05',terminal:'5',gate:'B36',target:'11:55'}};
test('host browser itinerary renders its own gate and makes only its own airport query',async()=>{
 const demo=await browserView();
 assert.match(demo.screen(),/Tokyo Haneda/);
 const web=await browserView({host:nonTokyoTrip});
 assert.match(web.screen(),/London Heathrow/);
 assert.match(web.screen(),/Rome Fiumicino/);
 assert.match(web.screen(),/BA 578/);
 assert.match(web.screen(),/Last known gate B36/);
 assert.doesNotMatch(web.screen(),/Haneda|Narita|Gate 105/);
 assert.match(web.screen(),/Indoor route unavailable/);
 assert.doesNotMatch(web.screen(),/data-action="review-plan"/);
 assert.equal(web.eval('progressStorageKey'),null);
 assert.deepEqual(web.requests,['/api/facilities?airport=LHR']);
 web.eval("state.view='flights'; render();");
 assert.match(web.screen(),/Gate-arrival target · GMT/);
 assert.match(web.screen(),/11:55/);
});
test('host browser timing is local, limited to the matched airport and unavailable after expiry',async()=>{
 const timing={airportCode:'LHR',flightId:'BA 578',gate:'B36',walkMinutes:15,observedAt:'2027-02-22T10:54:00Z',expiresAt:'2027-02-22T11:00:00Z',arrivalTargetAt:'2027-02-22T11:55:00Z'};
 const web=await browserView({host:{...nonTokyoTrip,timing}});
 assert.match(web.screen(),/Supplied walking estimate: <strong>15 min/);
 assert.match(web.screen(),/arrival is <strong>11:10/);
 assert.match(web.screen(),/target/);
 assert.deepEqual(web.requests,['/api/facilities?airport=LHR']);
 web.eval("state.view='map'; render();");
 assert.match(web.screen(),/Indoor route unavailable/);
 assert.doesNotMatch(web.screen(),/route-map/);
 web.advance(6);
 web.eval("state.view='journey'; render();");
 assert.doesNotMatch(web.screen(),/Supplied walking estimate/);
 assert.match(web.screen(),/Indoor route unavailable/);
 const mismatch=await browserView({host:{...nonTokyoTrip,timing:{...timing,airportCode:'HND'}}});
 assert.doesNotMatch(mismatch.screen(),/Supplied walking estimate|Haneda/);
});

test('unknown host baggage stays unconfirmed and a foreign directory record is not rendered',async()=>{
 const web=await browserView({
  host:{...nonTokyoTrip,officialDirectoryHosts:['example.com']},
  directory:{airportCode:'LHR',availability:'officialRecordsIndexed',facilities:[
   {airportCode:'HND',name:'Foreign directory record',accessZone:'airside',officialRecordURL:'https://example.com/mismatched'},
   {airportCode:'LHR',name:'Matching directory record',accessZone:'airside',officialRecordURL:'https://example.com/matching'}
  ]}
 });
 assert.equal(web.eval('state.bags'),'unknown');
 assert.equal((await browserView()).eval('state.bags'),'through');
 web.eval("state.view='explore'; render();");
 assert.match(web.screen(),/Matching directory record/);
 assert.doesNotMatch(web.screen(),/Foreign directory record/);
});
