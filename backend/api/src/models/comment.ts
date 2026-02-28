import { getClient, query } from '../lib/db';
import { Comment, CreateCommentInput, PaginationOptions } from './types';

const COMMENT_COLUMNS = 'id, report_id, device_id, content, upvotes, flag_count, created_at';

export async function findById(id: string): Promise<Comment | null> {
  const { rows } = await query<Comment>(
    `SELECT ${COMMENT_COLUMNS} FROM comments WHERE id = $1`,
    [id],
  );
  return rows[0] ?? null;
}

export async function findByReportId(
  reportId: string,
  pagination: PaginationOptions = { limit: 20, offset: 0 },
): Promise<Comment[]> {
  const { rows } = await query<Comment>(
    `SELECT ${COMMENT_COLUMNS}
     FROM comments
     WHERE report_id = $1
     ORDER BY created_at DESC
     LIMIT $2 OFFSET $3`,
    [reportId, pagination.limit, pagination.offset],
  );
  return rows;
}

export async function create(input: CreateCommentInput): Promise<Comment> {
  const { rows } = await query<Comment>(
    `INSERT INTO comments (report_id, device_id, content)
     VALUES ($1, $2, $3)
     RETURNING ${COMMENT_COLUMNS}`,
    [input.report_id, input.device_id, input.content],
  );
  return rows[0];
}

/**
 * Atomically creates a comment and increments the report's comment_count
 * in a single transaction to prevent count drift.
 */
export async function createForReport(input: CreateCommentInput): Promise<Comment> {
  const client = await getClient();
  try {
    await client.query('BEGIN');

    const { rows } = await client.query<Comment>(
      `INSERT INTO comments (report_id, device_id, content)
       VALUES ($1, $2, $3)
       RETURNING ${COMMENT_COLUMNS}`,
      [input.report_id, input.device_id, input.content],
    );

    await client.query(
      'UPDATE reports SET comment_count = comment_count + 1 WHERE id = $1',
      [input.report_id],
    );

    await client.query('COMMIT');
    return rows[0];
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

export async function deleteById(id: string): Promise<boolean> {
  const result = await query('DELETE FROM comments WHERE id = $1', [id]);
  return (result.rowCount ?? 0) > 0;
}

export async function countByReportId(reportId: string): Promise<number> {
  const { rows } = await query<{ count: string }>(
    'SELECT COUNT(*) AS count FROM comments WHERE report_id = $1',
    [reportId],
  );
  return parseInt(rows[0].count, 10);
}

export async function countTodayByDevice(deviceId: string): Promise<number> {
  const { rows } = await query<{ count: string }>(
    `SELECT COUNT(*) AS count FROM comments
     WHERE device_id = $1 AND created_at > NOW() - INTERVAL '24 hours'`,
    [deviceId],
  );
  return parseInt(rows[0].count, 10);
}
