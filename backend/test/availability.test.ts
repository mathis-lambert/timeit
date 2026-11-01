import assert from 'node:assert/strict';
import test from 'node:test';
import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';

test('production serves health but gates all cloud routes without a database or identity provider', async () => {
  const app = buildApp(loadConfig({ NODE_ENV: 'production' }));
  try {
    const health = await app.inject('/health');
    assert.equal(health.statusCode, 200);
    assert.deepEqual(health.json(), { status: 'ok', cloudAvailable: false });
    for (const method of ['GET', 'PUT', 'POST', 'DELETE'] as const) {
      for (const url of ['/v1/config', '/v1/me', '/v1/workspace']) {
        const response = await app.inject({ method, url });
        assert.equal(response.statusCode, 501);
        assert.equal(response.json().code, 'CLOUD_NOT_AVAILABLE');
      }
    }
  } finally {
    await app.close();
  }
});

test('cloud cannot be enabled by a production environment variable', () => {
  assert.throws(() => loadConfig({ NODE_ENV: 'production', CLOUD_ENABLED: 'true' }), /not available/);
});
