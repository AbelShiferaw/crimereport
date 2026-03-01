# Milestone 20: Report CRUD Endpoints

## Status
Completed

## Goal
Implement REST API endpoints for creating, reading, and managing crime reports — including PostGIS nearby queries, upvote toggling, device rate limiting, and Zod validation.

## Dependencies
Requires **Milestone 19** complete (database integration working).

## What Was Built
A full set of report CRUD routes at `/api/v1/reports` with Zod request validation, PostGIS spatial queries, transactional upvote toggling, device-based rate limiting (10 reports/day), and an `HttpError`-based error flow. The implementation uses a flat model-per-file pattern (no controllers/services) — route handlers call model functions directly. Comprehensive Jest + Supertest tests cover both route-level and model-level behavior.

## Key Files

| File | Description |
|------|-------------|
| `backend/api/src/routes/reports.ts` | All report routes (CRUD, upvote, comments, media upload) |
| `backend/api/src/models/report.ts` | Report model — `findById`, `findNearby`, `create`, `updateStatus`, upvote/comment counters |
| `backend/api/src/models/report-upvote.ts` | Transactional upvote toggle with `SELECT ... FOR UPDATE` |
| `backend/api/src/models/device-activity.ts` | Device rate limiting — `getOrCreate`, `incrementReportCount`, `flag` |
| `backend/api/src/validators/report.ts` | Zod schemas for create, nearby query, and upvote |
| `backend/api/src/models/types.ts` | `ReportRow`, `CreateReportInput`, `ReportUpvote`, `DeviceActivity` interfaces |
| `backend/api/src/lib/errors.ts` | `HttpError` class used by all route handlers |
| `backend/api/src/__tests__/routes/reports.test.ts` | Route-level tests (14 test cases) |
| `backend/api/src/__tests__/models/report.test.ts` | Model-level tests (8 test cases) |

## Implementation Details

### 1. Report Routes

All report-specific endpoints live in a single router file. Route handlers are inline async functions that throw `HttpError` instances (caught by `express-async-errors` + the global error handler):

```typescript
// backend/api/src/routes/reports.ts
import { Router, Request, Response } from 'express';
import { validate } from '../middleware/validate';
import { createReportSchema, nearbyQuerySchema, upvoteSchema } from '../validators/report';
import { HttpError } from '../lib/errors';
import * as reportModel from '../models/report';
import * as upvoteModel from '../models/report-upvote';
import * as deviceActivity from '../models/device-activity';

const MAX_DAILY_REPORTS = 10;
const router = Router();
```

**POST /reports** — create a report with device rate limiting:

```typescript
router.post('/', validate(createReportSchema), async (req: Request, res: Response) => {
  const { device_id, type, description, lat, lng, address } = req.body;

  const device = await deviceActivity.getOrCreate(device_id);

  if (device.flagged) {
    throw HttpError.forbidden('This device has been flagged for abuse');
  }
  if (device.report_count_today >= MAX_DAILY_REPORTS) {
    throw HttpError.tooManyRequests(`Daily report limit of ${MAX_DAILY_REPORTS} reached`);
  }

  const report = await reportModel.create({ device_id, type, description, lat, lng, address });
  await deviceActivity.incrementReportCount(device_id);

  res.status(201).json(report);
});
```

**GET /reports** — nearby query with PostGIS spatial filtering:

```typescript
router.get('/', validate(nearbyQuerySchema, 'query'), async (req: Request, res: Response) => {
  const { lat, lng, radius, limit, offset } = req.query as unknown as {
    lat: number; lng: number; radius: number; limit: number; offset: number;
  };

  const reports = await reportModel.findNearby(lat, lng, radius, { limit, offset });

  res.json({ data: reports, meta: { lat, lng, radius, limit, offset, count: reports.length } });
});
```

**GET /reports/:id** — single report with attached media:

```typescript
router.get('/:id', async (req: Request, res: Response) => {
  const report = await reportModel.findById(req.params.id);
  if (!report) throw HttpError.notFound('Report not found');

  const media = await mediaModel.findByReportId(report.id);
  res.json({ ...report, media });
});
```

**POST /reports/:id/upvote** — toggle upvote:

```typescript
router.post('/:id/upvote', validate(upvoteSchema), async (req: Request, res: Response) => {
  const { id } = req.params;
  const { device_id } = req.body;

  const report = await reportModel.findById(id);
  if (!report) throw HttpError.notFound('Report not found');

  const upvoted = await upvoteModel.toggle(id, device_id);
  res.json({ upvoted });
});
```

