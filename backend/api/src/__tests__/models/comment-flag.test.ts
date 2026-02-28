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
  });
});
