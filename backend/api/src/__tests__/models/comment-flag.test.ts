import * as commentFlagModel from '../../models/comment-flag';
import * as db from '../../lib/db';

jest.mock('../../lib/db');

const mockGetClient = db.getClient as jest.MockedFunction<typeof db.getClient>;
const mockQuery = db.query as jest.MockedFunction<typeof db.query>;

function createMockClient() {
  const mockClient = {
    query: jest.fn(),
    release: jest.fn(),
  };
  return mockClient;
}

describe('comment-flag model', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('flag', () => {
    it('adds flag when it does not exist and returns true', async () => {
      const client = createMockClient();
      mockGetClient.mockResolvedValueOnce(client as any);

      client.query
        .mockResolvedValueOnce(undefined) // BEGIN
        .mockResolvedValueOnce({ rows: [{ id: 'c1' }] }) // SELECT FOR UPDATE (lock comment)
        .mockResolvedValueOnce({ rows: [] }) // SELECT flag (not found)
        .mockResolvedValueOnce(undefined) // INSERT flag
        .mockResolvedValueOnce(undefined) // UPDATE flag_count +1
        .mockResolvedValueOnce(undefined); // COMMIT

      const result = await commentFlagModel.flag('c1', 'd1');

      expect(result).toBe(true);
      expect(client.query).toHaveBeenCalledWith('BEGIN');
      expect(client.query).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO comment_flags'),
        ['c1', 'd1'],
      );
      expect(client.query).toHaveBeenCalledWith('COMMIT');
      expect(client.release).toHaveBeenCalled();
    });

    it('returns false when device already flagged this comment', async () => {
      const client = createMockClient();
      mockGetClient.mockResolvedValueOnce(client as any);

      client.query
        .mockResolvedValueOnce(undefined) // BEGIN
        .mockResolvedValueOnce({ rows: [{ id: 'c1' }] }) // SELECT FOR UPDATE
        .mockResolvedValueOnce({ rows: [{ comment_id: 'c1' }] }) // SELECT flag (found)
        .mockResolvedValueOnce(undefined); // COMMIT

      const result = await commentFlagModel.flag('c1', 'd1');

      expect(result).toBe(false);
      expect(client.query).not.toHaveBeenCalledWith(
        expect.stringContaining('INSERT'),
        expect.anything(),
      );
      expect(client.query).toHaveBeenCalledWith('COMMIT');
      expect(client.release).toHaveBeenCalled();
    });

    it('rolls back on error and re-throws', async () => {
      const client = createMockClient();
      mockGetClient.mockResolvedValueOnce(client as any);

      client.query
        .mockResolvedValueOnce(undefined) // BEGIN
        .mockRejectedValueOnce(new Error('db error'));

      await expect(commentFlagModel.flag('c1', 'd1')).rejects.toThrow('db error');
      expect(client.query).toHaveBeenCalledWith('ROLLBACK');
      expect(client.release).toHaveBeenCalled();
    });
  });

  describe('existsForDevice', () => {
    it('returns true when flag exists', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [{ '?column?': 1 }], rowCount: 1 } as any);

      const result = await commentFlagModel.existsForDevice('c1', 'd1');

      expect(result).toBe(true);
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('FROM comment_flags'),
        ['c1', 'd1'],
      );
    });

    it('returns false when flag does not exist', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      const result = await commentFlagModel.existsForDevice('c1', 'd1');

      expect(result).toBe(false);
    });

    it('uses comment_id = $1 AND device_id = $2 in query', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      await commentFlagModel.existsForDevice('comment-xyz', 'device-abc');

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('comment_id = $1 AND device_id = $2'),
        ['comment-xyz', 'device-abc'],
      );
    });
  });

  describe('flag — flag_count increment', () => {
    it('increments flag_count when a new flag is added', async () => {
      const client = createMockClient();
      mockGetClient.mockResolvedValueOnce(client as any);

      client.query
        .mockResolvedValueOnce(undefined) // BEGIN
        .mockResolvedValueOnce({ rows: [{ id: 'c1' }] }) // SELECT FOR UPDATE
        .mockResolvedValueOnce({ rows: [] }) // SELECT flag (not found)
        .mockResolvedValueOnce(undefined) // INSERT flag
        .mockResolvedValueOnce(undefined) // UPDATE flag_count +1
        .mockResolvedValueOnce(undefined); // COMMIT

      await commentFlagModel.flag('c1', 'd1');

      const flagCountCall = client.query.mock.calls.find(
        (c: any[]) => typeof c[0] === 'string' && c[0].includes('flag_count'),
      );
      expect(flagCountCall).toBeDefined();
      expect(flagCountCall![0]).toContain('flag_count = flag_count + 1');
    });

    it('does NOT increment flag_count when flag already exists (duplicate)', async () => {
      const client = createMockClient();
      mockGetClient.mockResolvedValueOnce(client as any);

      client.query
        .mockResolvedValueOnce(undefined) // BEGIN
        .mockResolvedValueOnce({ rows: [{ id: 'c1' }] }) // SELECT FOR UPDATE
        .mockResolvedValueOnce({ rows: [{ comment_id: 'c1' }] }) // SELECT flag (found)
        .mockResolvedValueOnce(undefined); // COMMIT

      await commentFlagModel.flag('c1', 'd1');

      const flagCountCall = client.query.mock.calls.find(
        (c: any[]) => typeof c[0] === 'string' && c[0].includes('flag_count'),
      );
      expect(flagCountCall).toBeUndefined();
    });
  });

  describe('flag — locks comment row', () => {
    it('acquires SELECT FOR UPDATE lock on the comment', async () => {
      const client = createMockClient();
      mockGetClient.mockResolvedValueOnce(client as any);

      client.query
        .mockResolvedValueOnce(undefined) // BEGIN
        .mockResolvedValueOnce({ rows: [{ id: 'c1' }] }) // SELECT FOR UPDATE
        .mockResolvedValueOnce({ rows: [] }) // flag check
        .mockResolvedValueOnce(undefined) // INSERT
        .mockResolvedValueOnce(undefined) // UPDATE flag_count
        .mockResolvedValueOnce(undefined); // COMMIT

      await commentFlagModel.flag('c1', 'd1');

      expect(client.query).toHaveBeenCalledWith(
        expect.stringContaining('FOR UPDATE'),
        ['c1'],
      );
    });
  });

  describe('flag — client release', () => {
    it('releases client on success', async () => {
      const client = createMockClient();
      mockGetClient.mockResolvedValueOnce(client as any);

      client.query
        .mockResolvedValueOnce(undefined)
        .mockResolvedValueOnce({ rows: [{ id: 'c1' }] })
        .mockResolvedValueOnce({ rows: [] })
        .mockResolvedValueOnce(undefined)
        .mockResolvedValueOnce(undefined)
        .mockResolvedValueOnce(undefined);

      await commentFlagModel.flag('c1', 'd1');
      expect(client.release).toHaveBeenCalledTimes(1);
    });

    it('releases client on failure', async () => {
      const client = createMockClient();
      mockGetClient.mockResolvedValueOnce(client as any);

      client.query
        .mockResolvedValueOnce(undefined)
        .mockRejectedValueOnce(new Error('db failure'));

      await expect(commentFlagModel.flag('c1', 'd1')).rejects.toThrow('db failure');
      expect(client.release).toHaveBeenCalledTimes(1);
    });
  });

  describe('query error handling', () => {
    it('propagates db errors from existsForDevice', async () => {
      mockQuery.mockRejectedValueOnce(new Error('connection error'));
      await expect(commentFlagModel.existsForDevice('c1', 'd1')).rejects.toThrow('connection error');
    });
  });
});
