import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import test from 'node:test';
import Fastify from 'fastify';
import pg from 'pg';
import { exportJWK, generateKeyPair, SignJWT } from 'jose';
import { buildApp } from '../src/app.js';
import { migrate } from '../src/db/database.js';
import type { Workspace } from '../src/workspace/schema.js';

test('workspace, authentication and FX integration against PostgreSQL', { skip: !process.env.TEST_DATABASE_URL }, async t => {
  const admin = new pg.Pool({ connectionString: process.env.TEST_DATABASE_URL });
  const schema = 'test_' + randomUUID().replaceAll('-', '');
  await admin.query(`CREATE SCHEMA ${schema}`);
  const pool = new pg.Pool({ connectionString: process.env.TEST_DATABASE_URL, options: `-c search_path=${schema}`, max: 4 });
  await migrate(pool);
  const { publicKey, privateKey } = await generateKeyPair('RS256');
  const jwk = { ...await exportJWK(publicKey), kid: 'test-key', alg: 'RS256', use: 'sig' };
  const identityServer = Fastify();
  identityServer.get('/realm/protocol/openid-connect/certs', async () => ({ keys: [jwk] }));
  const host = await identityServer.listen({ host: '127.0.0.1', port: 0 });
  const issuer = host + '/realm';
  let providerCalls = 0;
  const app = buildApp({ host: '127.0.0.1', port: 0, databaseURL: process.env.TEST_DATABASE_URL!, developmentAuth: false, issuer, audience: 'timeit-api', clientID: 'timeit-macos' }, pool, {
    fetcher: async input => {
      providerCalls++;
      const url = String(input);
      if (url.includes('/ZZZ/')) return new Response('{}', { status: 404 });
      return Response.json({ base: 'USD', quote: 'EUR', date: '2026-10-16', rate: 0.89 });
    },
  });
  const token = async (subject: string, audience = 'timeit-api') => new SignJWT({}).setProtectedHeader({ alg: 'RS256', kid: 'test-key' }).setIssuer(issuer).setAudience(audience).setSubject(subject).setIssuedAt().setExpirationTime('5m').sign(privateKey);
  const alice = { authorization: 'Bearer ' + await token('alice') };
  const bob = { authorization: 'Bearer ' + await token('bob') };
  const clientID = randomUUID(); const projectID = randomUUID();
  const document: Workspace = {
    schemaVersion: 1,
    profile: { name: 'Alice', currency: 'EUR', weeklyGoal: 35, timezone: 'Europe/Paris' },
    clients: [{ id: clientID, name: 'Client', color: 'coral' }],
    projects: [{ id: projectID, clientID, name: 'Project', color: 'coral', currency: 'USD', hourlyRate: '100', billable: true, archived: false }],
    taxPolicies: [{ id: randomUUID(), effectiveFrom: '2020-01-01T00:00:00Z', contributions: '25', incomeTax: '5' }],
    entries: [{ id: randomUUID(), projectID, title: 'Work', start: '2026-10-16T08:00:00Z', end: '2026-10-16T10:00:00Z', currency: 'USD', hourlyRate: '100', billable: true, contributions: '25', incomeTax: '5' }],
  };
  try {
    await t.test('JWT verification rejects missing credentials and wrong audiences', async () => {
      assert.equal((await app.inject({ url: '/v1/workspace' })).statusCode, 401);
      const wrong = await token('alice', 'another-service');
      assert.equal((await app.inject({ url: '/v1/workspace', headers: { authorization: 'Bearer ' + wrong } })).statusCode, 401);
      assert.equal((await app.inject({ url: '/v1/me', headers: alice })).json().id, 'alice');
    });
    const mutationID = randomUUID();
    await t.test('first upload persists and isolates accounts', async () => {
      const result = await app.inject({ method: 'PUT', url: '/v1/workspace', headers: alice, payload: { baseRevision: 0, mutationID, document } });
      assert.equal(result.statusCode, 200, result.body); assert.equal(result.json().revision, 1);
      assert.deepEqual((await app.inject({ url: '/v1/workspace', headers: alice })).json().document, document);
      assert.deepEqual((await app.inject({ url: '/v1/workspace', headers: bob })).json(), { revision: 0, document: null });
    });
    await t.test('a lost-response retry is idempotent; identifier reuse cannot hide a different write', async () => {
      const retry = await app.inject({ method: 'PUT', url: '/v1/workspace', headers: alice, payload: { baseRevision: 0, mutationID, document } });
      assert.equal(retry.json().revision, 1);
      const changed = structuredClone(document); changed.profile.name = 'Different';
      const reused = await app.inject({ method: 'PUT', url: '/v1/workspace', headers: alice, payload: { baseRevision: 1, mutationID, document: changed } });
      assert.equal(reused.statusCode, 422);
    });
    await t.test('concurrent writes cannot silently overwrite each other', async () => {
      const results = await Promise.all(['one', 'two'].map(name => app.inject({ method: 'PUT', url: '/v1/workspace', headers: alice, payload: { baseRevision: 1, mutationID: randomUUID(), document: { ...document, profile: { ...document.profile, name } } } })));
      assert.deepEqual(results.map(result => result.statusCode).sort(), [200, 409]);
      assert.equal((await app.inject({ url: '/v1/workspace', headers: alice })).json().revision, 2);
    });
    await t.test('invalid references, duplicate timers, invalid dates and percentages are rejected', async () => {
      const invalids = [
        { ...document, projects: [{ ...document.projects[0]!, clientID: randomUUID() }] },
        { ...document, entries: [{ ...document.entries[0]!, end: null }, { ...document.entries[0]!, id: randomUUID(), end: null }] },
        { ...document, entries: [{ ...document.entries[0]!, end: '2026-10-15T00:00:00Z' }] },
        { ...document, taxPolicies: [{ ...document.taxPolicies[0]!, contributions: '90', incomeTax: '20' }] },
        { ...document, profile: { ...document.profile, timezone: 'not-a-zone' } },
      ];
      for (const invalid of invalids) {
        const response = await app.inject({ method: 'PUT', url: '/v1/workspace', headers: alice, payload: { baseRevision: 2, mutationID: randomUUID(), document: invalid } });
        assert.equal(response.statusCode, 400, response.body);
      }
    });
    await t.test('FX preserves the actual observed date and freezes the cached rate', async () => {
      const path = '/v1/exchange-rate?base=USD&quote=EUR&date=2026-10-18';
      const first = await app.inject({ url: path, headers: alice });
      assert.equal(first.statusCode, 200, first.body);
      assert.equal(first.json().observedDate, '2026-10-16'); assert.equal(first.json().rate, '0.89');
      const cached = await app.inject({ url: path, headers: bob });
      assert.deepEqual(cached.json(), first.json()); assert.equal(providerCalls, 1);
      const unavailable = await app.inject({ url: '/v1/exchange-rate?base=ZZZ&quote=EUR&date=2026-10-18', headers: alice });
      assert.equal(unavailable.statusCode, 502);
      assert.equal((await app.inject({ url: '/v1/exchange-rate?base=EUR&quote=EUR&date=2026-10-18', headers: alice })).json().rate, '1');
    });
  } finally {
    await app.close(); await identityServer.close(); await pool.end();
    await admin.query(`DROP SCHEMA ${schema} CASCADE`); await admin.end();
  }
});
