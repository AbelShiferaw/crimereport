import { query } from '../lib/db';
import { Media, CreateMediaInput } from './types';

export async function findByReportId(reportId: string): Promise<Media[]> {
  const { rows } = await query<Media>(
    `SELECT id, report_id, type, url, thumbnail_url,
            duration_ms, width, height, created_at
     FROM media WHERE report_id = $1
     ORDER BY created_at ASC`,
    [reportId],
  );
  return rows;
}

export async function create(input: CreateMediaInput): Promise<Media> {
  const { rows } = await query<Media>(
    `INSERT INTO media (report_id, type, url, thumbnail_url, duration_ms, width, height)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     RETURNING id, report_id, type, url, thumbnail_url,
               duration_ms, width, height, created_at`,
    [
      input.report_id,
      input.type,
      input.url,
      input.thumbnail_url ?? null,
      input.duration_ms ?? null,
      input.width ?? null,
      input.height ?? null,
    ],
  );
  return rows[0];
}

export async function deleteByReportId(reportId: string): Promise<number> {
  const result = await query('DELETE FROM media WHERE report_id = $1', [reportId]);
  return result.rowCount ?? 0;
}
