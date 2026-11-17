/* Explicit Tokyo test data. Never applied to a host-supplied itinerary. */
(function(root,factory){const api=factory(typeof module==='object'?require('./journey-engine.js'):root.AirBorderJourney);if(typeof module==='object')module.exports=api;else root.AirBorderDemo=api;})(globalThis,function(J){
'use strict';
const catalog={rest:{name:'Quiet time near your gate',minutes:45,minimum:10,position:4},coffee:{name:'A coffee before boarding',minutes:25,minimum:5,position:7},work:{name:'A little time to focus',minutes:40,minimum:10,position:9},deck:{name:'Observation deck',minutes:20,minimum:5,position:-8,outdoor:true}};

const gatePositions={'105':12,'108A':16};
const flightId='flight-demo';
function create(){return J.create({flightId,gate:'105',gatePositions,deadline:55,position:0,catalog,
 observations:Object.fromEntries(Object.keys(catalog).map(id=>['queue:'+id,{id:'baseline-'+id,type:'queue',entityId:id,at:-1,value:0,expiresAt:1000000,source:'synthetic-baseline'}]))});}
const add=J.add,observe=J.observe;
const fixtures={transferUsed:{name:'Used shuttle delayed',stops:['coffee'],transfers:['shuttle-t3-t2'],deadline:60,events:[{id:'t1',at:1,type:'transfer',entityId:'shuttle-t3-t2',value:30,expiresAt:60}]},transferUnused:{name:'Unused shuttle delayed',stops:['coffee'],deadline:60,events:[{id:'t1',at:1,type:'transfer',entityId:'shuttle-t3-t2',value:30,expiresAt:60}]},queue:{name:'Café queue grows',stops:['coffee','rest'],deadline:70,events:[{id:'q1',at:1,type:'queue',entityId:'coffee',value:20,expiresAt:15}]},gate:{name:'Gate changes during route',stops:['coffee','work'],deadline:80,events:[{id:'g1',at:1,type:'gate',entityId:'flight-demo',value:'108A',expiresAt:60}]},indoorRain:{name:'Rain — indoor plan',stops:['coffee'],deadline:80,events:[{id:'w1',at:1,type:'weather',entityId:'deck',value:'rain',expiresAt:60}]},deckRain:{name:'Rain — selected deck',stops:['deck','coffee'],deadline:80,events:[{id:'w1',at:1,type:'weather',entityId:'deck',value:'rain',expiresAt:60}]},unknown:{name:'Café queue unknown',stops:['coffee'],deadline:30,events:[{id:'u1',at:1,type:'queue',entityId:'coffee',value:null,expiresAt:60}]}};
function driver(id){const fixture=fixtures[id]||fixtures.queue;let state,cursor;function reset(){state=create();state.deadline=fixture.deadline;state.transfers=fixture.transfers||[];for(const id of state.transfers)state.observations['transfer:'+id]={id:'baseline-'+id,at:-1,type:'transfer',entityId:id,value:10,expiresAt:1000000};fixture.stops.forEach(id=>add(state,id));cursor=0;return state;}reset();return {get state(){return state;},reset,step(){const event=fixture.events[cursor++];if(event){state.now=event.at;observe(state,event);}return state;},advance(minutes){state.now+=minutes;state.dataRevision++;return state;}};}

const airports={
 BKK:{code:'BKK',name:'Bangkok',city:'Bangkok',zone:'ICT',timeZone:'Asia/Bangkok',country:'TH'},
 HND:{code:'HND',name:'Tokyo Haneda',city:'Tokyo',zone:'JST',timeZone:'Asia/Tokyo',country:'JP'},
 NRT:{code:'NRT',name:'Tokyo Narita',city:'Tokyo',zone:'JST',timeZone:'Asia/Tokyo',country:'JP'},
 LAX:{code:'LAX',name:'Los Angeles',city:'Los Angeles',zone:'PDT',timeZone:'America/Los_Angeles',country:'US'}
};
const {BKK,HND,NRT,LAX}=airports;
const inbound={id:'TG 660',airline:'Thai Airways',from:BKK,to:HND,departure:'05:15',arrival:'11:15',terminal:'3',gate:'146'};
const onward={id:'NH 106',airline:'ANA',logo:'assets/figma/imgLogo.png',from:HND,to:LAX,departure:'18:00',arrival:'11:45',terminal:'3'};
const interAirportOnward={...onward,id:'NH 6',from:NRT,departure:'21:00',arrival:'15:00',terminal:'1',target:'20:20',confirmationPlace:'Narita'};
const history=[['Tokyo Haneda','HND','Bangkok → Tokyo → Los Angeles'],['Singapore Changi','SIN','Sydney → Singapore → London'],['Doha Hamad','DOH','Delhi → Doha → Paris'],['London Heathrow','LHR','Boston → London → Rome']];
const facilities=[
 {id:'rest',name:'Quiet time near your gate',category:'rest',symbol:'rest',desc:'Take a seat in the departure area while keeping your onward gate close by.'},
 {id:'coffee',name:'A coffee before boarding',category:'food',symbol:'coffee',desc:'Pick up a coffee on your way to the departure gate.'},
 {id:'work',name:'A little time to focus',category:'work',symbol:'rest',desc:'Find a seat for a short work session. Outlet and seating availability need checking on arrival.'}
];
const itinerary={id:'tokyo-demo',subtitle:'Your Haneda connection, gate details, and next steps.',inbound,onward,clockEpoch:Date.UTC(2026,10,7,7,30),date:'15 October 2026',fullDate:'Thursday, 15 October 2026',shortDate:'15 Oct',
 initialGate:'105',changedGate:'108A',airportRegistry:HND,officialDirectoryHosts:['tokyo-haneda.com','www.shopping-sumitomo-rd.com'],facilities,history,routeOrigin:'International Gates',
 visual:{gate:'105',floor:'T3, 3F',ranges:['105–109','108–149']}};
return {create,fixtures,driver,itinerary,interAirportOnward};
});
