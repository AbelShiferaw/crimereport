# Milestone 22: Media Upload Flow

## Status
Completed

## Goal
Implement a two-phase presigned-URL upload flow for images and videos attached to reports, with S3 verification, polling-based status tracking, and CDN URL construction.

## Dependencies
Requires **Milestone 16** (S3 buckets, CloudFront CDN) and **Milestone 20** (report CRUD endpoints).

## What Was Built
- **POST /reports/:id/upload** — Phase 1: generates a presigned S3 PUT URL and creates a `pending` media record
- **POST /reports/:id/upload/complete** — Phase 2: verifies the object landed in S3, transitions media to `processing`
- **GET /reports/:id/media/status** — Polling endpoint that checks both S3 buckets, updates CDN URLs when processing completes, and derives aggregate report status
- `s3.ts` utility module wrapping AWS SDK v3 for presigned URLs, `HeadObject` checks, CDN URL building, and media key generation
- Zod validation with `file_type`/`content_type` cross-field refinement
- Edge-case guards: ownership check, removed-report check, flagged-device check, media-per-report limit (5), report status gating, idempotent completion

## Key Files
| File | Description |
|------|-------------|
| `backend/api/src/routes/reports.ts` | Upload, complete, and media-status routes (lines 135–297) |
| `backend/api/src/lib/s3.ts` | S3 helpers: `generateUploadUrl`, `objectExists`, `buildCdnUrl`, `buildMediaKey` |
| `backend/api/src/models/media.ts` | Media queries: find, create, `updateUrls`, `updateStatus`, delete |
| `backend/api/src/models/types.ts` | `Media`, `CreateMediaInput` interfaces |
| `backend/api/src/validators/media.ts` | Zod schemas for upload request and upload-complete |
| `backend/api/src/config.ts` | AWS config: region, bucket names, CDN domain |
| `backend/api/migrations/1709200000000_add-media-key.sql` | Adds `media_key` + `status` columns with indexes |
| `backend/api/src/__tests__/routes/media-upload.test.ts` | Route-level integration tests (supertest) |
| `backend/api/src/__tests__/models/media.test.ts` | Unit tests for media model |

## Implementation Details

### Upload Architecture

The flow is report-scoped — all three endpoints are nested under `/api/v1/reports/:id`. The client never uploads through the API server; it receives a presigned URL and PUTs directly to S3.

```
Mobile App                   API Server                     AWS S3
    │                            │                             │
    │ POST /reports/:id/upload   │                             │
    │ ──────────────────────────>│                             │
    │                            │  create media record        │
    │                            │  generate presigned URL     │
    │  { upload_url, media_key } │                             │
    │ <──────────────────────────│                             │
    │                            │                             │
    │  PUT upload_url (binary)   │                             │
    │ ─────────────────────────────────────────────────────────>
    │                            │                             │
    │ POST /:id/upload/complete  │                             │
    │ ──────────────────────────>│  HeadObject (verify upload) │
    │                            │ ───────────────────────────>│
    │   { status: processing }   │                             │
    │ <──────────────────────────│                             │
    │                            │                             │
    │ GET /:id/media/status      │  HeadObject (check both     │
    │ ──────────────────────────>│  buckets, build CDN URLs)   │
    │   { status, media[] }      │ ───────────────────────────>│
    │ <──────────────────────────│                             │
```

### Content-Type Mapping

A lookup table maps allowed MIME types to file extensions. Only types in this map pass Zod validation:

```typescript
// backend/api/src/routes/reports.ts  (lines 139–146)
const CONTENT_TYPE_TO_EXT: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'video/mp4': 'mp4',
  'video/quicktime': 'mov',
  'video/webm': 'webm',
};
```

### Phase 1: POST /reports/:id/upload — Presigned URL Generation

Performs five checks before generating the URL:

1. Report exists
2. Report owner matches `device_id`
3. Report is not `removed`
4. Report status allows uploads (`pending`, `uploading`, or `failed`)
5. Device is not flagged
6. Media count has not reached `MAX_MEDIA_PER_REPORT` (5)

