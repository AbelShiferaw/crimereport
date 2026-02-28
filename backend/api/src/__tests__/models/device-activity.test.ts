import * as deviceModel from '../../models/device-activity';
import * as db from '../../lib/db';

jest.mock('../../lib/db');

const mockQuery = db.query as jest.MockedFunction<typeof db.query>;

describe('device-activity model', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('getOrCreate', () => {
    it('returns existing or newly created device activity', async () => {
      const fakeRow = {
        device_id: 'd1',
        report_count_today: 0,
        last_report_at: null,
        flagged: false,
        created_at: new Date(),
      };
      mockQuery.mockResolvedValueOnce({ rows: [fakeRow], rowCount: 1 } as any);

      const result = await deviceModel.getOrCreate('d1');

      expect(result.device_id).toBe('d1');
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('ON CONFLICT'),
        ['d1'],
      );
    });
  });

  describe('incrementReportCount', () => {
    it('increments count and updates last_report_at', async () => {
      const fakeRow = {
        device_id: 'd1',
        report_count_today: 3,
        last_report_at: new Date(),
        flagged: false,
        created_at: new Date(),
      };
      mockQuery.mockResolvedValueOnce({ rows: [fakeRow], rowCount: 1 } as any);

      const result = await deviceModel.incrementReportCount('d1');

      expect(result.report_count_today).toBe(3);
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('report_count_today + 1'),
        ['d1'],
      );
    });
  });

  describe('flag', () => {
    it('updates flagged status', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 } as any);

      await deviceModel.flag('d1', true);

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('SET flagged = $2'),
        ['d1', true],
      );
    });
  });

  describe('resetDailyCounts', () => {
    it('resets all counts and returns number affected', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 15 } as any);

      const result = await deviceModel.resetDailyCounts();

      expect(result).toBe(15);
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('SET report_count_today = 0'),
      );
    });
  });
});
