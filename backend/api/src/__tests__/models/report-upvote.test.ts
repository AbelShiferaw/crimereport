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

  describe('toggle — upvotes + 1 on insert', () => {
    it('uses upvotes + 1 when adding an upvote', async () => {
      const client = createMockClient();
      mockGetClient.mockResolvedValueOnce(client as any);
      client.query
        .mockResolvedValueOnce(undefined) // BEGIN
        .mockResolvedValueOnce({ rows: [{ id: 'r1' }] }) // SELECT FOR UPDATE
        .mockResolvedValueOnce({ rows: [] }) // SELECT upvote (not found)
        .mockResolvedValueOnce(undefined) // INSERT
        .mockResolvedValueOnce(undefined) // UPDATE upvotes + 1
        .mockResolvedValueOnce(undefined); // COMMIT
      await upvoteModel.toggle('r1', 'd1');

      const incrementCall = client.query.mock.calls.find(
        (c: any[]) => typeof c[0] === 'string' && c[0].includes('upvotes + 1'),
      );
      expect(incrementCall).toBeDefined();
      expect(incrementCall![0]).toContain('upvotes + 1');
      expect(incrementCall![1]).toEqual(['r1']);
    });
  });

  describe('toggle — locks report row', () => {
    it('acquires FOR UPDATE lock on report before checking upvote', async () => {
      const client = createMockClient();
      mockGetClient.mockResolvedValueOnce(client as any);
      client.query
        .mockResolvedValueOnce(undefined) // BEGIN
        .mockResolvedValueOnce({ rows: [{ id: 'r1' }] }) // SELECT FOR UPDATE
        .mockResolvedValueOnce({ rows: [] }) // upvote check
        .mockResolvedValueOnce(undefined) // INSERT
        .mockResolvedValueOnce(undefined) // UPDATE
        .mockResolvedValueOnce(undefined); // COMMIT

      await upvoteModel.toggle('r1', 'd1');

      expect(client.query).toHaveBeenCalledWith(
        expect.stringContaining('FOR UPDATE'),
        ['r1'],
      );
      const calls = client.query.mock.calls.map((c: any[]) => c[0]);
      const lockIdx = calls.findIndex((s: string) => typeof s === 'string' && s.includes('FOR UPDATE'));
      const beginIdx = calls.indexOf('BEGIN');
      expect(lockIdx).toBeGreaterThan(beginIdx);
    });
  });

  describe('existsForDevice — SQL assertions', () => {
    it('queries report_upvotes table with correct parameters', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [{ '?column?': 1 }], rowCount: 1 } as any);

      await upvoteModel.existsForDevice('report-xyz', 'device-abc');

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('FROM report_upvotes'),
        ['report-xyz', 'device-abc'],
      );
    });

    it('uses report_id = $1 AND device_id = $2', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      await upvoteModel.existsForDevice('r1', 'd1');

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('report_id = $1 AND device_id = $2'),
        ['r1', 'd1'],
      );
    });
  });

  describe('toggle — client release', () => {
    it('always releases the client after success', async () => {
      const client = createMockClient();
      mockGetClient.mockResolvedValueOnce(client as any);
      client.query
        .mockResolvedValueOnce(undefined)
        .mockResolvedValueOnce({ rows: [{ id: 'r1' }] })
        .mockResolvedValueOnce({ rows: [] })
        .mockResolvedValueOnce(undefined)
        .mockResolvedValueOnce(undefined)
        .mockResolvedValueOnce(undefined);

      await upvoteModel.toggle('r1', 'd1');
      expect(client.release).toHaveBeenCalledTimes(1);
    });

    it('always releases the client after failure', async () => {
      const client = createMockClient();
      mockGetClient.mockResolvedValueOnce(client as any);
      client.query
        .mockResolvedValueOnce(undefined) // BEGIN
        .mockRejectedValueOnce(new Error('error'));

      await expect(upvoteModel.toggle('r1', 'd1')).rejects.toThrow();
      expect(client.release).toHaveBeenCalledTimes(1);
    });
  });
});