Then generates a structured media key, creates a presigned PUT URL, inserts a `pending` media record, and transitions the report to `uploading`:

```typescript
// backend/api/src/routes/reports.ts  (lines 150–201)
router.post(
  '/:id/upload',
  validate(uploadRequestSchema),
  async (req: Request, res: Response) => {
    const { id } = req.params;
    const { device_id, file_type, content_type } = req.body;

    const report = await reportModel.findById(id);
    if (!report) throw HttpError.notFound('Report not found');

    if (report.device_id !== device_id)
      throw HttpError.forbidden('Not authorized to upload to this report');

    if (report.status === 'removed')
      throw HttpError.forbidden('Cannot upload to a removed report');

    if (!UPLOAD_ALLOWED_STATUSES.has(report.status))
      throw HttpError.conflict('Report already has media being processed or active');

    const device = await deviceActivity.getOrCreate(device_id);
    if (device.flagged) throw HttpError.forbidden('This device has been flagged for abuse');

    const existingMedia = await mediaModel.findByReportId(id);
    if (existingMedia.length >= MAX_MEDIA_PER_REPORT)
      throw HttpError.badRequest(`Maximum of ${MAX_MEDIA_PER_REPORT} media items per report`);

    const ext = CONTENT_TYPE_TO_EXT[content_type] ?? 'bin';
    const fileId = randomUUID();
    const mediaKey = s3.buildMediaKey(file_type, id, fileId, ext);

    const { url: uploadUrl, expiresIn } = await s3.generateUploadUrl(mediaKey, content_type);

    await mediaModel.create({
      report_id: id,
      type: file_type,
      url: '',
      media_key: mediaKey,
    });

    await reportModel.updateStatus(id, 'uploading');

    res.status(201).json({ upload_url: uploadUrl, media_key: mediaKey, expires_in: expiresIn });
  },
);
```

### S3 Utility Module

Wraps AWS SDK v3 with four focused functions:

```typescript
// backend/api/src/lib/s3.ts
import { S3Client, PutObjectCommand, HeadObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { config } from '../config';

const PRESIGNED_URL_EXPIRES_IN = 15 * 60; // 15 minutes

const s3 = new S3Client({ region: config.aws.region });

export async function generateUploadUrl(
  key: string,
  contentType: string,
): Promise<{ url: string; expiresIn: number }> {
  const command = new PutObjectCommand({
    Bucket: config.aws.s3UploadsBucket,
    Key: key,
    ContentType: contentType,
  });

  const url = await getSignedUrl(s3, command, { expiresIn: PRESIGNED_URL_EXPIRES_IN });
  return { url, expiresIn: PRESIGNED_URL_EXPIRES_IN };
}

export async function objectExists(bucket: string, key: string): Promise<boolean> {
  try {
    await s3.send(new HeadObjectCommand({ Bucket: bucket, Key: key }));
    return true;
  } catch (err: any) {
    if (err.name === 'NotFound' || err.$metadata?.httpStatusCode === 404) {
      return false;
    }
    throw err;
  }
}

export function buildCdnUrl(key: string): string {
  const domain = config.aws.cdnDomain;
  if (!domain) return '';
  return `https://${domain}/${key}`;
}

