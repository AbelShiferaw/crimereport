import { getClient, query } from '../lib/db';
import { ReportUpvote } from './types';

/**
 * Toggles an upvote: adds it if it doesn't exist, removes it if it does.
 * Uses a transaction with FOR UPDATE to prevent race conditions and keep
 * the report.upvotes counter in sync.
 * Returns true if the upvote was added, false if it was removed.
 */
export async function toggle(reportId: string, deviceId: string): Promise<boolean> {
  const client = await getClient();
  try {
    await client.query('BEGIN');

    // Lock the report row to prevent concurrent upvote races
    await client.query('SELECT id FROM reports WHERE id = $1 FOR UPDATE', [reportId]);

    const { rows } = await client.query<ReportUpvote>(
      'SELECT report_id FROM report_upvotes WHERE report_id = $1 AND device_id = $2 FOR UPDATE',
      [reportId, deviceId],
    );

    if (rows.length > 0) {
      await client.query(
        'DELETE FROM report_upvotes WHERE report_id = $1 AND device_id = $2',
        [reportId, deviceId],
      );
      await client.query(
        'UPDATE reports SET upvotes = GREATEST(upvotes - 1, 0) WHERE id = $1',
        [reportId],
      );
      await client.query('COMMIT');
      return false;
    }

    await client.query(
      'INSERT INTO report_upvotes (report_id, device_id) VALUES ($1, $2)',
      [reportId, deviceId],
    );
    await client.query(
      'UPDATE reports SET upvotes = upvotes + 1 WHERE id = $1',
      [reportId],
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

export async function existsForDevice(reportId: string, deviceId: string): Promise<boolean> {
  const { rows } = await query(
    'SELECT 1 FROM report_upvotes WHERE report_id = $1 AND device_id = $2',
    [reportId, deviceId],
  );
  return rows.length > 0;
}
