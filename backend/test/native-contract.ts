import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import pg from 'pg';
import { buildApp } from '../src/app.js';
import { migrate } from '../src/db/database.js';

// Run the real Swift URLSession client against an isolated, disposable workspace.
if (!process.env.TEST_DATABASE_URL) throw new Error('TEST_DATABASE_URL is required.');
const databaseURL = process.env.TEST_DATABASE_URL;
const schema = 'native_' + randomUUID().replaceAll('-', '');
const admin = new pg.Pool({ connectionString: databaseURL });
await admin.query(`CREATE SCHEMA ${schema}`);
const pool = new pg.Pool({ connectionString: databaseURL, options: `-c search_path=${schema}` });
const app = buildApp({ host: '127.0.0.1', port: 0, databaseURL, developmentAuth: true }, pool);
try {
  await migrate(pool);
  const address = await app.listen({ host: '127.0.0.1', port: 0 });
  await new Promise<void>((resolve, reject) => {
    const child = spawn('swift', ['test', '--package-path', '../apps/macos', '--filter', 'nativeHTTPContract'], {
      stdio: 'inherit', env: { ...process.env, TIMEIT_API_TEST_URL: address },
    });
    child.on('error', reject);
    child.on('exit', code => code === 0 ? resolve() : reject(new Error(`Swift contract test exited with ${code}.`)));
  });
} finally {
  await app.close();
  await pool.end();
  await admin.query(`DROP SCHEMA ${schema} CASCADE`);
  await admin.end();
}
