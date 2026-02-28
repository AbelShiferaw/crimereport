import { getClient, query } from '../lib/db';
import { CommentFlag } from './types';

/**
 * Flags a comment from a device. Uses a transaction to atomically insert the
 * flag record and increment the comment's flag_count. Returns true if the flag
 * was newly added, false if the device already flagged this comment.
 */
export async function flag(commentId: string, deviceId: string): Promise<boolean> {
  const client = await getClient();
  try {
    await client.query('BEGIN');

    await client.query('SELECT id FROM comments WHERE id = $1 FOR UPDATE', [commentId]);

    const { rows } = await client.query<CommentFlag>(
      'SELECT comment_id FROM comment_flags WHERE comment_id = $1 AND device_id = $2',
      [commentId, deviceId],
    );

    if (rows.length > 0) {
      await client.query('COMMIT');
      return false;
    }

    await client.query(
      'INSERT INTO comment_flags (comment_id, device_id) VALUES ($1, $2)',
      [commentId, deviceId],
    );
    await client.query(
      'UPDATE comments SET flag_count = flag_count + 1 WHERE id = $1',
      [commentId],
    );

    await client.query('COMMIT');
    return true;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

export async function existsForDevice(commentId: string, deviceId: string): Promise<boolean> {
  const { rows } = await query(
    'SELECT 1 FROM comment_flags WHERE comment_id = $1 AND device_id = $2',
    [commentId, deviceId],
  );
  return rows.length > 0;
}
