import { createRemoteJWKSet, jwtVerify } from 'jose';
import type { FastifyRequest } from 'fastify';
import type { Config } from '../config.js';

export function authenticator(config: Config) {
  const keys = config.issuer ? createRemoteJWKSet(new URL(`${config.issuer}/protocol/openid-connect/certs`)) : undefined;
  return async (request: FastifyRequest): Promise<string> => {
    const token = request.headers.authorization?.match(/^Bearer (.+)$/)?.[1];
    if (config.developmentAuth && token === 'local-development-token') return 'local-development';
    if (!token || !keys || !config.issuer) throw new Error('Unauthorized');
    const { payload } = await jwtVerify(token, keys, { issuer: config.issuer, audience: config.audience, algorithms: ['RS256', 'ES256'] });
    if (!payload.sub) throw new Error('Unauthorized');
    return payload.sub;
  };
}
