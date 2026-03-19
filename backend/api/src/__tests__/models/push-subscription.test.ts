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
  });
});
