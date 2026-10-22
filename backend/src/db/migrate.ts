import { loadConfig } from '../config.js';
import { createPool, migrate } from './database.js';

const pool = createPool(loadConfig().databaseURL);
try { await migrate(pool); } finally { await pool.end(); }
