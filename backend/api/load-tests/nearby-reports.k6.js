import http from 'k6/http';
import { check, sleep } from 'k6';

const API_URL = __ENV.API_URL || 'http://localhost:3000';
const NYC_CENTER = { lat: 40.7128, lng: -74.006 };
const JITTER = 0.05;

export const options = {
  stages: [
    { duration: '30s', target: 50 },
    { duration: '1m', target: 100 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed: ['rate<0.01'],
  },
};

export default function () {
  const lat = (NYC_CENTER.lat + (Math.random() - 0.5) * 2 * JITTER).toFixed(6);
  const lng = (NYC_CENTER.lng + (Math.random() - 0.5) * 2 * JITTER).toFixed(6);
  const res = http.get(`${API_URL}/api/v1/reports?lat=${lat}&lng=${lng}&radius=5000`, {
    headers: { 'User-Agent': 'k6-load-test/1.0', 'Accept': 'application/json' },
  });
  check(res, {
    'status is 200': (r) => r.status === 200,
    'response has data array': (r) => { try { return Array.isArray(JSON.parse(r.body).data); } catch { return false; } },
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
  sleep(1);
}
