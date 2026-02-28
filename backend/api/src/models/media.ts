import { query } from '../lib/db';
import { Media, CreateMediaInput } from './types';

const MEDIA_COLUMNS =
  'id, report_id, type, url, thumbnail_url, media_key, status, duration_ms, width, height, created_at';

export async function findByReportId(reportId: string): Promise<Media[]> {
  const { rows } = await query<Media>(
    `SELECT ${MEDIA_COLUMNS} FROM media WHERE report_id = $1 ORDER BY created_at ASC`,
    [reportId],
  );
  return rows;
}

export async function findByMediaKey(mediaKey: string): Promise<Media | null> {
  const { rows } = await query<Media>(
    `SELECT ${MEDIA_COLUMNS} FROM media WHERE media_key = $1`,
    [mediaKey],
  );
  return rows[0] ?? null;
}

export async function create(input: CreateMediaInput): Promise<Media> {
  const { rows } = await query<Media>(
    `INSERT INTO media (report_id, type, url, media_key, thumbnail_url, duration_ms, width, height)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     RETURNING ${MEDIA_COLUMNS}`,
    [
      input.report_id,
      input.type,
      input.url,
      input.media_key ?? null,
      input.thumbnail_url ?? null,
      input.duration_ms ?? null,
      input.width ?? null,
      input.height ?? null,
    ],
  );
  return rows[0];
}

export async function updateUrls(
  mediaKey: string,
  url: string,
  thumbnailUrl: string | null,
): Promise<Media | null> {
  const { rows } = await query<Media>(
    `UPDATE media SET url = $2, thumbnail_url = $3, status = 'active'
     WHERE media_key = $1
     RETURNING ${MEDIA_COLUMNS}`,
    [mediaKey, url, thumbnailUrl],
  );
  return rows[0] ?? null;
}

export async function updateStatus(mediaKey: string, status: string): Promise<void> {
  await query('UPDATE media SET status = $2 WHERE media_key = $1', [mediaKey, status]);
}

export async function deleteByReportId(reportId: string): Promise<number> {
  const result = await query('DELETE FROM media WHERE report_id = $1', [reportId]);
  return result.rowCount ?? 0;
}
