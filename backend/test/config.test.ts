import assert from 'node:assert/strict';
import test from 'node:test';
import { loadConfig } from '../src/config.js';

test('development authentication cannot be exposed or enabled in production', () => {
  const env = { DATABASE_URL: 'postgres://unused', DEV_AUTH: 'true' };
  assert.equal(loadConfig(env).developmentAuth, true);
  assert.throws(() => loadConfig({ ...env, HOST: '0.0.0.0' }), /loopback/);
  assert.throws(() => loadConfig({ ...env, NODE_ENV: 'production' }), /loopback/);
});

test('production authentication requires an issuer, audience and public client', () => {
  assert.throws(() => loadConfig({ DATABASE_URL: 'postgres://unused' }), /OIDC/);
  assert.throws(() => loadConfig({ DATABASE_URL: 'postgres://unused', OIDC_ISSUER: 'http://insecure', OIDC_AUDIENCE: 'timeit', OIDC_CLIENT_ID: 'native' }), /HTTPS/);
});
