import { query } from '../lib/db';
import { Comment, CreateCommentInput, PaginationOptions } from './types';

export async function findByReportId(
  reportId: string,
  pagination: PaginationOptions = { limit: 20, offset: 0 },
): Promise<Comment[]> {
  const { rows } = await query<Comment>(
    `SELECT id, report_id, device_id, content, upvotes, created_at
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
     RETURNING id, report_id, device_id, content, upvotes, created_at`,
    [input.report_id, input.device_id, input.content],
  );
  return rows[0];
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
