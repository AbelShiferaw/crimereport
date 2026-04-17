import * as commentModel from '../../models/comment';
import * as db from '../../lib/db';

jest.mock('../../lib/db');

const mockQuery = db.query as jest.MockedFunction<typeof db.query>;
const mockGetClient = db.getClient as jest.MockedFunction<typeof db.getClient>;

function createMockClient() {
  return { query: jest.fn(), release: jest.fn() };
}

describe('comment model', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('findByReportId', () => {
    it('returns paginated comments', async () => {
      const fakeRows = [
        { id: 'c1', report_id: 'r1', device_id: 'd1', content: 'Be careful!' },
      ];
      mockQuery.mockResolvedValueOnce({ rows: fakeRows, rowCount: 1 } as any);

      const result = await commentModel.findByReportId('r1', { limit: 10, offset: 5 });

      expect(result).toHaveLength(1);
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('LIMIT $2 OFFSET $3'),
        ['r1', 10, 5],
      );
    });

    it('uses default pagination', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      await commentModel.findByReportId('r1');

      expect(mockQuery).toHaveBeenCalledWith(expect.any(String), ['r1', 20, 0]);
    });
  });

  describe('create', () => {
    it('inserts and returns the new comment', async () => {
      const fakeRow = { id: 'c-new', report_id: 'r1', device_id: 'd1', content: 'Watch out' };
      mockQuery.mockResolvedValueOnce({ rows: [fakeRow], rowCount: 1 } as any);

      const result = await commentModel.create({
        report_id: 'r1',
        device_id: 'd1',
        content: 'Watch out',
      });

      expect(result.id).toBe('c-new');
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO comments'),
        ['r1', 'd1', 'Watch out'],
      );
    });
  });

  describe('deleteById', () => {
    it('returns true when comment is deleted', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 } as any);

      const result = await commentModel.deleteById('c1');

      expect(result).toBe(true);
    });

    it('returns false when comment not found', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      const result = await commentModel.deleteById('nonexistent');

      expect(result).toBe(false);
    });
  });

  describe('countByReportId', () => {
    it('returns the count as a number', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [{ count: '42' }], rowCount: 1 } as any);

      const result = await commentModel.countByReportId('r1');

      expect(result).toBe(42);
    });
  });

  describe('findById', () => {
    it('returns comment when found', async () => {
      const fakeRow = { id: 'c1', report_id: 'r1', device_id: 'd1', content: 'Hello' };
      mockQuery.mockResolvedValueOnce({ rows: [fakeRow], rowCount: 1 } as any);

      const result = await commentModel.findById('c1');

      expect(result).toEqual(fakeRow);
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('WHERE id = $1'),
        ['c1'],
      );
    });

    it('returns null when not found', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      const result = await commentModel.findById('nonexistent');

      expect(result).toBeNull();
    });
  });

  describe('createForReport', () => {
    it('inserts comment and increments report count in a transaction', async () => {
      const client = createMockClient();
      mockGetClient.mockResolvedValueOnce(client as any);

      const fakeRow = { id: 'c-new', report_id: 'r1', device_id: 'd1', content: 'Watch out' };
      client.query
        .mockResolvedValueOnce(undefined) // BEGIN
        .mockResolvedValueOnce({ rows: [fakeRow] }) // INSERT
        .mockResolvedValueOnce(undefined) // UPDATE comment_count
        .mockResolvedValueOnce(undefined); // COMMIT

      const result = await commentModel.createForReport({
        report_id: 'r1',
        device_id: 'd1',
        content: 'Watch out',
      });

      expect(result.id).toBe('c-new');
      expect(client.query).toHaveBeenCalledWith('BEGIN');
      expect(client.query).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO comments'),
        ['r1', 'd1', 'Watch out'],
      );
      expect(client.query).toHaveBeenCalledWith(
        expect.stringContaining('comment_count = comment_count + 1'),
        ['r1'],
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

      await expect(
        commentModel.createForReport({ report_id: 'r1', device_id: 'd1', content: 'Test' }),
      ).rejects.toThrow('db error');
      expect(client.query).toHaveBeenCalledWith('ROLLBACK');
      expect(client.release).toHaveBeenCalled();
    });
  });

  describe('countTodayByDevice', () => {
    it('returns count of comments in the last 24 hours', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [{ count: '7' }], rowCount: 1 } as any);

      const result = await commentModel.countTodayByDevice('d1');

      expect(result).toBe(7);
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('24 hours'),
        ['d1'],
      );
    });

    it('returns 0 when no comments today', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [{ count: '0' }], rowCount: 1 } as any);

      const result = await commentModel.countTodayByDevice('d1');

      expect(result).toBe(0);
    });

    it('passes device_id as $1', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [{ count: '0' }], rowCount: 1 } as any);

      await commentModel.countTodayByDevice('device-xyz');

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('WHERE device_id = $1'),
        ['device-xyz'],
      );
    });
  });

  describe('countByReportId — edge cases', () => {
    it('returns 0 when no comments exist for report', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [{ count: '0' }], rowCount: 1 } as any);

      const result = await commentModel.countByReportId('empty-report');

      expect(result).toBe(0);
    });

    it('parses large count values correctly', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [{ count: '9999' }], rowCount: 1 } as any);

      const result = await commentModel.countByReportId('popular-report');

      expect(result).toBe(9999);
    });

    it('passes report_id as $1', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [{ count: '5' }], rowCount: 1 } as any);

      await commentModel.countByReportId('report-abc');

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('WHERE report_id = $1'),
        ['report-abc'],
      );
    });
  });

  describe('deleteById — edge cases', () => {
    it('SQL targets comments table with id parameter', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 } as any);

      await commentModel.deleteById('c1');

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('DELETE FROM comments WHERE id = $1'),
        ['c1'],
      );
    });

    it('handles null rowCount gracefully (returns false)', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: null } as any);

      const result = await commentModel.deleteById('c-null');

      expect(result).toBe(false);
    });
  });

  describe('findByReportId — edge cases', () => {
    it('returns empty array for report with no comments', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      const result = await commentModel.findByReportId('no-comments-report');

      expect(result).toEqual([]);
    });

    it('SQL orders by created_at DESC', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      await commentModel.findByReportId('r1');

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('ORDER BY created_at DESC'),
        expect.any(Array),
      );
    });
  });

  describe('createForReport — edge cases', () => {
    it('releases client even when commit succeeds', async () => {
      const client = createMockClient();
      mockGetClient.mockResolvedValueOnce(client as any);

      const fakeRow = { id: 'c-ok', report_id: 'r1', device_id: 'd1', content: 'ok' };
      client.query
        .mockResolvedValueOnce(undefined) // BEGIN
        .mockResolvedValueOnce({ rows: [fakeRow] }) // INSERT
        .mockResolvedValueOnce(undefined) // UPDATE
        .mockResolvedValueOnce(undefined); // COMMIT

      await commentModel.createForReport({ report_id: 'r1', device_id: 'd1', content: 'ok' });

      expect(client.release).toHaveBeenCalledTimes(1);
    });

    it('rolls back when UPDATE comment_count fails', async () => {
      const client = createMockClient();
      mockGetClient.mockResolvedValueOnce(client as any);

      const fakeRow = { id: 'c-fail', report_id: 'r1', device_id: 'd1', content: 'test' };
      client.query
        .mockResolvedValueOnce(undefined) // BEGIN
        .mockResolvedValueOnce({ rows: [fakeRow] }) // INSERT
        .mockRejectedValueOnce(new Error('FK violation')); // UPDATE fails

      await expect(
        commentModel.createForReport({ report_id: 'r1', device_id: 'd1', content: 'test' }),
      ).rejects.toThrow('FK violation');

      expect(client.query).toHaveBeenCalledWith('ROLLBACK');
      expect(client.release).toHaveBeenCalled();
    });
  });

  describe('query error handling', () => {
    it('propagates db errors from findByReportId', async () => {
      mockQuery.mockRejectedValueOnce(new Error('connection error'));
      await expect(commentModel.findByReportId('r1')).rejects.toThrow('connection error');
    });

    it('propagates db errors from create', async () => {
      mockQuery.mockRejectedValueOnce(new Error('disk full'));
      await expect(
        commentModel.create({ report_id: 'r1', device_id: 'd1', content: 'test' }),
      ).rejects.toThrow('disk full');
    });

    it('propagates db errors from countByReportId', async () => {
      mockQuery.mockRejectedValueOnce(new Error('timeout'));
      await expect(commentModel.countByReportId('r1')).rejects.toThrow('timeout');
    });
  });
});
