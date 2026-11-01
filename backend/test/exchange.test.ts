import assert from 'node:assert/strict';
import test from 'node:test';
import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { ExchangeService, ExchangeCapacityError } from '../src/exchange/service.js';

const path = '/v1/exchange-rate?base=USD&quote=EUR&date=2026-10-18';
const observation = { base: 'USD', quote: 'EUR', date: '2026-10-16', rate: 0.89 };

test('public rates work without authentication or PostgreSQL and preserve weekend observations', async () => {
  let calls = 0;
  const app = buildApp(loadConfig({ NODE_ENV: 'production' }), undefined, {
    fetcher: async url => {
      assert.equal(url, 'https://api.frankfurter.dev/v2/rate/USD/EUR?date=2026-10-18');
      calls++;
      return Response.json(observation);
    },
  });
  try {
    const first = await app.inject(path);
    assert.equal(first.statusCode, 200);
    assert.deepEqual(first.json(), {
      base: 'USD', quote: 'EUR', requestedDate: '2026-10-18', observedDate: '2026-10-16', rate: '0.89', source: 'Frankfurter',
    });
    assert.equal((await app.inject(path)).statusCode, 200);
    assert.equal(calls, 1);
    assert.equal((await app.inject('/v1/workspace')).statusCode, 501);
    for (const query of ['base=USD&quote=EUR&date=2099-01-01', 'base=../&quote=EUR&date=2026-10-18', 'base=USD&quote=EUR&date=2026-02-30']) {
      assert.equal((await app.inject('/v1/exchange-rate?' + query)).statusCode, 400);
    }
    assert.equal(calls, 1);
  } finally { await app.close(); }
});

test('provider failures and invalid observations are never cached as rates', async () => {
  for (const data of [{ ...observation, date: '2026-02-30' }, { ...observation, date: '2026-10-19' }, { ...observation, quote: 'GBP' }, { ...observation, rate: -1 }]) {
    let calls = 0;
    const app = buildApp(loadConfig({ NODE_ENV: 'production' }), undefined, {
      fetcher: async () => { calls++; return Response.json(calls === 1 ? data : observation); },
    });
    try {
      assert.equal((await app.inject(path)).statusCode, 502);
      assert.equal((await app.inject(path)).statusCode, 200);
    } finally { await app.close(); }
  }
});

test('simultaneous identical requests share one provider request', async () => {
  let calls = 0;
  const service = new ExchangeService(undefined, async () => {
    calls++;
    await new Promise(resolve => setTimeout(resolve, 10));
    return Response.json(observation);
  });
  const rates = await Promise.all(Array.from({ length: 20 }, () => service.get('USD', 'EUR', '2026-10-18')));
  assert.equal(calls, 1);
  assert.ok(rates.every(rate => rate.rate === '0.89'));
});

test('bounds simultaneous provider requests and releases capacity after failure', async () => {
  let release!: () => void;
  const gate = new Promise<void>(resolve => { release = resolve; });
  const service = new ExchangeService(undefined, async () => { await gate; throw new Error('offline'); });
  const pending = Array.from({ length: 16 }, (_, index) => service.get('USD', 'EUR', `2026-10-${String(index + 1).padStart(2, '0')}`));
  const settled = Promise.allSettled(pending);
  await assert.rejects(service.get('GBP', 'EUR', '2026-10-18'), ExchangeCapacityError);
  release();
  await settled;
  await assert.rejects(service.get('GBP', 'EUR', '2026-10-18'), /offline/);
});
