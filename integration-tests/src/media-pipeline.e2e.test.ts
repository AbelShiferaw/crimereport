import fs from 'fs';
import path from 'path';
import request from 'supertest';
import axios from 'axios';
import { io, Socket } from 'socket.io-client';

const API_URL = process.env.API_URL;
const WS_URL = process.env.WS_URL ?? API_URL?.replace(/^http/, 'ws');

if (!API_URL || !WS_URL) {
  throw new Error(
    'API_URL (and optionally WS_URL) env vars required for E2E media pipeline tests',
  );
}

const UA = 'CrimeReport-E2EMediaTests/1.0';
const get = (p: string) => request(API_URL!).get(p).set('User-Agent', UA);
const post = (p: string) => request(API_URL!).post(p).set('User-Agent', UA);

const TEST_LAT = 40.7128;
const TEST_LNG = -74.006;

const FIXTURES_DIR = path.resolve(__dirname, '..', 'fixtures');
const IMAGE_FIXTURE = path.join(FIXTURES_DIR, 'test-image.jpg');
const VIDEO_FIXTURE = path.join(FIXTURES_DIR, 'test-video.mp4');

function testDeviceId(): string {
  return `e2e-media-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

async function connectWs(deviceId: string): Promise<Socket> {
  const ws = io(WS_URL!, {
    auth: { deviceId },
    transports: ['websocket'],
  });
  await new Promise<void>((resolve, reject) => {
    ws.on('connect', () => resolve());
    ws.on('connect_error', (err) => reject(err));
  });
  return ws;
}

async function waitForTerminalStatus(
  reportId: string,
  maxSeconds: number,
): Promise<string> {
  const deadline = Date.now() + maxSeconds * 1000;
  while (Date.now() < deadline) {
    const res = await get(`/api/v1/reports/${reportId}/media/status`);
    if (
      res.status === 200 &&
      (res.body.status === 'active' || res.body.status === 'failed')
    ) {
      return res.body.status;
    }
    await new Promise((r) => setTimeout(r, 3000));
  }
  throw new Error(
    `report ${reportId} did not reach terminal status within ${maxSeconds}s`,
  );
}

async function createReport(deviceId: string): Promise<string> {
  const res = await post('/api/v1/reports').send({
    device_id: deviceId,
    type: 'theft',
    description: 'E2E media pipeline test report',
    lat: TEST_LAT,
    lng: TEST_LNG,
    address: 'E2E test address',
  });
  expect(res.status).toBe(201);
  expect(res.body.status).toBe('pending');
  return res.body.id as string;
}

async function uploadMedia(opts: {
  deviceId: string;
  reportId: string;
  filePath: string;
  fileType: 'image' | 'video';
  contentType: string;
}): Promise<void> {
  const presign = await post(`/api/v1/reports/${opts.reportId}/upload`).send({
    device_id: opts.deviceId,
    file_type: opts.fileType,
    content_type: opts.contentType,
  });
  expect(presign.status).toBe(201);
  expect(presign.body.upload_url).toBeTruthy();
  expect(presign.body.media_key).toBeTruthy();

  const bytes = fs.readFileSync(opts.filePath);
  const putRes = await axios.put(presign.body.upload_url, bytes, {
    headers: {
      'Content-Type': opts.contentType,
      'Content-Length': bytes.length,
    },
    maxBodyLength: Infinity,
    maxContentLength: Infinity,
  });
  expect(putRes.status).toBeGreaterThanOrEqual(200);
  expect(putRes.status).toBeLessThan(300);

  const complete = await post(
    `/api/v1/reports/${opts.reportId}/upload/complete`,
  ).send({
    device_id: opts.deviceId,
    media_key: presign.body.media_key,
  });
  expect(complete.status).toBe(200);
}

function awaitReportNew(
  ws: Socket,
  timeoutMs: number,
): Promise<{ id: string }> {
  const broadcast = new Promise<{ id: string }>((resolve) => {
    ws.on('report:new', (data: { id: string }) => resolve(data));
  });
  return Promise.race([
    broadcast,
    new Promise<{ id: string }>((_, reject) =>
      setTimeout(
        () => reject(new Error(`no report:new broadcast within ${timeoutMs}ms`)),
        timeoutMs,
      ),
    ),
  ]);
}

describe('E2E Media Pipeline', () => {
  describe('Image upload end-to-end', () => {
    let ws: Socket | undefined;

    afterEach(() => {
      if (ws && ws.connected) {
        ws.disconnect();
      }
      ws = undefined;
    });

    it(
      'uploads an image, processes via Step Functions, serves via CloudFront, and broadcasts report:new',
      async () => {
        const deviceId = testDeviceId();
        ws = await connectWs(deviceId);
        ws.emit('subscribe:location', { lat: TEST_LAT, lng: TEST_LNG });

        const reportId = await createReport(deviceId);
        const broadcastPromise = awaitReportNew(ws, 90_000);

        await uploadMedia({
          deviceId,
          reportId,
          filePath: IMAGE_FIXTURE,
          fileType: 'image',
          contentType: 'image/jpeg',
        });

        const status = await waitForTerminalStatus(reportId, 90);
        expect(status).toBe('active');

        const reportRes = await get(`/api/v1/reports/${reportId}`);
        expect(reportRes.status).toBe(200);
        expect(reportRes.body.status).toBe('active');
        expect(Array.isArray(reportRes.body.media)).toBe(true);
        expect(reportRes.body.media.length).toBeGreaterThan(0);
        const mediaUrl: string = reportRes.body.media[0].url;
        expect(typeof mediaUrl).toBe('string');
        expect(mediaUrl.length).toBeGreaterThan(0);

        const mediaGet = await axios.get(mediaUrl, {
          responseType: 'arraybuffer',
          validateStatus: () => true,
        });
        expect(mediaGet.status).toBe(200);

        const event = await broadcastPromise;
        expect(event.id).toBe(reportId);
      },
      120_000,
    );
  });

  describe('Video upload end-to-end', () => {
    let ws: Socket | undefined;

    afterEach(() => {
      if (ws && ws.connected) {
        ws.disconnect();
      }
      ws = undefined;
    });

    it(
      'uploads a video, transcodes via MediaConvert, serves via CloudFront, and broadcasts report:new',
      async () => {
        const deviceId = testDeviceId();
        ws = await connectWs(deviceId);
        ws.emit('subscribe:location', { lat: TEST_LAT, lng: TEST_LNG });

        const reportId = await createReport(deviceId);
        const broadcastPromise = awaitReportNew(ws, 300_000);

        await uploadMedia({
          deviceId,
          reportId,
          filePath: VIDEO_FIXTURE,
          fileType: 'video',
          contentType: 'video/mp4',
        });

        const status = await waitForTerminalStatus(reportId, 300);
        expect(status).toBe('active');

        const reportRes = await get(`/api/v1/reports/${reportId}`);
        expect(reportRes.status).toBe(200);
        expect(reportRes.body.status).toBe('active');
        expect(Array.isArray(reportRes.body.media)).toBe(true);
        expect(reportRes.body.media.length).toBeGreaterThan(0);

        const media = reportRes.body.media[0];
        expect(typeof media.url).toBe('string');
        expect(media.url.length).toBeGreaterThan(0);
        expect(typeof media.thumbnail_url).toBe('string');
        expect(media.thumbnail_url.length).toBeGreaterThan(0);

        const mediaGet = await axios.get(media.url, {
          responseType: 'arraybuffer',
          validateStatus: () => true,
        });
        expect(mediaGet.status).toBe(200);

        const thumbGet = await axios.get(media.thumbnail_url, {
          responseType: 'arraybuffer',
          validateStatus: () => true,
        });
        expect(thumbGet.status).toBe(200);

        const event = await broadcastPromise;
        expect(event.id).toBe(reportId);
      },
      300_000,
    );
  });

  describe('Invalid content type is rejected', () => {
    it('returns 400 when requesting a presigned URL with a non-allowlisted content_type', async () => {
      const deviceId = testDeviceId();
      const reportId = await createReport(deviceId);

      const res = await post(`/api/v1/reports/${reportId}/upload`).send({
        device_id: deviceId,
        file_type: 'image',
        content_type: 'image/gif',
      });

      expect(res.status).toBe(400);
    });
  });
});