export function buildMediaKey(
  fileType: 'image' | 'video',
  reportId: string,
  fileId: string,
  ext: string,
): string {
  const prefix = fileType === 'image' ? 'images' : 'videos';
  return `${prefix}/${reportId}/${fileId}.${ext}`;
}
```

### Phase 2: POST /reports/:id/upload/complete — S3 Verification

After the client finishes the direct S3 PUT, it calls this endpoint. The handler:

1. Validates report existence and ownership
2. Looks up the media record by `media_key`
3. **Idempotency**: if the media is already `processing` or `active`, returns the current status without re-verifying
4. Calls `s3.objectExists` on the uploads bucket to confirm the file arrived
5. Transitions media to `processing` and report to `processing`

```typescript
// backend/api/src/routes/reports.ts  (lines 203–239)
router.post(
  '/:id/upload/complete',
  validate(uploadCompleteSchema),
  async (req: Request, res: Response) => {
    const { id } = req.params;
    const { device_id, media_key } = req.body;

    const report = await reportModel.findById(id);
    if (!report) throw HttpError.notFound('Report not found');

    if (report.device_id !== device_id)
      throw HttpError.forbidden('Not authorized for this report');

    const media = await mediaModel.findByMediaKey(media_key);
    if (!media || media.report_id !== id)
      throw HttpError.notFound('Media not found for this report');

    if (media.status === 'processing' || media.status === 'active') {
      res.json({ status: media.status });
      return;
    }

    const exists = await s3.objectExists(config.aws.s3UploadsBucket, media_key);
    if (!exists)
      throw HttpError.badRequest('File not found in uploads bucket. Upload may have failed.');

    await mediaModel.updateStatus(media_key, 'processing');
    await reportModel.updateStatus(id, 'processing');

    res.json({ status: 'processing' });
  },
);
```

### Polling: GET /reports/:id/media/status — Status Check with CDN Resolution

The client polls this endpoint to discover when processing completes. For each media item:

- If already `active`, return as-is
- Check the **media bucket** for the processed file; if found, build CDN URL (+ optional thumbnail) and update the record to `active`
- If not in media bucket, check the **uploads bucket** — if missing from both and status is `processing`, mark as `failed`

After resolving all items, the handler derives aggregate report status:

```typescript
// backend/api/src/routes/reports.ts  (lines 241–297)
router.get('/:id/media/status', async (req: Request, res: Response) => {
  const { id } = req.params;

  const report = await reportModel.findById(id);
  if (!report) throw HttpError.notFound('Report not found');

  const mediaItems = await mediaModel.findByReportId(id);

  if (mediaItems.length === 0) {
    res.json({ status: report.status, media: [] });
    return;
  }

  const results = await Promise.all(
    mediaItems.map(async (item) => {
      if (item.status === 'active') return item;
      if (!item.media_key) return item;

      const processedKey = item.media_key;
      const processed = await s3.objectExists(config.aws.s3MediaBucket, processedKey);

      if (processed) {
        const cdnUrl = s3.buildCdnUrl(processedKey);

        const thumbnailKey = processedKey.replace(/\.[^.]+$/, '_thumb.jpg');
        const hasThumb = await s3.objectExists(config.aws.s3MediaBucket, thumbnailKey);
        const thumbUrl = hasThumb ? s3.buildCdnUrl(thumbnailKey) : null;

        const updated = await mediaModel.updateUrls(processedKey, cdnUrl, thumbUrl);
        return updated ?? item;
      }

      const stillInUploads = await s3.objectExists(config.aws.s3UploadsBucket, processedKey);
      if (!stillInUploads && item.status === 'processing') {
        await mediaModel.updateStatus(processedKey, 'failed');
        return { ...item, status: 'failed' };
      }

      return item;
    }),
  );

  const allActive = results.every((m) => m.status === 'active');
  const anyFailed = results.some((m) => m.status === 'failed');

  if (allActive && report.status !== 'active') {
    await reportModel.updateStatus(id, 'active');
  } else if (anyFailed && report.status === 'processing') {
    await reportModel.updateStatus(id, 'failed');
  }

  const currentStatus = allActive ? 'active' : anyFailed ? 'failed' : report.status;

  res.json({ status: currentStatus, media: results });
});
```

### Media Model

Tracks media records keyed by `media_key`. The `updateUrls` function atomically sets the CDN URL, thumbnail, and status to `active`:

```typescript
// backend/api/src/models/media.ts  (lines 42–54)
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
```

### Validation Schemas

Zod schemas with a cross-field refinement ensuring `content_type` matches `file_type`:

```typescript
// backend/api/src/validators/media.ts
const ALLOWED_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp'] as const;
const ALLOWED_VIDEO_TYPES = ['video/mp4', 'video/quicktime', 'video/webm'] as const;
const ALLOWED_CONTENT_TYPES = [...ALLOWED_IMAGE_TYPES, ...ALLOWED_VIDEO_TYPES] as const;

