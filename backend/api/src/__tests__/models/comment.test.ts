import * as commentModel from '../../models/comment';
import * as db from '../../lib/db';

jest.mock('../../lib/db');

const mockQuery = db.query as jest.MockedFunction<typeof db.query>;

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
});
