import * as upvoteModel from '../../models/report-upvote';
import * as db from '../../lib/db';

jest.mock('../../lib/db');
const mockGetClient = db.getClient as jest.MockedFunction<typeof db.getClient>;
const mockQuery = db.query as jest.MockedFunction<typeof db.query>;

function createMockClient() { return { query: jest.fn(), release: jest.fn() }; }

describe('report-upvote model', () => {
  beforeEach(() => { jest.clearAllMocks(); });

  describe('toggle', () => {
    it('adds upvote when it does not exist and returns true', async () => {
      const client = createMockClient();
      mockGetClient.mockResolvedValueOnce(client as any);
      client.query.mockResolvedValueOnce(undefined).mockResolvedValueOnce({ rows: [{ id: 'r1' }] }).mockResolvedValueOnce({ rows: [] }).mockResolvedValueOnce(undefined).mockResolvedValueOnce(undefined).mockResolvedValueOnce(undefined);
      expect(await upvoteModel.toggle('r1', 'd1')).toBe(true);
      expect(client.query).toHaveBeenCalledWith('BEGIN');
      expect(client.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO report_upvotes'), ['r1', 'd1']);
      expect(client.query).toHaveBeenCalledWith('COMMIT');
      expect(client.release).toHaveBeenCalled();
    });
    it('removes upvote when it already exists and returns false', async () => {
      const client = createMockClient();
      mockGetClient.mockResolvedValueOnce(client as any);
      client.query.mockResolvedValueOnce(undefined).mockResolvedValueOnce({ rows: [{ id: 'r1' }] }).mockResolvedValueOnce({ rows: [{ report_id: 'r1' }] }).mockResolvedValueOnce(undefined).mockResolvedValueOnce(undefined).mockResolvedValueOnce(undefined);
      expect(await upvoteModel.toggle('r1', 'd1')).toBe(false);
      expect(client.query).toHaveBeenCalledWith(expect.stringContaining('DELETE FROM report_upvotes'), ['r1', 'd1']);
      expect(client.query).toHaveBeenCalledWith('COMMIT');
    });
    it('rolls back on error and re-throws', async () => {
      const client = createMockClient();
      mockGetClient.mockResolvedValueOnce(client as any);
      client.query.mockResolvedValueOnce(undefined).mockRejectedValueOnce(new Error('db error'));
      await expect(upvoteModel.toggle('r1', 'd1')).rejects.toThrow('db error');
      expect(client.query).toHaveBeenCalledWith('ROLLBACK');
      expect(client.release).toHaveBeenCalled();
    });
  });

  describe('existsForDevice', () => {
    it('returns true when upvote exists', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [{ '?column?': 1 }], rowCount: 1 } as any);
      expect(await upvoteModel.existsForDevice('r1', 'd1')).toBe(true);
    });
    it('returns false when upvote does not exist', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);
      expect(await upvoteModel.existsForDevice('r1', 'd1')).toBe(false);
    });
  });

  describe('toggle — double toggle returns to original state', () => {
    it('upvote then un-upvote returns false', async () => {
      const c1 = createMockClient();
      mockGetClient.mockResolvedValueOnce(c1 as any);
      c1.query.mockResolvedValueOnce(undefined).mockResolvedValueOnce({ rows: [{ id: 'r1' }] }).mockResolvedValueOnce({ rows: [] }).mockResolvedValueOnce(undefined).mockResolvedValueOnce(undefined).mockResolvedValueOnce(undefined);
      expect(await upvoteModel.toggle('r1', 'd1')).toBe(true);

      const c2 = createMockClient();
      mockGetClient.mockResolvedValueOnce(c2 as any);
      c2.query.mockResolvedValueOnce(undefined).mockResolvedValueOnce({ rows: [{ id: 'r1' }] }).mockResolvedValueOnce({ rows: [{ report_id: 'r1' }] }).mockResolvedValueOnce(undefined).mockResolvedValueOnce(undefined).mockResolvedValueOnce(undefined);
      expect(await upvoteModel.toggle('r1', 'd1')).toBe(false);
    });
  });

  describe('toggle — GREATEST floor guard in SQL', () => {
    it('uses GREATEST(upvotes - 1, 0) when removing', async () => {
      const client = createMockClient();
      mockGetClient.mockResolvedValueOnce(client as any);
      client.query.mockResolvedValueOnce(undefined).mockResolvedValueOnce({ rows: [{ id: 'r1' }] }).mockResolvedValueOnce({ rows: [{ report_id: 'r1' }] }).mockResolvedValueOnce(undefined).mockResolvedValueOnce(undefined).mockResolvedValueOnce(undefined);
      await upvoteModel.toggle('r1', 'd1');
      const updateCall = client.query.mock.calls.find((c: any[]) => typeof c[0] === 'string' && c[0].includes('GREATEST'));
      expect(updateCall).toBeDefined();
      expect(updateCall![0]).toContain('GREATEST(upvotes - 1, 0)');
    });
  });
});
