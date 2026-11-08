import test from 'node:test';
import assert from 'node:assert/strict';
import { server } from '../../dev-server.mjs';

test('local HTTP server serves the frontend and routes API calls through the wrapper', async t => {
 await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
 t.after(() => new Promise(resolve => server.close(resolve)));
 const base = `http://127.0.0.1:${server.address().port}`;
 const page = await fetch(base + '/');
 assert.equal(page.status, 200);
 assert.match(page.headers.get('content-type'), /text\/html/);
 const health = await fetch(base + '/api/health');
 assert.equal(health.status, 200);
 assert.equal((await health.json()).service, 'airborder');
 const facilities = await fetch(base + '/api/facilities?airport=HND');
 assert.equal((await facilities.json()).facilities.length, 7);
 const calculation = await fetch(base + '/api/connection', { method:'POST', headers:{'content-type':'application/json'}, body:JSON.stringify({availableMinutes:100,walkingMinutes:10,activityMinutes:30,bufferMinutes:20}) });
 assert.equal((await calculation.json()).spareMinutes, 40);
 const invalid = await fetch(base + '/api/connection', { method:'POST', headers:{'content-type':'application/json'}, body:'{' });
 assert.equal(invalid.status, 400);
 const protectedRoute = await fetch(base + '/v1/provider-policies');
 assert.equal(protectedRoute.status, 503);
 assert.equal((await protectedRoute.json()).error, 'authentication_not_configured');
 const forbiddenOrigin = await fetch(base + '/api/health', {headers:{origin:'https://evil.example'}});
 assert.equal(forbiddenOrigin.status, 403);
});
