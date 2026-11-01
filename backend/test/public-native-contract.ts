import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';

const app = buildApp(loadConfig({ NODE_ENV: 'production' }), undefined, {
  fetcher: async () => Response.json({ base: 'USD', quote: 'EUR', date: '2026-10-16', rate: 0.89 }),
});
app.addHook('onRequest', async request => {
  assert.equal(request.headers.authorization, undefined, 'Public rates must not carry a token');
});
try {
  const address = await app.listen({ host: '127.0.0.1', port: 0 });
  await new Promise<void>((resolve, reject) => {
    const child = spawn('swift', ['test', '--package-path', '../apps/macos', '--filter', 'publicExchangeRateHTTPContract'], {
      stdio: 'inherit', env: { ...process.env, TIMEIT_PUBLIC_API_TEST_URL: address },
    });
    child.on('error', reject);
    child.on('exit', code => code === 0 ? resolve() : reject(new Error(`Swift public rate contract exited with ${code}`)));
  });
} finally { await app.close(); }
