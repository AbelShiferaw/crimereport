# Milestone 21: Comments Endpoints

## Status
Completed

## Goal
Implement REST API endpoints for listing and creating comments on reports, plus flagging inappropriate comments — all identified by anonymous device IDs.

## Dependencies
Requires **Milestone 20** complete (report CRUD endpoints working).

## What Was Built
- **GET /reports/:id/comments** — paginated comment list for a report
- **POST /reports/:id/comments** — create a comment with transactional `comment_count` update on the parent report
- **POST /comments/:id/flag** — flag a comment with per-device duplicate prevention
- Zod validation schemas with whitespace trimming and length limits
- Device-based daily rate limiting (50 comments/day)
- Guards against commenting on removed reports and from flagged devices
- `comment-flag` model using `SELECT ... FOR UPDATE` row-level locking for safe concurrent flag inserts

## Key Files
| File | Description |
|------|-------------|
| `backend/api/src/routes/reports.ts` | Comment list + creation routes (nested under `/reports/:id`) |
| `backend/api/src/routes/comments.ts` | Flag-comment route (`POST /comments/:id/flag`) |
| `backend/api/src/models/comment.ts` | Comment queries: find, create, `createForReport` (transactional), count helpers |
| `backend/api/src/models/comment-flag.ts` | Atomic flag insert with duplicate prevention |
| `backend/api/src/models/types.ts` | `Comment`, `CommentFlag`, `CreateCommentInput` interfaces |
| `backend/api/src/validators/comment.ts` | Zod schemas for create, flag, and list-query validation |
| `backend/api/src/middleware/validate.ts` | Generic Zod-based validation middleware |
| `backend/api/src/lib/errors.ts` | `HttpError` class with static factory methods |
| `backend/api/migrations/1709100000000_add-comment-flags.sql` | Adds `flag_count` column + `comment_flags` table |
| `backend/api/src/__tests__/routes/comments.test.ts` | Route-level integration tests (supertest) |
| `backend/api/src/__tests__/models/comment.test.ts` | Unit tests for comment model |
| `backend/api/src/__tests__/models/comment-flag.test.ts` | Unit tests for comment-flag model |

## Implementation Details

### Route Mounting

Comments routes are split across two routers. Listing and creating comments live under the report router (`/api/v1/reports`), while flagging lives on a dedicated comment router (`/api/v1/comments`):

```typescript
// backend/api/src/routes/index.ts
router.use('/reports', reportRouter);
router.use('/comments', commentRouter);
```

### GET /reports/:id/comments — Paginated List

Validates query-string pagination via Zod, confirms the report exists, then delegates to the comment model:

```typescript
// backend/api/src/routes/reports.ts  (lines 85–101)
router.get(
  '/:id/comments',
  validate(commentListQuerySchema, 'query'),
  async (req: Request, res: Response) => {
    const { id } = req.params;
    const { limit, offset } = req.query as unknown as { limit: number; offset: number };

    const report = await reportModel.findById(id);
    if (!report) {
      throw HttpError.notFound('Report not found');
    }

    const comments = await commentModel.findByReportId(id, { limit, offset });

    res.json({ data: comments, meta: { report_id: id, limit, offset, count: comments.length } });
  },
);
```

The model query orders by `created_at DESC` with defaults of `limit: 20, offset: 0`:

```typescript
// backend/api/src/models/comment.ts  (lines 14–27)
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
```

### POST /reports/:id/comments — Create Comment

The route handler performs four guard checks before creating:

1. Report must exist
2. Report must not have `status === 'removed'`
3. Device must not be flagged
4. Device must not have exceeded the daily comment limit (50/day)

```typescript
// backend/api/src/routes/reports.ts  (lines 103–133)
router.post(
  '/:id/comments',
  validate(createCommentSchema),
  async (req: Request, res: Response) => {
    const { id } = req.params;
    const { device_id, content } = req.body;

    const report = await reportModel.findById(id);
    if (!report) {
      throw HttpError.notFound('Report not found');
    }

    if (report.status === 'removed') {
      throw HttpError.forbidden('Cannot comment on a removed report');
    }

    const device = await deviceActivity.getOrCreate(device_id);
    if (device.flagged) {
      throw HttpError.forbidden('This device has been flagged for abuse');
    }

    const todayCount = await commentModel.countTodayByDevice(device_id);
    if (todayCount >= MAX_DAILY_COMMENTS) {
      throw HttpError.tooManyRequests(`Daily comment limit of ${MAX_DAILY_COMMENTS} reached`);
    }

    const comment = await commentModel.createForReport({ report_id: id, device_id, content });

    res.status(201).json(comment);
  },
);
```

