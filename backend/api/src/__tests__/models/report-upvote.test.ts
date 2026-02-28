import * as upvoteModel from '../../models/report-upvote';
import * as db from '../../lib/db';

jest.mock('../../lib/db');

const mockGetClient = db.getClient as jest.MockedFunction<typeof db.getClient>;

function createMockClient() {
  const mockClient = {
    query: jest.fn(),
    release: jest.fn(),
  };
  return mockClient;
}

describe('report-upvote model', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('toggle', () => {
    it('adds upvote when it does not exist and returns true', async () => {
      const client = createMockClient();
      mockGetClient.mockResolvedValueOnce(client as any);

      client.query
        .mockResolvedValueOnce(undefined) // BEGIN
        .mockResolvedValueOnce({ rows: [] }) // SELECT (not found)
        .mockResolvedValueOnce(undefined) // INSERT
        .mockResolvedValueOnce(undefined) // UPDATE upvotes +1
        .mockResolvedValueOnce(undefined); // COMMIT

      const result = await upvoteModel.toggle('r1', 'd1');

      expect(result).toBe(true);
      expect(client.query).toHaveBeenCalledWith('BEGIN');
      expect(client.query).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO report_upvotes'),
        ['r1', 'd1'],
      );
      expect(client.query).toHaveBeenCalledWith('COMMIT');
      expect(client.release).toHaveBeenCalled();
    });

    it('removes upvote when it already exists and returns false', async () => {
      const client = createMockClient();
      mockGetClient.mockResolvedValueOnce(client as any);

      client.query
        .mockResolvedValueOnce(undefined) // BEGIN
        .mockResolvedValueOnce({ rows: [{ report_id: 'r1' }] }) // SELECT (found)
        .mockResolvedValueOnce(undefined) // DELETE
        .mockResolvedValueOnce(undefined) // UPDATE upvotes -1
        .mockResolvedValueOnce(undefined); // COMMIT

      const result = await upvoteModel.toggle('r1', 'd1');

      expect(result).toBe(false);
      expect(client.query).toHaveBeenCalledWith(
        expect.stringContaining('DELETE FROM report_upvotes'),
        ['r1', 'd1'],
      );
      expect(client.query).toHaveBeenCalledWith('COMMIT');
      expect(client.release).toHaveBeenCalled();
    });

    it('rolls back on error and re-throws', async () => {
      const client = createMockClient();
      mockGetClient.mockResolvedValueOnce(client as any);

      client.query
        .mockResolvedValueOnce(undefined) // BEGIN
        .mockRejectedValueOnce(new Error('db error')); // SELECT fails

      await expect(upvoteModel.toggle('r1', 'd1')).rejects.toThrow('db error');
      expect(client.query).toHaveBeenCalledWith('ROLLBACK');
      expect(client.release).toHaveBeenCalled();
    });
  });

  describe('existsForDevice', () => {
    it('returns true when upvote exists', async () => {
      const client = createMockClient();
      mockGetClient.mockResolvedValueOnce(client as any);
      client.query.mockResolvedValueOnce({ rows: [{ '?column?': 1 }] });

      const result = await upvoteModel.existsForDevice('r1', 'd1');

      expect(result).toBe(true);
      expect(client.release).toHaveBeenCalled();
    });

    it('returns false when upvote does not exist', async () => {
      const client = createMockClient();
      mockGetClient.mockResolvedValueOnce(client as any);
      client.query.mockResolvedValueOnce({ rows: [] });

      const result = await upvoteModel.existsForDevice('r1', 'd1');

      expect(result).toBe(false);
      expect(client.release).toHaveBeenCalled();
    });
  });
});
