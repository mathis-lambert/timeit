import Fastify, { type FastifyError } from 'fastify';
import { Type, type Static } from '@sinclair/typebox';
import type pg from 'pg';
import type { Config } from './config.js';
import { authenticator } from './auth/authenticate.js';
import { WorkspaceRepository } from './workspace/repository.js';
import { SyncSchema, validateWorkspace, type SyncRequest } from './workspace/schema.js';
import { ExchangeService } from './exchange/service.js';

declare module 'fastify' { interface FastifyRequest { ownerID: string } }

const ExchangeQuery = Type.Object({
  base: Type.String({ pattern: '^[A-Z]{3}$' }),
  quote: Type.String({ pattern: '^[A-Z]{3}$' }),
  date: Type.String({ format: 'date' }),
}, { additionalProperties: false });

export function buildApp(config: Config, pool: pg.Pool, options: { logger?: boolean; fetcher?: typeof fetch } = {}) {
  const app = Fastify({ logger: options.logger ?? false, bodyLimit: 10 * 1024 * 1024 });
  const workspace = new WorkspaceRepository(pool);
  const exchange = new ExchangeService(pool, options.fetcher);
  const authenticate = authenticator(config);
  app.get('/health', async () => { await pool.query('SELECT 1'); return { status: 'ok' }; });
  app.get('/v1/config', async () => ({ developmentAuth: config.developmentAuth, issuer: config.issuer ?? null, clientID: config.clientID ?? null }));
  app.register(async protectedRoutes => {
    protectedRoutes.decorateRequest('ownerID', '');
    protectedRoutes.addHook('preHandler', async (request, reply) => {
      try { request.ownerID = await authenticate(request); }
      catch { return reply.code(401).send({ error: 'Unauthorized' }); }
    });
    protectedRoutes.get('/v1/me', async request => ({ id: request.ownerID }));
    protectedRoutes.get('/v1/workspace', async request => workspace.read(request.ownerID));
    protectedRoutes.put<{ Body: SyncRequest }>('/v1/workspace', { schema: { body: SyncSchema } }, async (request, reply) => {
      const invalid = validateWorkspace(request.body.document);
      if (invalid) return reply.code(400).send({ error: invalid });
      const result = await workspace.save(request.ownerID, request.body);
      if (result.status === 'conflict') return reply.code(409).send({ error: 'Workspace changed on another device.', revision: result.revision });
      if (result.status === 'reused-id') return reply.code(422).send({ error: 'Mutation identifier already used for different content.' });
      return { revision: result.revision };
    });
    protectedRoutes.get<{ Querystring: Static<typeof ExchangeQuery> }>('/v1/exchange-rate', { schema: { querystring: ExchangeQuery } }, async (request, reply) => {
      const { base, quote, date } = request.query;
      if (date > new Date().toISOString().slice(0, 10)) return reply.code(400).send({ error: 'Future rates are unavailable.' });
      try { return await exchange.get(base, quote, date); }
      catch (error) { request.log.warn({ error: error instanceof Error ? error.message : 'provider failure' }, 'Exchange rate unavailable'); return reply.code(502).send({ error: 'Exchange rate unavailable. Original amounts are preserved.' }); }
    });
  });
  app.setErrorHandler<FastifyError>((error, request, reply) => {
    if (error.validation) return reply.code(400).send({ error: 'Invalid request.', details: error.validation.map(item => ({ field: item.instancePath, message: item.message })) });
    if (error.statusCode && error.statusCode < 500) return reply.code(error.statusCode).send({ error: error.message });
    request.log.error({ err: error }, 'Request failed');
    return reply.code(500).send({ error: 'Internal server error.' });
  });
  return app;
}
