export interface Config {
  cloudEnabled: boolean;
  host: string;
  port: number;
  databaseURL: string;
  developmentAuth: boolean;
  issuer?: string;
  audience?: string;
  clientID?: string;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const cloudEnabled = env.CLOUD_ENABLED === 'true';
  if (cloudEnabled && env.NODE_ENV === 'production') {
    throw new Error('Cloud is not available in production yet.');
  }
  const host = env.HOST ?? '127.0.0.1';
  const developmentAuth = env.DEV_AUTH === 'true';
  if (developmentAuth && (env.NODE_ENV === 'production' || !['127.0.0.1', '::1'].includes(host))) {
    throw new Error('DEV_AUTH is only allowed on loopback outside production.');
  }
  if (cloudEnabled && !developmentAuth && (!env.OIDC_ISSUER || !env.OIDC_AUDIENCE || !env.OIDC_CLIENT_ID)) {
    throw new Error('Configure OIDC_ISSUER, OIDC_AUDIENCE and OIDC_CLIENT_ID, or enable local DEV_AUTH.');
  }
  if (env.OIDC_ISSUER && !env.OIDC_ISSUER.startsWith('https://')) {
    throw new Error('OIDC_ISSUER must use HTTPS.');
  }
  if (cloudEnabled && !env.DATABASE_URL) throw new Error('DATABASE_URL is required.');
  const port = Number(env.PORT ?? 4318);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid PORT.');
  return {
    cloudEnabled, host, port, databaseURL: env.DATABASE_URL ?? '', developmentAuth,
    issuer: env.OIDC_ISSUER, audience: env.OIDC_AUDIENCE, clientID: env.OIDC_CLIENT_ID,
  };
}
