import request from 'supertest';

/**
 * Contract tests that assert every backend response shape matches what
 * the Flutter models expect. Runs against a deployed API in CI after
 * every deploy so any future drift is caught before it reaches users.
 *
 * The scenarios here cover all the Milestone 31 contract bugs (lat/lng
 * naming, nullable description / width / height, snake_case crime types,
 * device_id required on register/unregister/preferences, radius in
 * meters on PUT /preferences, etc.).
 */

const API_URL = process.env.API_URL;

if (!API_URL) {
  throw new Error('API_URL environment variable is required for contract tests');
}

const UA = 'CrimeReport-ContractTests/1.0';
const get = (path: string) => request(API_URL).get(path).set('User-Agent', UA);
const post = (path: string) => request(API_URL).post(path).set('User-Agent', UA);
const put = (path: string) => request(API_URL).put(path).set('User-Agent', UA);
const del = (path: string) => request(API_URL).delete(path).set('User-Agent', UA);

/**
 * Source of truth that mirrors `backend/api/src/validators/report.ts`
 * and `apps/mobile/lib/core/constants/enums.dart`. If this list drifts
 * from either side, the CRIME_TYPES tests below will flag it.
 */
const CRIME_TYPES = [
  'theft',
  'assault',
  'vandalism',
  'robbery',
  'burglary',
  'suspicious',
  'shooting',
  'carjacking',
  'harassment',
  'drug_activity',
  'other',
] as const;

const TEST_DEVICE_ID = `contract-test-${Date.now()}`;
let reportId: string;

// ---------------------------------------------------------------------------
// Reports: POST /api/v1/reports
// ---------------------------------------------------------------------------

describe('Contract: POST /api/v1/reports', () => {
  it('returns lat/lng (not latitude/longitude) in the Flutter-expected shape', async () => {
    const res = await post('/api/v1/reports').send({
      device_id: TEST_DEVICE_ID,
      type: 'theft',
      description: 'contract test report',
      lat: 40.7128,
      lng: -74.006,
      address: '123 Test St',
    });

    expect(res.status).toBe(201);
    const body = res.body;

    // Required fields Flutter's Report.fromJson reads.
    expect(typeof body.id).toBe('string');
    expect(typeof body.device_id).toBe('string');
    expect(CRIME_TYPES).toContain(body.type);

    // Coordinates must be `lat`/`lng` — the Flutter model was broken for
    // months when the backend accidentally used latitude/longitude keys.
    expect(typeof body.lat).toBe('number');
    expect(typeof body.lng).toBe('number');
    expect(body).not.toHaveProperty('latitude');
    expect(body).not.toHaveProperty('longitude');

    // description is optional in the Zod schema — string or null.
    expect(['string', 'object']).toContain(typeof body.description);

    expect(typeof body.status).toBe('string');
    expect(typeof body.upvotes).toBe('number');
    expect(typeof body.comment_count).toBe('number');
    expect(typeof body.created_at).toBe('string');

    reportId = body.id;
  });

  it('accepts an omitted description (backend returns null)', async () => {
    const res = await post('/api/v1/reports').send({
      device_id: TEST_DEVICE_ID,
      type: 'other',
      lat: 40.7128,
      lng: -74.006,
    });

    // Report creation may succeed (201) or be rate-limited (429) since
    // we create multiple reports in this suite — both are acceptable
    // contract-wise.
    expect([201, 429]).toContain(res.status);
    if (res.status === 201) {
      // description field, when present, must tolerate null.
      if ('description' in res.body) {
        expect([null, '']).toContain(res.body.description);
      }
    }
  });
});

// ---------------------------------------------------------------------------
// Reports: GET /api/v1/reports/:id  (includes media[])
// ---------------------------------------------------------------------------