Comment creation uses a database transaction to atomically insert the comment **and** increment the report's `comment_count`, preventing count drift:

```typescript
// backend/api/src/models/comment.ts  (lines 43–68)
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
```

### POST /comments/:id/flag — Flag Comment

A separate router handles flagging. The route checks comment existence, then delegates to the `comment-flag` model:

```typescript
// backend/api/src/routes/comments.ts
router.post('/:id/flag', validate(flagCommentSchema), async (req: Request, res: Response) => {
  const { id } = req.params;
  const { device_id } = req.body;

  const comment = await commentModel.findById(id);
  if (!comment) {
    throw HttpError.notFound('Comment not found');
  }

  const flagged = await commentFlagModel.flag(id, device_id);

  res.json({ flagged });
});
```

The flag model uses `SELECT ... FOR UPDATE` to lock the comment row, checks for an existing flag from the same device (duplicate prevention), and atomically inserts the flag + increments `flag_count`:

```typescript
// backend/api/src/models/comment-flag.ts  (lines 9–43)
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
```

### Validation Schemas

All validation uses Zod (not Joi). The `content` field applies `.trim()` to reject whitespace-only strings:

```typescript
// backend/api/src/validators/comment.ts
export const createCommentSchema = z.object({
  device_id: z.string().min(1).max(64),
  content: z.string().trim().min(1).max(1000),
});

export const flagCommentSchema = z.object({
  device_id: z.string().min(1).max(64),
});

export const commentListQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  offset: z.coerce.number().int().min(0).default(0),
});
```

### Database Migration

```sql
-- backend/api/migrations/1709100000000_add-comment-flags.sql

ALTER TABLE comments ADD COLUMN flag_count INTEGER NOT NULL DEFAULT 0;

CREATE TABLE comment_flags (
    comment_id UUID NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
    device_id VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (comment_id, device_id)
);
```

## API Endpoints Summary

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/reports/:id/comments` | Paginated comment list for a report |
| POST | `/api/v1/reports/:id/comments` | Create comment (transactional count update) |
| POST | `/api/v1/comments/:id/flag` | Flag a comment (idempotent per device) |

## Testing

Three test suites cover this milestone, all using Jest with `supertest` for route tests and mock-based unit tests for models:

**`src/__tests__/routes/comments.test.ts`** (route integration):
- GET returns paginated comments with meta; custom pagination; 404 for missing report
- POST creates comment with 201; rejects missing report (404), removed reports (403), flagged devices (403), rate-limited devices (429), missing/invalid content (400), whitespace-only content (400)
- POST flag returns `flagged: true/false`; 404 for missing comment; 400 for missing device_id

**`src/__tests__/models/comment.test.ts`** (model unit):
- `findByReportId` with custom and default pagination
- `create` inserts and returns comment
- `createForReport` runs BEGIN/INSERT/UPDATE/COMMIT; rolls back on error
- `deleteById` returns true/false
- `countByReportId` and `countTodayByDevice` return numeric counts
- `findById` returns comment or null

**`src/__tests__/models/comment-flag.test.ts`** (model unit):
- `flag` inserts flag + increments `flag_count` when new; returns false when duplicate; rolls back on error
- `existsForDevice` returns true/false

## Notes

### Deviations from Original Plan
- **TypeScript + ES modules** instead of JavaScript + CommonJS (`require`)
- **No controller/service/repository layers** — routes call model functions directly (flat architecture)
- **Zod** for validation instead of Joi
- **`HttpError`** class with static factories instead of custom error classes
- **No upvote/toggle or delete-comment endpoints** — the original plan included `POST /:id/upvote` and `DELETE /:id`; these were not implemented. Flagging was implemented instead.
- **No `anonymousId` hash or `isReporter` flag** in comment responses
- **Comments nested under `/reports/:id/comments`** instead of a standalone `/comments` resource
- **Daily limit (50/day)** instead of hourly limit (30/hour) as originally planned
- **`createForReport`** uses an explicit transaction with `getClient()` instead of incrementing the count in a separate query
- **`flag_count`** column tracks flags directly on the comment row, kept in sync via `SELECT FOR UPDATE` locking