export const uploadRequestSchema = z.object({
  device_id: z.string().min(1).max(64),
  file_type: z.enum(['image', 'video']),
  content_type: z.enum(ALLOWED_CONTENT_TYPES),
}).refine(
  (data) => {
    if (data.file_type === 'image') {
      return (ALLOWED_IMAGE_TYPES as readonly string[]).includes(data.content_type);
    }
    return (ALLOWED_VIDEO_TYPES as readonly string[]).includes(data.content_type);
  },
  { message: 'content_type does not match file_type', path: ['content_type'] },
);

export const uploadCompleteSchema = z.object({
  device_id: z.string().min(1).max(64),
  media_key: z.string().min(1).max(500),
});
```

### Database Migration

```sql
-- backend/api/migrations/1709200000000_add-media-key.sql

ALTER TABLE media ADD COLUMN media_key VARCHAR(500);
ALTER TABLE media ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'pending';

CREATE INDEX idx_media_media_key ON media(media_key);
CREATE INDEX idx_media_status ON media(status);
```

## API Endpoints Summary

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/reports/:id/upload` | Generate presigned URL + create pending media record |
| POST | `/api/v1/reports/:id/upload/complete` | Verify S3 upload, transition to processing |
| GET | `/api/v1/reports/:id/media/status` | Poll for processing completion, resolve CDN URLs |

## Testing

Two test suites cover this milestone, both using Jest with `supertest` for route tests and mock-based unit tests for models.

**`src/__tests__/routes/media-upload.test.ts`** (route integration):

*POST /upload:*
- Returns 201 with `upload_url`, `media_key`, `expires_in`
- 404 for missing report
- 403 when device doesn't own report
- 403 when report is removed
- 409 when report is already processing/active
- 403 when device is flagged
- 400 when media limit (5) exceeded
- 400 when `content_type` doesn't match `file_type`
- 400 when required fields missing

*POST /upload/complete:*
- 200 with `status: processing` on successful verification
- 404 for missing report, missing media_key
- 403 for non-owner device
- 400 when file not found in S3
- Idempotent: returns current status when already `processing` or `active`

*GET /media/status:*
- Returns empty media array when none exist
- Resolves CDN URLs and returns `active` when processed file is in media bucket
- Marks media `failed` when file vanishes from both buckets
- 404 for missing report

**`src/__tests__/models/media.test.ts`** (model unit):
- `findByReportId` returns media items
- `create` inserts and returns media record
- `deleteByReportId` returns deletion count

## Notes

### Deviations from Original Plan
- **TypeScript + ES modules** instead of JavaScript + CommonJS (`require`)
- **No controller/service layer** — route handlers call model and S3 functions directly (flat architecture)
- **Zod** for validation instead of Joi
- **Two-phase flow** (upload + complete) instead of single-request presigned URL generation bundled with report creation
- **Polling-based** status resolution instead of WebSocket/MediaConvert callback — the `GET /media/status` endpoint actively checks both S3 buckets and updates records in real time
- **No in-memory `pendingUploads` Map** — media records are persisted to PostgreSQL immediately with a `media_key` column, making the flow stateless and horizontally scalable
- **`media_key`** used as the tracking identifier instead of a separate `uploadId` / `original_key`
- **Media key structure** is `{images|videos}/{reportId}/{fileId}.{ext}` instead of `{folder}/{uploadId}.{ext}`
- **Report status gating** via `UPLOAD_ALLOWED_STATUSES` set (`pending`, `uploading`, `failed`) prevents duplicate upload flows
- **Presigned URL TTL** is 15 minutes instead of 1 hour
- **Thumbnail detection** is convention-based (`_thumb.jpg` suffix) checked via `HeadObject`, not via a MediaConvert callback
- **`webp` and `webm`** added as allowed content types beyond the original `mp4`, `quicktime`, `jpeg`, `png`