### 2. Zod Validation Schemas

```typescript
// backend/api/src/validators/report.ts
import { z } from 'zod';

export const CRIME_TYPES = [
  'theft', 'assault', 'vandalism', 'robbery', 'burglary',
  'suspicious', 'shooting', 'carjacking', 'harassment', 'drug_activity', 'other',
] as const;

export const createReportSchema = z.object({
  device_id: z.string().min(1).max(64),
  type: z.enum(CRIME_TYPES),
  description: z.string().max(2000).optional(),
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  address: z.string().max(255).optional(),
});

export const nearbyQuerySchema = z.object({
  lat: z.coerce.number().min(-90).max(90),
  lng: z.coerce.number().min(-180).max(180),
  radius: z.coerce.number().min(100).max(50_000).default(5_000),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  offset: z.coerce.number().int().min(0).default(0),
});

export const upvoteSchema = z.object({
  device_id: z.string().min(1).max(64),
});
```

The nearby query schema uses `z.coerce.number()` because Express query parameters arrive as strings.

### 3. Report Model (PostGIS Queries)

All queries extract `lat`/`lng` from the PostGIS `GEOGRAPHY` column using `ST_Y`/`ST_X`:

```typescript
// backend/api/src/models/report.ts
import { query } from '../lib/db';
import { ReportRow, CreateReportInput, PaginationOptions } from './types';

export async function findById(id: string): Promise<ReportRow | null> {
  const { rows } = await query<ReportRow>(
    `SELECT id, device_id, type, description,
            ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng,
            address, status, upvotes, comment_count, created_at, updated_at
     FROM reports WHERE id = $1`,
    [id],
  );
  return rows[0] ?? null;
}

export async function findNearby(
  lat: number, lng: number, radiusMeters: number,
  pagination: PaginationOptions = { limit: 20, offset: 0 },
): Promise<ReportRow[]> {
  const { rows } = await query<ReportRow>(
    `SELECT id, device_id, type, description,
            ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng,
            address, status, upvotes, comment_count, created_at, updated_at,
            ST_Distance(location, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography) AS distance_m
     FROM reports
     WHERE ST_DWithin(location, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography, $3)
       AND status != 'removed'
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
               ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng,
               address, status, upvotes, comment_count, created_at, updated_at`,
    [input.device_id, input.type, input.description ?? null, input.lat, input.lng, input.address ?? null],
  );
  return rows[0];
}

export async function updateStatus(id: string, status: string): Promise<ReportRow | null> {
  const { rows } = await query<ReportRow>(
    `UPDATE reports SET status = $2 WHERE id = $1
     RETURNING id, device_id, type, description,
               ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng,
               address, status, upvotes, comment_count, created_at, updated_at`,
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
```

### 4. Upvote Toggle (Transactional)

Uses `SELECT ... FOR UPDATE` row-level locking to prevent race conditions:

```typescript
// backend/api/src/models/report-upvote.ts
import { getClient, query } from '../lib/db';
import { ReportUpvote } from './types';

export async function toggle(reportId: string, deviceId: string): Promise<boolean> {
  const client = await getClient();
  try {
    await client.query('BEGIN');
    await client.query('SELECT id FROM reports WHERE id = $1 FOR UPDATE', [reportId]);

    const { rows } = await client.query<ReportUpvote>(
      'SELECT report_id FROM report_upvotes WHERE report_id = $1 AND device_id = $2 FOR UPDATE',
      [reportId, deviceId],
    );

    if (rows.length > 0) {
      await client.query('DELETE FROM report_upvotes WHERE report_id = $1 AND device_id = $2', [reportId, deviceId]);
      await client.query('UPDATE reports SET upvotes = GREATEST(upvotes - 1, 0) WHERE id = $1', [reportId]);
      await client.query('COMMIT');
      return false;
    }

    await client.query('INSERT INTO report_upvotes (report_id, device_id) VALUES ($1, $2)', [reportId, deviceId]);
    await client.query('UPDATE reports SET upvotes = upvotes + 1 WHERE id = $1', [reportId]);
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
```

### 5. Device Activity & Rate Limiting

