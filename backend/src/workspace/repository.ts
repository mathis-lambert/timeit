import { createHash } from 'node:crypto';
import type pg from 'pg';
import type { SyncRequest, Workspace } from './schema.js';

export class WorkspaceRepository {
  constructor(private readonly pool: pg.Pool) {}

  async read(owner: string): Promise<{ revision: number; document: Workspace | null }> {
    const result = await this.pool.query('SELECT revision, document FROM workspaces WHERE owner_id=$1', [owner]);
    return result.rows[0] ?? { revision: 0, document: null };
  }

  async save(owner: string, request: SyncRequest) {
    const client = await this.pool.connect();
    const hash = createHash('sha256').update(JSON.stringify(request.document)).digest('hex');
    try {
      await client.query('BEGIN');
      // A transaction-scoped lock also serializes the first write, before a row exists.
      await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`timeit:${owner}`]);
      const receipt = await client.query('SELECT request_hash, revision FROM sync_receipts WHERE owner_id=$1 AND mutation_id=$2', [owner, request.mutationID]);
      if (receipt.rows[0]) {
        await client.query('COMMIT');
        return receipt.rows[0].request_hash === hash
          ? { status: 'saved' as const, revision: receipt.rows[0].revision as number }
          : { status: 'reused-id' as const };
      }
      const current = await client.query('SELECT revision FROM workspaces WHERE owner_id=$1', [owner]);
      const revision = (current.rows[0]?.revision as number | undefined) ?? 0;
      if (revision !== request.baseRevision) {
        await client.query('COMMIT');
        return { status: 'conflict' as const, revision };
      }
      const next = revision + 1;
      await client.query(`INSERT INTO workspaces(owner_id, revision, document) VALUES($1,$2,$3)
        ON CONFLICT(owner_id) DO UPDATE SET revision=$2, document=$3, updated_at=now()`, [owner, next, request.document]);
      await client.query('INSERT INTO sync_receipts(owner_id,mutation_id,request_hash,revision) VALUES($1,$2,$3,$4)', [owner, request.mutationID, hash, next]);
      await client.query('COMMIT');
      return { status: 'saved' as const, revision: next };
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally { client.release(); }
  }
}
