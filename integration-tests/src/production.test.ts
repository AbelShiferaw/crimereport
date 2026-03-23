import request from 'supertest';

const API_URL = process.env.API_URL;

if (!API_URL) {
  throw new Error('API_URL environment variable is required for integration tests');
}

const UA = 'CrimeReport-IntegrationTests/1.0';
const api = () => request(API_URL).set('User-Agent', UA);

const TEST_DEVICE_ID = `integration-test-${Date.now()}`;

let createdReportId: string;

describe('Health endpoints', () => {
  it('GET /health returns 200 with status ok', async () => {
    const res = await api().get('/health');

    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
    expect(res.body).toHaveProperty('uptime');
    expect(res.body).toHaveProperty('timestamp');
  });

  it('GET /health/ready returns 200 with all checks connected', async () => {
    const res = await api().get('/health/ready');

    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
    expect(res.body.checks.db).toBe('connected');
    expect(res.body.checks.redis).toBe('connected');
  });
});

describe('API info', () => {
  it('GET /api/v1 returns API name and version', async () => {
    const res = await api().get('/api/v1');

    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('name');
    expect(res.body).toHaveProperty('version');
  });
});

describe('Reports CRUD', () => {
  it('POST /api/v1/reports creates a report', async () => {
    const res = await api()
      .post('/api/v1/reports')
      .send({
        device_id: TEST_DEVICE_ID,
        type: 'theft',
        description: 'Integration test report',
        lat: 40.7128,
        lng: -74.006,
        address: '123 Test St',
      });

    expect(res.status).toBe(201);
    expect(res.body).toHaveProperty('id');
    expect(res.body.type).toBe('theft');
    expect(res.body.description).toBe('Integration test report');
    expect(res.body.status).toBe('pending');

    createdReportId = res.body.id;
  });

  it('GET /api/v1/reports/:id returns the created report', async () => {
    const res = await api().get(`/api/v1/reports/${createdReportId}`);

    expect(res.status).toBe(200);
    expect(res.body.id).toBe(createdReportId);
    expect(res.body.type).toBe('theft');
  });

  it('GET /api/v1/reports returns nearby reports', async () => {
    const res = await api()
      .get('/api/v1/reports')
      .query({ lat: 40.7128, lng: -74.006, radius: 5000 });

    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('data');
    expect(res.body).toHaveProperty('meta');
    expect(Array.isArray(res.body.data)).toBe(true);
  });

  it('GET /api/v1/reports/:id returns 404 for non-existent report', async () => {
    const fakeId = '00000000-0000-0000-0000-000000000000';
    const res = await api().get(`/api/v1/reports/${fakeId}`);

    expect(res.status).toBe(404);
  });
});

describe('Validation', () => {
  it('POST /api/v1/reports with bad body returns 400', async () => {
    const res = await api()
      .post('/api/v1/reports')
      .send({ type: 'invalid_type' });

    expect(res.status).toBe(400);
  });

  it('GET /api/v1/reports with missing lat/lng returns 400', async () => {
    const res = await api().get('/api/v1/reports');

    expect(res.status).toBe(400);
  });
});

describe('Comments', () => {
  it('POST /api/v1/reports/:id/comments creates a comment', async () => {
    const res = await api()
      .post(`/api/v1/reports/${createdReportId}/comments`)
      .send({
        device_id: TEST_DEVICE_ID,
        content: 'Integration test comment',
      });

    expect(res.status).toBe(201);
    expect(res.body).toHaveProperty('id');
    expect(res.body.content).toBe('Integration test comment');
  });

  it('GET /api/v1/reports/:id/comments returns comments', async () => {
    const res = await api()
      .get(`/api/v1/reports/${createdReportId}/comments`);

    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('data');
    expect(res.body.data.length).toBeGreaterThanOrEqual(1);
    expect(res.body.data[0].content).toBe('Integration test comment');
  });
});

describe('Upvotes', () => {
  it('POST /api/v1/reports/:id/upvote toggles upvote', async () => {
    const res = await api()
      .post(`/api/v1/reports/${createdReportId}/upvote`)
      .send({ device_id: TEST_DEVICE_ID });

    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('upvoted');
    expect(res.body).toHaveProperty('upvotes');
  });
});

describe('Comment flagging', () => {
  let commentId: string;

  beforeAll(async () => {
    const res = await api()
      .post(`/api/v1/reports/${createdReportId}/comments`)
      .send({
        device_id: TEST_DEVICE_ID,
        content: 'Comment to flag',
      });
    commentId = res.body.id;
  });

  it('POST /api/v1/comments/:id/flag flags a comment', async () => {
    const res = await api()
      .post(`/api/v1/comments/${commentId}/flag`)
      .send({ device_id: TEST_DEVICE_ID });

    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('flagged', true);
  });
});

describe('Media upload', () => {
  it('POST /api/v1/reports/:id/upload returns a presigned URL', async () => {
    const res = await api()
      .post(`/api/v1/reports/${createdReportId}/upload`)
      .send({
        device_id: TEST_DEVICE_ID,
        file_type: 'image',
        content_type: 'image/jpeg',
      });

    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('upload_url');
    expect(res.body).toHaveProperty('media_key');
  });

  it('GET /api/v1/reports/:id/media/status returns media status', async () => {
    const res = await api()
      .get(`/api/v1/reports/${createdReportId}/media/status`);

    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('media');
    expect(Array.isArray(res.body.media)).toBe(true);
  });
});

describe('Push notifications', () => {
  it('POST /api/v1/notifications/register registers a device', async () => {
    const res = await api()
      .post('/api/v1/notifications/register')
      .send({
        device_id: TEST_DEVICE_ID,
        fcm_token: 'integration-test-token-fake',
        platform: 'android',
        lat: 40.7128,
        lng: -74.006,
      });

    expect(res.status).toBe(201);
    expect(res.body).toHaveProperty('device_id', TEST_DEVICE_ID);
  });

  it('PUT /api/v1/notifications/preferences updates preferences', async () => {
    const res = await api()
      .put('/api/v1/notifications/preferences')
      .send({
        device_id: TEST_DEVICE_ID,
        enabled: true,
        radius: 10000,
        types: ['theft', 'assault'],
      });

    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('device_id', TEST_DEVICE_ID);
  });

  it('DELETE /api/v1/notifications/unregister removes device', async () => {
    const res = await api()
      .delete('/api/v1/notifications/unregister')
      .send({ device_id: TEST_DEVICE_ID });

    expect(res.status).toBe(200);
  });
});
