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
        ['r1', 'image', 'https://cdn/new.jpg', null, null, null, null, null],
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

    it('returns 0 when no media exists for report', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      const result = await mediaModel.deleteByReportId('empty-report');

      expect(result).toBe(0);
    });

    it('handles null rowCount gracefully', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: null } as any);

      const result = await mediaModel.deleteByReportId('r1');

      expect(result).toBe(0);
    });
  });

  describe('findByMediaKey', () => {
    it('returns media when found by key', async () => {
      const fakeRow = {
        id: 'm1',
        report_id: 'r1',
        type: 'image',
        url: 'https://cdn/img.jpg',
        media_key: 'uploads/r1/abc.jpg',
        status: 'active',
      };
      mockQuery.mockResolvedValueOnce({ rows: [fakeRow], rowCount: 1 } as any);

      const result = await mediaModel.findByMediaKey('uploads/r1/abc.jpg');

      expect(result).toEqual(fakeRow);
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('WHERE media_key = $1'),
        ['uploads/r1/abc.jpg'],
      );
    });

    it('returns null when media key not found', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      const result = await mediaModel.findByMediaKey('nonexistent-key');

      expect(result).toBeNull();
    });
  });

  describe('updateUrls', () => {
    it('updates url, thumbnail_url, and sets status to active', async () => {
      const fakeRow = {
        id: 'm1',
        report_id: 'r1',
        type: 'image',
        url: 'https://cdn/processed.jpg',
        thumbnail_url: 'https://cdn/thumb.jpg',
        media_key: 'uploads/r1/abc.jpg',
        status: 'active',
      };
      mockQuery.mockResolvedValueOnce({ rows: [fakeRow], rowCount: 1 } as any);

      const result = await mediaModel.updateUrls(
        'uploads/r1/abc.jpg',
        'https://cdn/processed.jpg',
        'https://cdn/thumb.jpg',
      );

      expect(result).toEqual(fakeRow);
      expect(result!.status).toBe('active');
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining("status = 'active'"),
        ['uploads/r1/abc.jpg', 'https://cdn/processed.jpg', 'https://cdn/thumb.jpg'],
      );
    });

    it('handles null thumbnail_url', async () => {
      const fakeRow = {
        id: 'm1',
        url: 'https://cdn/video.mp4',
        thumbnail_url: null,
        status: 'active',
      };
      mockQuery.mockResolvedValueOnce({ rows: [fakeRow], rowCount: 1 } as any);

      const result = await mediaModel.updateUrls(
        'uploads/r1/vid.mp4',
        'https://cdn/video.mp4',
        null,
      );

      expect(result!.thumbnail_url).toBeNull();
      expect(mockQuery).toHaveBeenCalledWith(
        expect.any(String),
        ['uploads/r1/vid.mp4', 'https://cdn/video.mp4', null],
      );
    });

    it('returns null when media_key not found', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      const result = await mediaModel.updateUrls('nonexistent', 'url', null);

      expect(result).toBeNull();
    });
  });

  describe('updateStatus', () => {
    it('updates status for a media_key', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 } as any);

      await mediaModel.updateStatus('uploads/r1/abc.jpg', 'processing');

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('UPDATE media SET status = $2'),
        ['uploads/r1/abc.jpg', 'processing'],
      );
    });

    it('uses media_key as $1 parameter', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 } as any);

      await mediaModel.updateStatus('key-123', 'failed');

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('WHERE media_key = $1'),
        ['key-123', 'failed'],
      );
    });

    it('accepts various status values', async () => {
      for (const status of ['processing', 'active', 'failed']) {
        mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 } as any);
        await mediaModel.updateStatus('key', status);
      }
      expect(mockQuery).toHaveBeenCalledTimes(3);
    });
  });

  describe('updateFailure', () => {
    it('sets status=failed and stores the failure_reason', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 } as any);

      await mediaModel.updateFailure('uploads/r1/abc.jpg', 'processing_error');

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('failure_reason = $2'),
        ['uploads/r1/abc.jpg', 'processing_error'],
      );
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining("status = 'failed'"),
        expect.any(Array),
      );
    });

    it('supports flagged_content reason', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 } as any);

      await mediaModel.updateFailure('key', 'flagged_content');

      expect(mockQuery).toHaveBeenCalledWith(
        expect.any(String),
        ['key', 'flagged_content'],
      );
    });

    it('supports unsupported_format reason', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 } as any);

      await mediaModel.updateFailure('key', 'unsupported_format');

      expect(mockQuery).toHaveBeenCalledWith(
        expect.any(String),
        ['key', 'unsupported_format'],
      );
    });
  });

  describe('SELECT columns include failure_reason', () => {
    it('findByReportId selects failure_reason', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);
      await mediaModel.findByReportId('r1');
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('failure_reason'),
        ['r1'],
      );
    });

    it('findByMediaKey selects failure_reason', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);
      await mediaModel.findByMediaKey('k');
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('failure_reason'),
        ['k'],
      );
    });
  });

  describe('create — with optional fields', () => {
    it('passes all optional fields when provided', async () => {
      const fakeRow = {
        id: 'm-full',
        report_id: 'r1',
        type: 'video',
        url: 'https://cdn/vid.mp4',
        media_key: 'uploads/r1/vid.mp4',
        thumbnail_url: 'https://cdn/thumb.jpg',
        duration_ms: 15000,
        width: 1920,
        height: 1080,
        status: 'pending',
      };
      mockQuery.mockResolvedValueOnce({ rows: [fakeRow], rowCount: 1 } as any);

      const result = await mediaModel.create({
        report_id: 'r1',
        type: 'video',
        url: 'https://cdn/vid.mp4',
        media_key: 'uploads/r1/vid.mp4',
        thumbnail_url: 'https://cdn/thumb.jpg',
        duration_ms: 15000,
        width: 1920,
        height: 1080,
      });

      expect(result.id).toBe('m-full');
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO media'),
        ['r1', 'video', 'https://cdn/vid.mp4', 'uploads/r1/vid.mp4', 'https://cdn/thumb.jpg', 15000, 1920, 1080],
      );
    });
  });

  describe('findByReportId — edge cases', () => {
    it('returns empty array when no media exists', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      const result = await mediaModel.findByReportId('no-media-report');

      expect(result).toEqual([]);
    });

    it('SQL orders by created_at ASC', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 } as any);

      await mediaModel.findByReportId('r1');

      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('ORDER BY created_at ASC'),
        expect.any(Array),
      );
    });
  });

  describe('query error handling', () => {
    it('propagates db errors from findByReportId', async () => {
      mockQuery.mockRejectedValueOnce(new Error('connection error'));
      await expect(mediaModel.findByReportId('r1')).rejects.toThrow('connection error');
    });

    it('propagates db errors from findByMediaKey', async () => {
      mockQuery.mockRejectedValueOnce(new Error('timeout'));
      await expect(mediaModel.findByMediaKey('key')).rejects.toThrow('timeout');
    });

    it('propagates db errors from updateUrls', async () => {
      mockQuery.mockRejectedValueOnce(new Error('disk error'));
      await expect(mediaModel.updateUrls('key', 'url', null)).rejects.toThrow('disk error');
    });

    it('propagates db errors from updateStatus', async () => {
      mockQuery.mockRejectedValueOnce(new Error('db error'));
      await expect(mediaModel.updateStatus('key', 'failed')).rejects.toThrow('db error');
    });
  });
});
