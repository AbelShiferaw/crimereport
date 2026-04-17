import * as deviceModel from '../../models/device-activity';
import * as db from '../../lib/db';

jest.mock('../../lib/db');
const mockQuery = db.query as jest.MockedFunction<typeof db.query>;

describe('device-activity model', () => {
  beforeEach(() => { jest.clearAllMocks(); });

  describe('getOrCreate', () => {
    it('returns existing or newly created device activity', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [{ device_id: 'd1', report_count_today: 0, last_report_at: null, flagged: false, created_at: new Date() }], rowCount: 1 } as any);
      const result = await deviceModel.getOrCreate('d1');
      expect(result.device_id).toBe('d1');
      expect(mockQuery).toHaveBeenCalledWith(expect.stringContaining('ON CONFLICT'), ['d1']);
    });
  });

  describe('incrementReportCount', () => {
    it('increments count and updates last_report_at', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [{ device_id: 'd1', report_count_today: 3, last_report_at: new Date(), flagged: false, created_at: new Date() }], rowCount: 1 } as any);
      const result = await deviceModel.incrementReportCount('d1');
      expect(result.report_count_today).toBe(3);
      expect(mockQuery).toHaveBeenCalledWith(expect.stringContaining('report_count_today + 1'), ['d1']);
    });
  });

  describe('flag', () => {
    it('updates flagged status', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 } as any);
      await deviceModel.flag('d1', true);
      expect(mockQuery).toHaveBeenCalledWith(expect.stringContaining('SET flagged = $2'), ['d1', true]);
    });
  });

  describe('resetDailyCounts', () => {
    it('resets all counts and returns number affected', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 15 } as any);
      expect(await deviceModel.resetDailyCounts()).toBe(15);
      expect(mockQuery).toHaveBeenCalledWith(expect.stringContaining('SET report_count_today = 0'));
    });
  });

  describe('getOrCreate — creates new device on first call', () => {
    it('creates new device via INSERT ON CONFLICT', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [{ device_id: 'brand-new-device', report_count_today: 0, last_report_at: null, flagged: false, created_at: new Date() }], rowCount: 1 } as any);
      const result = await deviceModel.getOrCreate('brand-new-device');
      expect(result.device_id).toBe('brand-new-device');
      expect(result.report_count_today).toBe(0);
      expect(result.flagged).toBe(false);
      expect(mockQuery).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO device_activity'), ['brand-new-device']);
    });
  });

  describe('incrementReportCount — floor guard', () => {
    it('SQL uses report_count_today + 1 ensuring count stays positive', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [{ device_id: 'd1', report_count_today: 1, last_report_at: new Date(), flagged: false, created_at: new Date() }], rowCount: 1 } as any);
      const result = await deviceModel.incrementReportCount('d1');
      expect(result.report_count_today).toBeGreaterThanOrEqual(0);
      expect((mockQuery.mock.calls[0][0] as string)).toContain('report_count_today + 1');
    });
  });

  describe('flag — unflag path', () => {
    it('can unflag a device by passing false', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 } as any);
      await deviceModel.flag('d1', false);
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('SET flagged = $2'),
        ['d1', false],
      );
    });
  });

  describe('resetDailyCounts — WHERE predicate', () => {
    it('only resets devices where report_count_today > 0', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 5 } as any);
      await deviceModel.resetDailyCounts();
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('WHERE report_count_today > 0'),
      );
    });

    it('returns 0 when no devices had reports today', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);
      const result = await deviceModel.resetDailyCounts();
      expect(result).toBe(0);
    });

    it('handles null rowCount gracefully', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: null } as any);
      const result = await deviceModel.resetDailyCounts();
      expect(result).toBe(0);
    });
  });

  describe('getOrCreate — SQL assertions', () => {
    it('uses INSERT INTO device_activity with ON CONFLICT DO UPDATE', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [{ device_id: 'd-new', report_count_today: 0, last_report_at: null, flagged: false, created_at: new Date() }], rowCount: 1 } as any);
      await deviceModel.getOrCreate('d-new');
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('ON CONFLICT (device_id) DO UPDATE'),
        ['d-new'],
      );
    });

    it('returns RETURNING clause fields', async () => {
      const now = new Date();
      mockQuery.mockResolvedValueOnce({
        rows: [{ device_id: 'd1', report_count_today: 5, last_report_at: now, flagged: true, created_at: now }],
        rowCount: 1,
      } as any);
      const result = await deviceModel.getOrCreate('d1');
      expect(result).toHaveProperty('device_id');
      expect(result).toHaveProperty('report_count_today');
      expect(result).toHaveProperty('flagged');
      expect(result).toHaveProperty('created_at');
    });
  });

  describe('incrementReportCount — SQL details', () => {
    it('updates last_report_at with NOW()', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [{ device_id: 'd1', report_count_today: 1 }], rowCount: 1 } as any);
      await deviceModel.incrementReportCount('d1');
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('last_report_at = NOW()'),
        ['d1'],
      );
    });

    it('targets correct device via WHERE device_id = $1', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [{ device_id: 'target', report_count_today: 1 }], rowCount: 1 } as any);
      await deviceModel.incrementReportCount('target');
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('WHERE device_id = $1'),
        ['target'],
      );
    });
  });

  describe('query error handling', () => {
    it('propagates db errors from getOrCreate', async () => {
      mockQuery.mockRejectedValueOnce(new Error('connection error'));
      await expect(deviceModel.getOrCreate('d1')).rejects.toThrow('connection error');
    });

    it('propagates db errors from incrementReportCount', async () => {
      mockQuery.mockRejectedValueOnce(new Error('timeout'));
      await expect(deviceModel.incrementReportCount('d1')).rejects.toThrow('timeout');
    });

    it('propagates db errors from flag', async () => {
      mockQuery.mockRejectedValueOnce(new Error('db down'));
      await expect(deviceModel.flag('d1', true)).rejects.toThrow('db down');
    });

    it('propagates db errors from resetDailyCounts', async () => {
      mockQuery.mockRejectedValueOnce(new Error('locked'));
      await expect(deviceModel.resetDailyCounts()).rejects.toThrow('locked');
    });
  });
});
