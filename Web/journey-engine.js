/* Synthetic route values are demonstration fixtures, not surveyed airport guidance. */
(function(root,factory){const api=factory();if(typeof module==='object')module.exports=api;else root.AirBorderJourney=api;})(globalThis,function(){
'use strict';
const copy=v=>JSON.parse(JSON.stringify(v));
const own=(records,id)=>typeof id==='string'&&Object.hasOwn(records,id)?records[id]:undefined;
const facility=(s,id)=>own(s.catalog||{},id);
function create({flightId=null,gate=null,gatePositions={},position=null,deadline=null,catalog={},observations={},transfers=[]}={}){
 return {revision:0,dataRevision:0,now:0,deadline,flightId,gate,gatePositions:copy(gatePositions),catalog:copy(catalog),position,stops:[],observations:copy(observations),transfers:[...transfers],seen:[],undo:null};
}
function add(s,id){const f=facility(s,id);if(!f||!Number.isFinite(f.minutes)||f.minutes<0||s.stops.some(x=>x.facilityId===id))return false;s.stops.push({id:'stop-'+id,facilityId:id,minutes:f.minutes,required:false,status:'pending'});s.revision++;return true;}
function remove(s,id){const i=s.stops.findIndex(x=>x.id===id);if(i<0)return false;s.stops.splice(i,1);s.revision++;return true;}
function move(s,id,offset){const i=s.stops.findIndex(x=>x.id===id),j=i+offset;if(i<0||j<0||j>=s.stops.length)return false;[s.stops[i],s.stops[j]]=[s.stops[j],s.stops[i]];s.revision++;return true;}
function complete(s,id){const stop=s.stops.find(x=>x.id===id);if(!stop||stop.status==='completed'||!Number.isFinite(facility(s,stop.facilityId)?.position))return false;stop.status='completed';s.position=facility(s,stop.facilityId).position;s.revision++;return true;}
function observe(s,e){
 if(!e||!e.id||!Number.isFinite(e.at)||s.seen.includes(e.id)||!['queue','gate','weather','transfer','flight-delay'].includes(e.type))return false;
 if(['gate','flight-delay'].includes(e.type)&&(!s.flightId||e.entityId!==s.flightId))return false;
 if(e.type!=='flight-delay'&&!Number.isFinite(e.expiresAt))return false;
 if(e.type==='gate'&&(typeof e.value!=='string'||!e.value.trim()))return false;
 if(['queue','transfer'].includes(e.type)&&e.value!==null&&(!Number.isFinite(e.value)||e.value<0))return false;
 const key=e.type+':'+e.entityId,old=s.observations[key];
 if(old&&e.at<=old.at)return false;
 s.seen.push(e.id);s.observations[key]=copy(e);if(e.type==='gate')s.gate=e.value;s.dataRevision++;return true;
}
function estimate(s,stops=s.stops){
 let travel=0,dwell=0,queue=0,pos=s.position;
 const gatePosition=own(s.gatePositions||{},s.gate),gateObservation=s.flightId?s.observations['gate:'+s.flightId]:null;
 let known=Number.isFinite(s.now)&&Number.isFinite(s.deadline)&&Number.isFinite(pos)&&Number.isFinite(gatePosition)&&(!gateObservation||gateObservation.expiresAt>s.now);
 for(const stop of stops.filter(x=>x.status!=='completed')){
  const f=facility(s,stop.facilityId);
  if(!Number.isFinite(f?.position)||!Number.isFinite(pos))known=false;else travel+=Math.abs(f.position-pos);
  pos=f?.position;
  if(!Number.isFinite(stop.minutes)||stop.minutes<0)known=false;else dwell+=stop.minutes;
  const o=s.observations['queue:'+stop.facilityId];
  if(!o||!Number.isFinite(o.expiresAt)||o.expiresAt<=s.now||!Number.isFinite(o.value)||o.value<0)known=false;else queue+=o.value;
 }
 if(Number.isFinite(pos)&&Number.isFinite(gatePosition))travel+=Math.abs(gatePosition-pos);
 for(const id of s.transfers){
  const o=s.observations['transfer:'+id];
  if(!o||!Number.isFinite(o.expiresAt)||o.expiresAt<=s.now||!Number.isFinite(o.value)||o.value<0)known=false;else travel+=o.value;
 }
 const arrival=s.now+travel+dwell+queue;
 known=known&&Number.isFinite(arrival);
 return {known,travel,dwell,queue,arrival:known?arrival:null,deadline:s.deadline};
}
function recommendations(s){const before=estimate(s),result=[];for(const stop of s.stops){if(stop.required||stop.status==='completed')continue;const weather=s.observations['weather:'+stop.facilityId];const affected=facility(s,stop.facilityId)?.outdoor&&weather&&weather.expiresAt>s.now&&weather.value==='rain';if(!before.known||(!affected&&before.arrival<=s.deadline))continue;const after=estimate(s,s.stops.filter(x=>x.id!==stop.id));if(!after.known||after.arrival>=before.arrival)continue;result.push({id:`${s.revision}:${s.dataRevision}:${s.now}:${stop.id}`,revision:s.revision,dataRevision:s.dataRevision,now:s.now,stopId:stop.id,before:before.arrival,after:after.arrival,saved:before.arrival-after.arrival,reason:affected?'rain':'time',fits:after.arrival<=s.deadline});}return result.sort((a,b)=>Number(b.fits)-Number(a.fits)||b.saved-a.saved);}
function apply(s,r){if(!r||r.revision!==s.revision||r.dataRevision!==s.dataRevision||r.now!==s.now)return false;const valid=recommendations(s).find(x=>x.id===r.id);if(!valid)return false;const previous=copy(s.stops);remove(s,valid.stopId);s.undo={stops:previous,revision:s.revision};return true;}
function undo(s){if(!s.undo||s.undo.revision!==s.revision)return false;s.stops=s.undo.stops;s.undo=null;s.revision++;return true;}
return {create,facility,add,remove,move,complete,observe,estimate,recommendations,apply,undo};
});
