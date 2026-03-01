import { query } from '../lib/db';
import { ReportRow, CreateReportInput, PaginationOptions } from './types';

export async function findById(id: string): Promise<ReportRow | null> {
  const { rows } = await query<ReportRow>(
    `SELECT id, device_id, type, description,
            ST_Y(location::geometry) AS lat,
            ST_X(location::geometry) AS lng,
            address, status, upvotes, comment_count,
            created_at, updated_at
     FROM reports WHERE id = $1`,
    [id],
  );
  return rows[0] ?? null;
}

export async function findNearby(
  lat: number,
  lng: number,
  radiusMeters: number,
  pagination: PaginationOptions = { limit: 20, offset: 0 },
): Promise<ReportRow[]> {
  const { rows } = await query<ReportRow>(
    `SELECT id, device_id, type, description,
            ST_Y(location::geometry) AS lat,
            ST_X(location::geometry) AS lng,
            address, status, upvotes, comment_count,
            created_at, updated_at,
            ST_Distance(location, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography) AS distance_m
     FROM reports
     WHERE ST_DWithin(location, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography, $3)
       AND status = 'active'
     ORDER BY created_at DESC
     LIMIT $4 OFFSET $5`,
    [lat, lng, radiusMeters, pagination.limit, pagination.offset],
  );
  return rows;
}

export async function create(input: CreateReportInput): Promise<ReportRow> {
  const { rows } = await query<ReportRow>(
    `INSERT INTO reports (device_id, type, description, location, address)
     VALUES ($1, $2, $3, ST_SetSRID(ST_MakePoint($5, $4), 4326)::geography, $6)
     RETURNING id, device_id, type, description,
               ST_Y(location::geometry) AS lat,
               ST_X(location::geometry) AS lng,
               address, status, upvotes, comment_count,
               created_at, updated_at`,
    [input.device_id, input.type, input.description ?? null, input.lat, input.lng, input.address ?? null],
  );
  return rows[0];
}

export async function updateStatus(id: string, status: string): Promise<ReportRow | null> {
  const { rows } = await query<ReportRow>(
    `UPDATE reports SET status = $2
     WHERE id = $1
     RETURNING id, device_id, type, description,
               ST_Y(location::geometry) AS lat,
               ST_X(location::geometry) AS lng,
               address, status, upvotes, comment_count,
               created_at, updated_at`,
    [id, status],
  );
  return rows[0] ?? null;
}

export async function incrementUpvotes(id: string): Promise<void> {
  await query('UPDATE reports SET upvotes = upvotes + 1 WHERE id = $1', [id]);
}

export async function decrementUpvotes(id: string): Promise<void> {
  await query('UPDATE reports SET upvotes = GREATEST(upvotes - 1, 0) WHERE id = $1', [id]);
}

export async function incrementCommentCount(id: string): Promise<void> {
  await query('UPDATE reports SET comment_count = comment_count + 1 WHERE id = $1', [id]);
}

export async function decrementCommentCount(id: string): Promise<void> {
  await query('UPDATE reports SET comment_count = GREATEST(comment_count - 1, 0) WHERE id = $1', [id]);
}