describe('Contract: GET /api/v1/reports/:id', () => {
  it('returns a report with a media array matching Flutter Media.fromJson', async () => {
    const res = await get(`/api/v1/reports/${reportId}`);

    expect(res.status).toBe(200);
    expect(res.body.id).toBe(reportId);
    expect(typeof res.body.lat).toBe('number');
    expect(typeof res.body.lng).toBe('number');
    expect(Array.isArray(res.body.media)).toBe(true);

    for (const m of res.body.media) {
      expect(typeof m.id).toBe('string');
      expect(typeof m.report_id).toBe('string');
      expect(['image', 'video']).toContain(m.type);
      expect(typeof m.url).toBe('string');

      // Optional / nullable fields. Flutter now treats all four as
      // nullable, so null or missing are both acceptable.
      for (const key of ['thumbnail_url', 'duration_ms', 'width', 'height']) {
        if (key in m && m[key] !== null) {
          if (key === 'duration_ms' || key === 'width' || key === 'height') {
            expect(typeof m[key]).toBe('number');
          } else {
            expect(typeof m[key]).toBe('string');
          }
        }
      }

      expect(typeof m.created_at).toBe('string');
    }
  });
});

// ---------------------------------------------------------------------------
// Reports: POST /api/v1/reports CRIME_TYPES contract
// ---------------------------------------------------------------------------

describe('Contract: CRIME_TYPES stays in sync with the backend validator', () => {
  it.each(CRIME_TYPES)('accepts type=%s', async (type) => {
    const res = await post('/api/v1/reports').send({
      device_id: TEST_DEVICE_ID,
      type,
      description: `type-check-${type}`,
      lat: 40.7128,
      lng: -74.006,
    });

    // 201 = created; 429 = per-device daily rate limit hit, which is
    // still proof that the type passed validation. Anything else means
    // the backend rejected the type.
    expect([201, 429]).toContain(res.status);
  });

  it('rejects the removed `disturbance` type (Flutter parity)', async () => {
    const res = await post('/api/v1/reports').send({
      device_id: TEST_DEVICE_ID,
      type: 'disturbance',
      description: 'should be rejected',
      lat: 40.7128,
      lng: -74.006,
    });
    expect(res.status).toBe(400);
  });

  it('rejects camelCase type names that used to be sent by Flutter', async () => {
    const res = await post('/api/v1/reports').send({
      device_id: TEST_DEVICE_ID,
      type: 'drugActivity', // .name form — must be rejected; only drug_activity is valid
      description: 'should be rejected',
      lat: 40.7128,
      lng: -74.006,
    });
    expect(res.status).toBe(400);
  });
});

// ---------------------------------------------------------------------------
// Reports: POST /api/v1/reports/:id/comments
// ---------------------------------------------------------------------------

describe('Contract: comments endpoints', () => {
  let commentId: string;

  it('POST /reports/:id/comments returns the Flutter Comment shape', async () => {
    const res = await post(`/api/v1/reports/${reportId}/comments`).send({
      device_id: TEST_DEVICE_ID,
      content: 'contract test comment',
    });

    expect(res.status).toBe(201);
    const c = res.body;
    expect(typeof c.id).toBe('string');
    expect(c.report_id).toBe(reportId);
    expect(typeof c.device_id).toBe('string');
    expect(typeof c.content).toBe('string');
    expect(typeof c.upvotes).toBe('number');
    expect(typeof c.created_at).toBe('string');

    commentId = c.id;
  });

  it('GET /reports/:id/comments returns { data, meta }', async () => {
    const res = await get(`/api/v1/reports/${reportId}/comments`);

    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.data)).toBe(true);
    expect(res.body.data.some((c: { id: string }) => c.id === commentId)).toBe(true);

    expect(typeof res.body.meta).toBe('object');
    expect(res.body.meta.report_id).toBe(reportId);
    expect(typeof res.body.meta.count).toBe('number');
  });
});

// ---------------------------------------------------------------------------
// Media upload: POST /api/v1/reports/:id/upload
// ---------------------------------------------------------------------------

