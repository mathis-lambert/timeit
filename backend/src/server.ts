import { buildApp } from './app.js';
import { loadConfig } from './config.js';
import { createPool, migrate } from './db/database.js';

const config = loadConfig();
const pool = createPool(config.databaseURL);
await migrate(pool);
const app = buildApp(config, pool, { logger: true });
app.addHook('onClose', async () => pool.end());
for (const signal of ['SIGINT', 'SIGTERM'] as const) process.once(signal, () => { void app.close(); });
try { await app.listen({ host: config.host, port: config.port }); }
catch (error) { app.log.error(error); await app.close(); process.exitCode = 1; }
