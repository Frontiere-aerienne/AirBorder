// Local development and browser-test server. Never use this in production.
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { dirname, extname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import worker from './backend/index.mjs';

const root = dirname(fileURLToPath(import.meta.url));
const port = 4173;
const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml' };
// This in-memory limiter exists only for local testing; deployed environments
// must supply their own durable rate limiter binding.
const buckets = new Map();
const env = {
  DEPLOYMENT_ENVIRONMENT: 'production',
  REQUIRE_RATE_LIMITER: 'true',
  ALLOWED_ORIGINS: `http://localhost:${port},http://127.0.0.1:${port}`,
  API_RATE_LIMITER: { async limit({ key }) {
    const now = Date.now();
    const current = buckets.get(key);
    const bucket = !current || now - current.start >= 60_000 ? { start: now, count: 0 } : current;
    bucket.count++;
    buckets.set(key, bucket);
    return { success: bucket.count <= 1000 };
  } }
};

export const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://localhost:${port}`);
    if (url.pathname.startsWith('/api/') || url.pathname.startsWith('/v1/') || url.pathname === '/health') {
      const init = { method: req.method, headers: req.headers };
      if (!['GET', 'HEAD'].includes(req.method)) { init.body = req; init.duplex = 'half'; }
      const response = await worker.fetch(new Request(url, init), env);
      res.writeHead(response.status, Object.fromEntries(response.headers));
      if (response.body) for await (const chunk of response.body) res.write(chunk);
      res.end();
      return;
    }
    if (!['GET', 'HEAD'].includes(req.method)) { res.writeHead(405, { allow: 'GET, HEAD' }); res.end(); return; }
    const path = resolve(root, '.' + (url.pathname === '/' ? '/index.html' : decodeURIComponent(url.pathname)));
    if (!path.startsWith(root + sep) || path.includes(`${sep}backend${sep}`)) { res.writeHead(404); res.end(); return; }
    const data = await readFile(path);
    res.writeHead(200, { 'content-type': types[extname(path)] || 'application/octet-stream', 'x-content-type-options': 'nosniff' });
    res.end(req.method === 'HEAD' ? undefined : data);
  } catch {
    if (!res.headersSent) res.writeHead(404);
    res.end();
  }
});

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  server.listen(port, '127.0.0.1', () => console.log(`Local server listening on http://127.0.0.1:${port}`));
}