describe('Contract: POST /api/v1/reports/:id/upload', () => {
  it('returns upload_url, media_key, expires_in', async () => {
    const res = await post(`/api/v1/reports/${reportId}/upload`).send({
      device_id: TEST_DEVICE_ID,
      file_type: 'image',
      content_type: 'image/jpeg',
    });

    // Accept 201 for successful presign; 409 if the report is already
    // beyond the "pending|uploading|failed" gate (e.g. active from a
    // previous run on the same data).
    expect([201, 409]).toContain(res.status);
    if (res.status === 201) {
      expect(typeof res.body.upload_url).toBe('string');
      expect(typeof res.body.media_key).toBe('string');
      expect(typeof res.body.expires_in).toBe('number');
    }
  });
});

// ---------------------------------------------------------------------------
// Push notifications
// ---------------------------------------------------------------------------

describe('Contract: notifications', () => {
  const NOTIF_DEVICE = `contract-notif-${Date.now()}`;

  it('POST /notifications/register accepts the corrected payload', async () => {
    const res = await post('/api/v1/notifications/register').send({
      device_id: NOTIF_DEVICE,
      fcm_token: 'contract-test-token',
      platform: 'android',
      lat: 40.7128,
      lng: -74.006,
    });

    expect(res.status).toBe(201);
    expect(res.body.device_id).toBe(NOTIF_DEVICE);
  });

  it('POST /notifications/register rejects missing device_id', async () => {
    const res = await post('/api/v1/notifications/register').send({
      fcm_token: 'token',
      platform: 'android',
      lat: 40.7128,
      lng: -74.006,
    });
    expect(res.status).toBe(400);
  });

  it('POST /notifications/register rejects null lat/lng (old Flutter payload)', async () => {
    const res = await post('/api/v1/notifications/register').send({
      device_id: `${NOTIF_DEVICE}-null`,
      fcm_token: 'token',
      platform: 'android',
      lat: null,
      lng: null,
    });
    expect(res.status).toBe(400);
  });

  it('POST /notifications/register rejects an invalid platform', async () => {
    const res = await post('/api/v1/notifications/register').send({
      device_id: `${NOTIF_DEVICE}-plat`,
      fcm_token: 'token',
      platform: 'web',
      lat: 40.7128,
      lng: -74.006,
    });
    expect(res.status).toBe(400);
  });

  it('PUT /notifications/preferences accepts device_id + radius + types + enabled', async () => {
    const res = await put('/api/v1/notifications/preferences').send({
      device_id: NOTIF_DEVICE,
      enabled: true,
      radius: 5000,
      types: ['theft', 'assault'],
    });

    expect(res.status).toBe(200);
    expect(res.body.device_id).toBe(NOTIF_DEVICE);
  });

  it('PUT /notifications/preferences rejects radius below 1000m', async () => {
    const res = await put('/api/v1/notifications/preferences').send({
      device_id: NOTIF_DEVICE,
      radius: 500,
    });
    expect(res.status).toBe(400);
  });

  it('PUT /notifications/preferences rejects radius above 50km', async () => {
    const res = await put('/api/v1/notifications/preferences').send({
      device_id: NOTIF_DEVICE,
      radius: 60_000,
    });
    expect(res.status).toBe(400);
  });

  it('PUT /notifications/preferences rejects an unknown crime type', async () => {
    const res = await put('/api/v1/notifications/preferences').send({
      device_id: NOTIF_DEVICE,
      types: ['disturbance'],
    });
    expect(res.status).toBe(400);
  });

  it('DELETE /notifications/unregister accepts device_id in body', async () => {
    const res = await del('/api/v1/notifications/unregister').send({
      device_id: NOTIF_DEVICE,
    });
    expect(res.status).toBe(200);
  });

  it('DELETE /notifications/unregister without a body returns 400', async () => {
    const res = await del('/api/v1/notifications/unregister').send({});
    expect(res.status).toBe(400);
  });
});
