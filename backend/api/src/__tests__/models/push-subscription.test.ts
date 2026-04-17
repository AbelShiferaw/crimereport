import * as pushModel from '../../models/push-subscription';
import * as db from '../../lib/db';

jest.mock('../../lib/db');

const mockQuery = db.query as jest.MockedFunction<typeof db.query>;

describe('push-subscription model', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('findByDeviceId', () => {
    it('returns subscription when found', async () => {
      const row = {
        device_id: 'dev-1',
        fcm_token: 'tok',
        platform: 'android',
        endpoint_arn: 'arn:aws:sns:us-east-1:123:endpoint/GCM/app/id',
        lat: 40.71,
        lng: -74.0,
        radius: 10000,
        types: null,
        enabled: true,
        created_at: new Date(),
        updated_at: new Date(),
      };
      mockQuery.mockResolvedValueOnce({ rows: [row], rowCount: 1 } as any);

      const result = await pushModel.findByDeviceId('dev-1');
      expect(result).toEqual(row);
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('WHERE device_id = $1'),
        ['dev-1'],
      );
    });

    it('returns null when not found', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);
      const result = await pushModel.findByDeviceId('nonexistent');
      expect(result).toBeNull();
    });
  });

  describe('upsert', () => {
    it('inserts and returns the subscription', async () => {
      const row = {
        device_id: 'dev-1',
        fcm_token: 'tok',
        platform: 'android',
        endpoint_arn: 'arn:endpoint',
        lat: 40.71,
        lng: -74.0,
        radius: 10000,
        types: null,
        enabled: true,
        created_at: new Date(),
        updated_at: new Date(),
      };
      mockQuery.mockResolvedValueOnce({ rows: [row], rowCount: 1 } as any);

      const result = await pushModel.upsert(
        { device_id: 'dev-1', fcm_token: 'tok', platform: 'android', lat: 40.71, lng: -74.0 },
        'arn:endpoint',
      );
      expect(result).toEqual(row);
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('ON CONFLICT'),
        ['dev-1', 'tok', 'android', 'arn:endpoint', 40.71, -74.0],
      );
    });
  });

  describe('remove', () => {
    it('returns endpoint_arn when subscription exists', async () => {
      mockQuery.mockResolvedValueOnce({
        rows: [{ endpoint_arn: 'arn:endpoint' }],
        rowCount: 1,
      } as any);

      const result = await pushModel.remove('dev-1');
      expect(result).toBe('arn:endpoint');
    });

    it('returns null when subscription does not exist', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);
      const result = await pushModel.remove('nonexistent');
      expect(result).toBeNull();
    });
  });

  describe('updatePreferences', () => {
    it('returns updated subscription', async () => {
      const row = {
        device_id: 'dev-1',
        enabled: false,
        radius: 20000,
        types: ['theft'],
      };
      mockQuery.mockResolvedValueOnce({ rows: [row], rowCount: 1 } as any);

      const result = await pushModel.updatePreferences('dev-1', {
        enabled: false,
        radius: 20000,
        types: ['theft'],
      });
      expect(result).toEqual(row);
    });

    it('returns null when device not found', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);
      const result = await pushModel.updatePreferences('nonexistent', { enabled: true });
      expect(result).toBeNull();
    });
  });

  describe('findNearbyEnabled', () => {
    it('queries with ST_DWithin and returns matching devices', async () => {
      const rows = [
        { device_id: 'dev-2', endpoint_arn: 'arn:2', platform: 'android' },
      ];
      mockQuery.mockResolvedValueOnce({ rows, rowCount: 1 } as any);

      const result = await pushModel.findNearbyEnabled(40.71, -74.0, 'theft', 'dev-1');
      expect(result).toEqual(rows);
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('ST_DWithin'),
        [40.71, -74.0, 'theft', 'dev-1'],
      );
    });
  });

  describe('disableByEndpointArn', () => {
    it('disables the subscription', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 } as any);
      await pushModel.disableByEndpointArn('arn:endpoint');
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('enabled = false'),
        ['arn:endpoint'],
      );
    });

    it('passes endpoint_arn as $1 parameter', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);
      await pushModel.disableByEndpointArn('arn:aws:sns:us-east-1:123:endpoint/test');
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('WHERE endpoint_arn = $1'),
        ['arn:aws:sns:us-east-1:123:endpoint/test'],
      );
    });

    it('updates updated_at timestamp', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 } as any);
      await pushModel.disableByEndpointArn('arn:endpoint');
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('updated_at = NOW()'),
        expect.any(Array),
      );
    });
  });

  describe('upsert — token refresh / ON CONFLICT', () => {
    it('SQL includes ON CONFLICT DO UPDATE for fcm_token, endpoint_arn, location', async () => {
      const row = {
        device_id: 'dev-1',
        fcm_token: 'new-tok',
        platform: 'ios',
        endpoint_arn: 'arn:new',
        lat: 34.05,
        lng: -118.24,
        radius: 10000,
        types: null,
        enabled: true,
        created_at: new Date(),
        updated_at: new Date(),
      };
      mockQuery.mockResolvedValueOnce({ rows: [row], rowCount: 1 } as any);

      const result = await pushModel.upsert(
        { device_id: 'dev-1', fcm_token: 'new-tok', platform: 'ios', lat: 34.05, lng: -118.24 },
        'arn:new',
      );

      expect(result.fcm_token).toBe('new-tok');
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('EXCLUDED.fcm_token'),
        expect.any(Array),
      );
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('EXCLUDED.endpoint_arn'),
        expect.any(Array),
      );
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('EXCLUDED.location'),
        expect.any(Array),
      );
    });

    it('passes parameters in correct positional order ($1-$6)', async () => {
      const row = { device_id: 'dev-2', fcm_token: 'tok-2' };
      mockQuery.mockResolvedValueOnce({ rows: [row], rowCount: 1 } as any);

      await pushModel.upsert(
        { device_id: 'dev-2', fcm_token: 'tok-2', platform: 'android', lat: 0, lng: 0 },
        'arn:ep-2',
      );

      expect(mockQuery).toHaveBeenCalledWith(
        expect.any(String),
        ['dev-2', 'tok-2', 'android', 'arn:ep-2', 0, 0],
      );
    });
  });

  describe('updatePreferences — partial updates', () => {
    it('passes null for fields not provided (COALESCE preserves existing)', async () => {
      const row = { device_id: 'dev-1', enabled: true, radius: 10000, types: null };
      mockQuery.mockResolvedValueOnce({ rows: [row], rowCount: 1 } as any);

      await pushModel.updatePreferences('dev-1', { enabled: true });

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('COALESCE'),
        ['dev-1', true, null, null],
      );
    });

    it('passes only radius when updating radius alone', async () => {
      const row = { device_id: 'dev-1', enabled: true, radius: 25000, types: null };
      mockQuery.mockResolvedValueOnce({ rows: [row], rowCount: 1 } as any);

      await pushModel.updatePreferences('dev-1', { radius: 25000 });

      expect(mockQuery).toHaveBeenCalledWith(
        expect.any(String),
        ['dev-1', null, 25000, null],
      );
    });

    it('passes types array when updating notification types', async () => {
      const row = { device_id: 'dev-1', enabled: true, radius: 10000, types: ['theft', 'assault'] };
      mockQuery.mockResolvedValueOnce({ rows: [row], rowCount: 1 } as any);

      await pushModel.updatePreferences('dev-1', { types: ['theft', 'assault'] });

      expect(mockQuery).toHaveBeenCalledWith(
        expect.any(String),
        ['dev-1', null, null, ['theft', 'assault']],
      );
    });

    it('passes all fields when updating everything', async () => {
      const row = { device_id: 'dev-1', enabled: false, radius: 5000, types: ['robbery'] };
      mockQuery.mockResolvedValueOnce({ rows: [row], rowCount: 1 } as any);

      await pushModel.updatePreferences('dev-1', {
        enabled: false,
        radius: 5000,
        types: ['robbery'],
      });

      expect(mockQuery).toHaveBeenCalledWith(
        expect.any(String),
        ['dev-1', false, 5000, ['robbery']],
      );
    });
  });

  describe('findNearbyEnabled — edge cases', () => {
    it('returns empty array when no nearby enabled devices found', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      const result = await pushModel.findNearbyEnabled(40.71, -74.0, 'theft', 'dev-1');

      expect(result).toEqual([]);
      expect(result).toHaveLength(0);
    });

    it('SQL includes types filter with ANY clause', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      await pushModel.findNearbyEnabled(40.71, -74.0, 'assault', 'dev-1');

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('types IS NULL OR $3 = ANY(types)'),
        [40.71, -74.0, 'assault', 'dev-1'],
      );
    });

    it('SQL filters for enabled = true only', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      await pushModel.findNearbyEnabled(40.71, -74.0, 'theft', 'dev-1');

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('enabled = true'),
        expect.any(Array),
      );
    });

    it('SQL excludes the reporting device via device_id != $4', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      await pushModel.findNearbyEnabled(40.71, -74.0, 'theft', 'reporter-dev');

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('device_id != $4'),
        [40.71, -74.0, 'theft', 'reporter-dev'],
      );
    });

    it('uses per-device radius instead of fixed radius', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      await pushModel.findNearbyEnabled(40.71, -74.0, 'theft', 'dev-1');

      const sql = mockQuery.mock.calls[0][0] as string;
      expect(sql).toContain('radius');
      expect(sql).not.toMatch(/ST_DWithin\([^)]*\$3[^)]*\)/);
    });
  });

  describe('query error handling', () => {
    it('propagates db errors from findByDeviceId', async () => {
      mockQuery.mockRejectedValueOnce(new Error('connection lost'));
      await expect(pushModel.findByDeviceId('dev-1')).rejects.toThrow('connection lost');
    });

    it('propagates db errors from upsert', async () => {
      mockQuery.mockRejectedValueOnce(new Error('constraint error'));
      await expect(
        pushModel.upsert(
          { device_id: 'd1', fcm_token: 't', platform: 'ios', lat: 0, lng: 0 },
          'arn:x',
        ),
      ).rejects.toThrow('constraint error');
    });

    it('propagates db errors from remove', async () => {
      mockQuery.mockRejectedValueOnce(new Error('timeout'));
      await expect(pushModel.remove('dev-1')).rejects.toThrow('timeout');
    });
  });
});
