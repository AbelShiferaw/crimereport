import * as mediaModel from '../../models/media';
import * as db from '../../lib/db';

jest.mock('../../lib/db');

const mockQuery = db.query as jest.MockedFunction<typeof db.query>;

describe('media model', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('findByReportId', () => {
    it('returns media items for a report', async () => {
      const fakeRows = [
        { id: 'm1', report_id: 'r1', type: 'image', url: 'https://cdn/img.jpg' },
        { id: 'm2', report_id: 'r1', type: 'video', url: 'https://cdn/vid.mp4' },
      ];
      mockQuery.mockResolvedValueOnce({ rows: fakeRows, rowCount: 2 } as any);

      const result = await mediaModel.findByReportId('r1');

      expect(result).toHaveLength(2);
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('WHERE report_id = $1'),
        ['r1'],
      );
    });
  });

  describe('create', () => {
    it('inserts and returns the media record', async () => {
      const fakeRow = { id: 'm-new', report_id: 'r1', type: 'image', url: 'https://cdn/new.jpg' };
      mockQuery.mockResolvedValueOnce({ rows: [fakeRow], rowCount: 1 } as any);

      const result = await mediaModel.create({
        report_id: 'r1',
        type: 'image',
        url: 'https://cdn/new.jpg',
      });

      expect(result.id).toBe('m-new');
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO media'),
        ['r1', 'image', 'https://cdn/new.jpg', null, null, null, null],
      );
    });
  });

  describe('deleteByReportId', () => {
    it('deletes all media for a report and returns count', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 3 } as any);

      const result = await mediaModel.deleteByReportId('r1');

      expect(result).toBe(3);
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('DELETE FROM media'),
        ['r1'],
      );
    });
  });
});
