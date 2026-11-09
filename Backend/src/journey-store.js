// Authenticated, per-principal journey progress. Durable Object storage serializes
// and atomically commits the revision, snapshot and idempotency record.
const STEPS = Object.freeze({
  departure: { checkin: false, bagdrop: true, security: false, passport: true, gate: false, board: false },
  arrival: { landed: false, passport: true, bags: true, customs: true, connectivity: true, transport: false },
  transfer: { arrival: false, connection: false, bags: true, 'airport-transfer': false, security: true, passport: true, gate: false, board: false }
});
const EVENT_LIMIT = 1000;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const json = (body, status = 200) => new Response(JSON.stringify(body), {status, headers:{'content-type':'application/json; charset=utf-8','cache-control':'no-store','x-content-type-options':'nosniff'}});
const initial = () => ({revision:0, phase:'transfer', status:{arrival:{},departure:{},transfer:{}}});

export function validateJourneyEvent(data) {
  if (!data || typeof data !== 'object' || Array.isArray(data) ||
      Object.keys(data).sort().join(',') !== 'eventId,expectedOwner,expectedRevision,phase,step,value' ||
      typeof data.eventId !== 'string' || !UUID.test(data.eventId) ||
      typeof data.expectedOwner !== 'string' || !/^[a-f0-9]{64}$/.test(data.expectedOwner) ||
      !Number.isSafeInteger(data.expectedRevision) || data.expectedRevision < 0 ||
      !Object.hasOwn(STEPS, data.phase)) return null;
  if (data.step === null && data.value === null) return {...data, eventId:data.eventId.toLowerCase()};
  if (typeof data.step !== 'string' || !Object.hasOwn(STEPS[data.phase], data.step) ||
      !['done','pending','not-needed'].includes(data.value) ||
      (data.value === 'not-needed' && !STEPS[data.phase][data.step])) return null;
  return {...data, eventId:data.eventId.toLowerCase()};
}

export class JourneyStore {
  constructor(state) { this.storage = state.storage; }
  async fetch(request) {
    const owner = request.headers.get('x-journey-owner');
    if (!/^[a-f0-9]{64}$/.test(owner || '')) return json({error:'invalid_owner'}, 400);
    if (request.method === 'GET') {
      const state = await this.storage.get('state') || initial();
      return json({...state, owner});
    }
    if (request.method !== 'POST') return json({error:'method_not_allowed'}, 405);
    let body;
    try { body = await request.json(); } catch { return json({error:'invalid_json'}, 400); }
    const event = validateJourneyEvent(body);
    if (!event) return json({error:'invalid_journey_event'}, 400);
    if (event.expectedOwner !== owner) return json({error:'owner_mismatch'}, 403);
    const payload = JSON.stringify([event.expectedRevision,event.phase,event.step,event.value]);
    return this.storage.transaction(async tx => {
      const state = await tx.get('state') || initial();
      const existing = await tx.get(`event:${event.eventId}`);
      if (existing) return existing.payload === payload
        ? json({...existing.record, owner}) : json({error:'event_id_conflict'}, 409);
      if (state.revision !== event.expectedRevision)
        return json({error:'revision_conflict',record:{...state,owner}}, 409);
      const count = await tx.get('eventCount') || 0;
      if (count >= EVENT_LIMIT) return json({error:'journey_event_limit_reached'}, 507);
      const next = structuredClone(state);
      next.revision++;
      next.phase = event.phase;
      if (event.step !== null) {
        if (event.value === 'pending') delete next.status[event.phase][event.step];
        else next.status[event.phase][event.step] = event.value;
      }
      await tx.put('state', next);
      await tx.put(`event:${event.eventId}`, {payload,record:next});
      await tx.put('eventCount', count + 1);
      return json({...next,owner});
    });
  }
}
