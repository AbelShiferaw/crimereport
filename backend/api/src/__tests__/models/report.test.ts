import * as reportModel from '../../models/report';
import * as db from '../../lib/db';

jest.mock('../../lib/db');

const mockQuery = db.query as jest.MockedFunction<typeof db.query>;

describe('report model', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('findById', () => {
    it('returns report when found', async () => {
      const fakeRow = {
        id: 'abc-123',
        device_id: 'device-1',
        type: 'theft',
        description: 'Stolen bike',
        lat: 40.7128,
        lng: -74.006,
        address: '123 Main St',
        status: 'active',
        upvotes: 5,
        comment_count: 2,
        created_at: new Date(),
        updated_at: new Date(),
      };
      mockQuery.mockResolvedValueOnce({ rows: [fakeRow], rowCount: 1 } as any);

      const result = await reportModel.findById('abc-123');

      expect(result).toEqual(fakeRow);
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('WHERE id = $1'),
        ['abc-123'],
      );
    });

    it('returns null when not found', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      const result = await reportModel.findById('nonexistent');

      expect(result).toBeNull();
    });
  });

  describe('findNearby', () => {
    it('queries with PostGIS ST_DWithin and returns rows', async () => {
      const fakeRows = [
        { id: 'r1', lat: 40.71, lng: -74.0, distance_m: 150 },
        { id: 'r2', lat: 40.72, lng: -74.01, distance_m: 800 },
      ];
      mockQuery.mockResolvedValueOnce({ rows: fakeRows, rowCount: 2 } as any);

      const result = await reportModel.findNearby(40.7128, -74.006, 5000, { limit: 10, offset: 0 });

      expect(result).toHaveLength(2);
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('ST_DWithin'),
        [40.7128, -74.006, 5000, 10, 0],
      );
    });

    it('uses default pagination', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      await reportModel.findNearby(40.7128, -74.006, 5000);

      expect(mockQuery).toHaveBeenCalledWith(
        expect.any(String),
        [40.7128, -74.006, 5000, 20, 0],
      );
    });
  });

  describe('create', () => {
    it('inserts and returns the new report', async () => {
      const fakeRow = {
        id: 'new-id',
        device_id: 'device-1',
        type: 'vandalism',
        lat: 40.71,
        lng: -74.0,
        status: 'pending',
        upvotes: 0,
        comment_count: 0,
      };
      mockQuery.mockResolvedValueOnce({ rows: [fakeRow], rowCount: 1 } as any);

      const result = await reportModel.create({
        device_id: 'device-1',
        type: 'vandalism',
        lat: 40.71,
        lng: -74.0,
      });

      expect(result.id).toBe('new-id');
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO reports'),
        ['device-1', 'vandalism', null, 40.71, -74.0, null],
      );
    });
  });

  describe('updateStatus', () => {
    it('updates and returns the report', async () => {
      const fakeRow = { id: 'abc-123', status: 'active' };
      mockQuery.mockResolvedValueOnce({ rows: [fakeRow], rowCount: 1 } as any);

      const result = await reportModel.updateStatus('abc-123', 'active');

      expect(result?.status).toBe('active');
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('UPDATE reports SET status'),
        ['abc-123', 'active'],
      );
    });

    it('returns null when report not found', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      const result = await reportModel.updateStatus('nonexistent', 'active');

      expect(result).toBeNull();
    });
  });

  describe('incrementUpvotes', () => {
    it('increments upvotes for the given report', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 } as any);

      await reportModel.incrementUpvotes('abc-123');

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('upvotes + 1'),
        ['abc-123'],
      );
    });
  });

  describe('decrementUpvotes', () => {
    it('decrements upvotes with a floor of 0', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 } as any);

      await reportModel.decrementUpvotes('abc-123');

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('GREATEST(upvotes - 1, 0)'),
        ['abc-123'],
      );
    });
  });

  describe('incrementCommentCount', () => {
    it('increments comment count', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 } as any);

      await reportModel.incrementCommentCount('abc-123');

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('comment_count + 1'),
        ['abc-123'],
      );
    });
  });

  describe('decrementCommentCount', () => {
    it('decrements comment count with a floor of 0', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 } as any);

      await reportModel.decrementCommentCount('abc-123');

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('GREATEST(comment_count - 1, 0)'),
        ['abc-123'],
      );
    });
  });

  describe('findNearby — edge cases', () => {
    it('returns empty array when no reports are within radius', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      const result = await reportModel.findNearby(40.7128, -74.006, 100);

      expect(result).toEqual([]);
      expect(result).toHaveLength(0);
    });

    it('filters for active status only', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      await reportModel.findNearby(40.7128, -74.006, 5000);

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining("status = 'active'"),
        expect.any(Array),
      );
    });

    it('orders results by created_at DESC', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      await reportModel.findNearby(40.7128, -74.006, 5000);

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('ORDER BY created_at DESC'),
        expect.any(Array),
      );
    });

    it('passes lat as $1 and lng as $2 for PostGIS ST_MakePoint($2, $1)', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      await reportModel.findNearby(51.5074, -0.1278, 3000, { limit: 5, offset: 10 });

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('ST_MakePoint($2, $1)'),
        [51.5074, -0.1278, 3000, 5, 10],
      );
    });

    it('handles boundary radius at minimum distance', async () => {
      const fakeRow = { id: 'edge', distance_m: 99.9 };
      mockQuery.mockResolvedValueOnce({ rows: [fakeRow], rowCount: 1 } as any);

      const result = await reportModel.findNearby(0, 0, 100, { limit: 1, offset: 0 });

      expect(result).toHaveLength(1);
      expect(mockQuery).toHaveBeenCalledWith(
        expect.any(String),
        [0, 0, 100, 1, 0],
      );
    });

    it('handles large radius up to 50km', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      await reportModel.findNearby(40.7128, -74.006, 50000);

      expect(mockQuery).toHaveBeenCalledWith(
        expect.any(String),
        [40.7128, -74.006, 50000, 20, 0],
      );
    });

    it('computes ST_Distance in the SELECT', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      await reportModel.findNearby(40.7128, -74.006, 5000);

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('ST_Distance'),
        expect.any(Array),
      );
    });
  });

  describe('create — edge cases', () => {
    it('passes description and address when provided', async () => {
      const fakeRow = {
        id: 'new-2',
        device_id: 'device-2',
        type: 'assault',
        description: 'Mugging in the park',
        lat: 34.05,
        lng: -118.24,
        address: '456 Oak Ave',
        status: 'pending',
        upvotes: 0,
        comment_count: 0,
      };
      mockQuery.mockResolvedValueOnce({ rows: [fakeRow], rowCount: 1 } as any);

      await reportModel.create({
        device_id: 'device-2',
        type: 'assault',
        description: 'Mugging in the park',
        lat: 34.05,
        lng: -118.24,
        address: '456 Oak Ave',
      });

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO reports'),
        ['device-2', 'assault', 'Mugging in the park', 34.05, -118.24, '456 Oak Ave'],
      );
    });
  });

  describe('query error handling', () => {
    it('propagates db errors from findById', async () => {
      mockQuery.mockRejectedValueOnce(new Error('connection refused'));
      await expect(reportModel.findById('abc-123')).rejects.toThrow('connection refused');
    });

    it('propagates db errors from findNearby', async () => {
      mockQuery.mockRejectedValueOnce(new Error('timeout'));
      await expect(reportModel.findNearby(40.7128, -74.006, 5000)).rejects.toThrow('timeout');
    });

    it('propagates db errors from create', async () => {
      mockQuery.mockRejectedValueOnce(new Error('constraint violation'));
      await expect(
        reportModel.create({ device_id: 'd1', type: 'theft', lat: 0, lng: 0 }),
      ).rejects.toThrow('constraint violation');
    });

    it('propagates db errors from updateStatus', async () => {
      mockQuery.mockRejectedValueOnce(new Error('deadlock'));
      await expect(reportModel.updateStatus('r1', 'active')).rejects.toThrow('deadlock');
    });

    it('propagates db errors from incrementUpvotes', async () => {
      mockQuery.mockRejectedValueOnce(new Error('db error'));
      await expect(reportModel.incrementUpvotes('r1')).rejects.toThrow('db error');
    });

    it('propagates db errors from decrementUpvotes', async () => {
      mockQuery.mockRejectedValueOnce(new Error('db error'));
      await expect(reportModel.decrementUpvotes('r1')).rejects.toThrow('db error');
    });
  });
});
