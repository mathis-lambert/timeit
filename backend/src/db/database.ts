import pg from 'pg';

export function createPool(connectionString: string) {
  return new pg.Pool({ connectionString, max: 5, connectionTimeoutMillis: 5_000 });
}

export async function migrate(pool: pg.Pool) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SELECT pg_advisory_xact_lock(hashtext('timeit-migrations'))");
    await client.query(`
      CREATE TABLE IF NOT EXISTS workspaces (
        owner_id text PRIMARY KEY,
        revision integer NOT NULL DEFAULT 0 CHECK (revision >= 0),
        document jsonb NOT NULL,
        updated_at timestamptz NOT NULL DEFAULT now()
      );
      CREATE TABLE IF NOT EXISTS sync_receipts (
        owner_id text NOT NULL,
        mutation_id uuid NOT NULL,
        request_hash text NOT NULL,
        revision integer NOT NULL,
        created_at timestamptz NOT NULL DEFAULT now(),
        PRIMARY KEY (owner_id, mutation_id)
      );
      CREATE TABLE IF NOT EXISTS exchange_rates (
        base text NOT NULL,
        quote text NOT NULL,
        requested_date date NOT NULL,
        observed_date date NOT NULL,
        rate numeric NOT NULL CHECK (rate > 0),
        source text NOT NULL,
        fetched_at timestamptz NOT NULL DEFAULT now(),
        PRIMARY KEY (base, quote, requested_date)
      );
    `);
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}