```typescript
// backend/api/src/models/device-activity.ts
import { query } from '../lib/db';
import { DeviceActivity } from './types';

export async function getOrCreate(deviceId: string): Promise<DeviceActivity> {
  const { rows } = await query<DeviceActivity>(
    `INSERT INTO device_activity (device_id)
     VALUES ($1)
     ON CONFLICT (device_id) DO UPDATE SET device_id = EXCLUDED.device_id
     RETURNING device_id, report_count_today, last_report_at, flagged, created_at`,
    [deviceId],
  );
  return rows[0];
}

export async function incrementReportCount(deviceId: string): Promise<DeviceActivity> {
  const { rows } = await query<DeviceActivity>(
    `UPDATE device_activity
     SET report_count_today = report_count_today + 1, last_report_at = NOW()
     WHERE device_id = $1
     RETURNING device_id, report_count_today, last_report_at, flagged, created_at`,
    [deviceId],
  );
  return rows[0];
}

export async function resetDailyCounts(): Promise<number> {
  const result = await query(
    'UPDATE device_activity SET report_count_today = 0 WHERE report_count_today > 0',
  );
  return result.rowCount ?? 0;
}
```

## API Endpoints Summary

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/reports` | Create a new crime report |
| GET | `/api/v1/reports` | Get reports within radius (PostGIS `ST_DWithin`) |
| GET | `/api/v1/reports/:id` | Get single report with attached media |
| POST | `/api/v1/reports/:id/upvote` | Toggle upvote (transactional) |
| GET | `/api/v1/reports/:id/comments` | List comments for a report |
| POST | `/api/v1/reports/:id/comments` | Add a comment to a report |
| POST | `/api/v1/reports/:id/upload` | Request a presigned S3 upload URL |
| POST | `/api/v1/reports/:id/upload/complete` | Confirm upload completion |
| GET | `/api/v1/reports/:id/media/status` | Check media processing status |

## Testing

### Route Tests (`backend/api/src/__tests__/routes/reports.test.ts`)

14 test cases using Jest + Supertest with mocked models:

- **POST /reports**: creates report (201), rejects missing fields (400), rejects invalid lat (400), rejects invalid crime type (400), rejects flagged device (403), rejects when daily limit exceeded (429)
- **GET /reports**: returns nearby reports with metadata (200), applies custom pagination, rejects missing lat/lng (400), rejects radius too large (400)
- **GET /reports/:id**: returns report with media (200), returns 404 when not found
- **POST /reports/:id/upvote**: adds upvote returning `upvoted: true`, removes upvote returning `upvoted: false`, returns 404 when report not found, rejects missing device_id (400)

### Model Tests (`backend/api/src/__tests__/models/report.test.ts`)

8 test cases with mocked `db.query`:

- `findById`: returns report when found, returns null when not found
- `findNearby`: queries with `ST_DWithin`, uses default pagination
- `create`: inserts with PostGIS `ST_MakePoint` and returns new row
- `updateStatus`: updates and returns, returns null when not found
- `incrementUpvotes`, `decrementUpvotes`, `incrementCommentCount`, `decrementCommentCount`: verify correct SQL

## Notes

**Deviations from original plan:**
- **No controller/service/repository layers.** The original plan had `reportController.js`, `reportService.js`, `reportRepository.js`, and `baseRepository.js`. The implementation uses a flat architecture: route handlers call model functions directly. Business logic (rate limiting, validation) lives inline in the route handlers.
- **No cache layer.** The original plan had `reportCacheService.js` with Redis-backed caching for `getNearbyReports`. Not implemented — all queries hit PostgreSQL directly.
- **Zod replaced Joi.** Validation schemas use `z.object()` / `z.enum()` / `z.coerce.number()` instead of `Joi.object()` / `Joi.string().valid()`.
- **Flat nearby endpoint.** `GET /reports` with query params replaces the planned `GET /reports/nearby` and `GET /reports/location` as separate endpoints. A single endpoint with `radius` serves both use cases.
- **Upvote uses `device_id` in body** instead of relying on a `req.deviceId` set by middleware. There is no `validateDevice` middleware; device ID is passed explicitly per-request.
- **Transactional upvote toggle** with `FOR UPDATE` locking replaces the simple non-transactional upvote in the original plan. The `decrementUpvotes` model function uses `GREATEST(upvotes - 1, 0)` to prevent negative counts.
- **Crime types expanded.** The original plan had 7 types; the implementation has 11 including `robbery`, `burglary`, `shooting`, `carjacking`, `harassment`, and `drug_activity`.
- **No flag endpoint on reports.** The planned `POST /reports/:id/flag` was not implemented on the reports router. Comment flagging exists at `POST /api/v1/comments/:id/flag` instead.
- **Additional endpoints** not in the original plan: comments sub-routes (`GET/POST /:id/comments`), media upload sub-routes (`POST /:id/upload`, `POST /:id/upload/complete`, `GET /:id/media/status`) are also implemented in the same `reports.ts` router.
