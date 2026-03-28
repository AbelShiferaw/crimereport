import http from 'http';
import { Server as SocketServer } from 'socket.io';
import { io as ioClient, Socket as ClientSocket } from 'socket.io-client';
import { initSocket, shutdownSocket } from '../../lib/socket';

jest.mock('../../lib/logger', () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn(), debug: jest.fn() },
}));

jest.mock('redis', () => ({
  createClient: jest.fn(() => ({
    connect: jest.fn().mockRejectedValue(new Error('no redis in test')),
    duplicate: jest.fn(function (this: any) { return this; }),
    on: jest.fn(),
  })),
}));

let httpServer: http.Server;
let serverSocket: SocketServer;
let port: number;

function connectClient(auth: Record<string, unknown> = { deviceId: 'test-device' }): ClientSocket {
  return ioClient(`http://localhost:${port}`, { transports: ['websocket'], auth, forceNew: true });
}

function waitForConnect(socket: ClientSocket, ms = 3000): Promise<void> {
  return new Promise((resolve, reject) => {
    if (socket.connected) return resolve();
    const t = setTimeout(() => reject(new Error('timeout')), ms);
    socket.once('connect', () => { clearTimeout(t); resolve(); });
    socket.once('connect_error', (e) => { clearTimeout(t); reject(e); });
  });
}

function waitForError(socket: ClientSocket, ms = 3000): Promise<Error> {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('no error received')), ms);
    socket.once('connect_error', (e) => { clearTimeout(t); resolve(e); });
  });
}

beforeAll((done) => {
  httpServer = http.createServer();
  serverSocket = initSocket(httpServer);
  httpServer.listen(0, () => {
    const addr = httpServer.address();
    port = typeof addr === 'object' && addr ? addr.port : 0;
    done();
  });
});

afterAll(async () => {
  await shutdownSocket();
  await new Promise<void>((resolve) => httpServer.close(() => resolve()));
});

describe('WebSocket auth middleware', () => {
  it('rejects connection without deviceId', async () => {
    const client = connectClient({});
    const err = await waitForError(client);
    expect(err.message).toContain('Invalid device ID');
    client.disconnect();
  });
  it('rejects connection with empty deviceId', async () => {
    const client = connectClient({ deviceId: '' });
    const err = await waitForError(client);
    expect(err.message).toContain('Invalid device ID');
    client.disconnect();
  });
  it('accepts connection with valid deviceId', async () => {
    const client = connectClient({ deviceId: 'valid-device-123' });
    await waitForConnect(client);
    expect(client.connected).toBe(true);
    client.disconnect();
  });
});

describe('WebSocket subscribe:location', () => {
  it('client joins location room', async () => {
    const client = connectClient({ deviceId: 'loc-device' });
    await waitForConnect(client);
    client.emit('subscribe:location', { lat: 40.71, lng: -74.0 });
    await new Promise((r) => setTimeout(r, 100));
    expect(serverSocket.sockets.adapter.rooms.has('location:40.7:-74.0')).toBe(true);
    client.disconnect();
  });
  it('ignores invalid lat/lng data', async () => {
    const client = connectClient({ deviceId: 'invalid-loc' });
    await waitForConnect(client);
    client.emit('subscribe:location', { lat: 'abc', lng: 'def' });
    await new Promise((r) => setTimeout(r, 100));
    expect(client.connected).toBe(true);
    client.disconnect();
  });
});

describe('WebSocket subscribe:report / unsubscribe:report', () => {
  it('joins and leaves a report room', async () => {
    const client = connectClient({ deviceId: 'report-device' });
    await waitForConnect(client);
    client.emit('subscribe:report', 'report-abc');
    await new Promise((r) => setTimeout(r, 100));
    expect(serverSocket.sockets.adapter.rooms.has('report:report-abc')).toBe(true);
    client.emit('unsubscribe:report', 'report-abc');
    await new Promise((r) => setTimeout(r, 100));
    expect(serverSocket.sockets.adapter.rooms.get('report:report-abc')?.size ?? 0).toBe(0);
    client.disconnect();
  });
});

describe('WebSocket connection limit', () => {
  it('rejects more than 3 connections per device', async () => {
    const deviceId = 'limited-device';
    const clients: ClientSocket[] = [];
    for (let i = 0; i < 3; i++) {
      const c = connectClient({ deviceId });
      await waitForConnect(c);
      clients.push(c);
    }
    const fourth = connectClient({ deviceId });
    const err = await waitForError(fourth);
    expect(err.message).toContain('Too many concurrent connections');
    fourth.disconnect();
    for (const c of clients) c.disconnect();
    await new Promise((r) => setTimeout(r, 200));
  });
});
