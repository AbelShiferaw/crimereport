import { uploadRequestSchema, uploadCompleteSchema } from '../../validators/media';

describe('media validators', () => {
  describe('uploadRequestSchema', () => {
    const validImageBody = {
      device_id: 'device-123',
      file_type: 'image' as const,
      content_type: 'image/jpeg' as const,
    };

    const validVideoBody = {
      device_id: 'device-123',
      file_type: 'video' as const,
      content_type: 'video/mp4' as const,
    };

    it('accepts valid image upload request', () => {
      const result = uploadRequestSchema.safeParse(validImageBody);
      expect(result.success).toBe(true);
    });

    it('accepts valid video upload request', () => {
      const result = uploadRequestSchema.safeParse(validVideoBody);
      expect(result.success).toBe(true);
    });

    it.each(['image/jpeg', 'image/png', 'image/webp'] as const)(
      'accepts image content_type: %s',
      (content_type) => {
        const result = uploadRequestSchema.safeParse({
          ...validImageBody,
          content_type,
        });
        expect(result.success).toBe(true);
      },
    );

    it.each(['video/mp4', 'video/quicktime', 'video/webm'] as const)(
      'accepts video content_type: %s',
      (content_type) => {
        const result = uploadRequestSchema.safeParse({
          ...validVideoBody,
          content_type,
        });
        expect(result.success).toBe(true);
      },
    );

    it('rejects image file_type with video content_type (cross-type mismatch)', () => {
      const result = uploadRequestSchema.safeParse({
        device_id: 'device-123',
        file_type: 'image',
        content_type: 'video/mp4',
      });
      expect(result.success).toBe(false);
    });

    it('rejects video file_type with image content_type (cross-type mismatch)', () => {
      const result = uploadRequestSchema.safeParse({
        device_id: 'device-123',
        file_type: 'video',
        content_type: 'image/jpeg',
      });
      expect(result.success).toBe(false);
    });

    it('rejects unsupported content_type', () => {
      const result = uploadRequestSchema.safeParse({
        device_id: 'device-123',
        file_type: 'image',
        content_type: 'image/gif',
      });
      expect(result.success).toBe(false);
    });

    it('rejects unsupported file_type', () => {
      const result = uploadRequestSchema.safeParse({
        device_id: 'device-123',
        file_type: 'audio',
        content_type: 'audio/mp3',
      });
      expect(result.success).toBe(false);
    });

    it('rejects empty device_id', () => {
      const result = uploadRequestSchema.safeParse({
        ...validImageBody,
        device_id: '',
      });
      expect(result.success).toBe(false);
    });

    it('rejects device_id longer than 64 characters', () => {
      const result = uploadRequestSchema.safeParse({
        ...validImageBody,
        device_id: 'x'.repeat(65),
      });
      expect(result.success).toBe(false);
    });

    it('rejects missing file_type', () => {
      const result = uploadRequestSchema.safeParse({
        device_id: 'device-123',
        content_type: 'image/jpeg',
      });
      expect(result.success).toBe(false);
    });

    it('rejects missing content_type', () => {
      const result = uploadRequestSchema.safeParse({
        device_id: 'device-123',
        file_type: 'image',
      });
      expect(result.success).toBe(false);
    });

    it('rejects missing device_id', () => {
      const result = uploadRequestSchema.safeParse({
        file_type: 'image',
        content_type: 'image/jpeg',
      });
      expect(result.success).toBe(false);
    });
  });

  describe('uploadCompleteSchema', () => {
    const validBody = {
      device_id: 'device-123',
      media_key: 'uploads/report-abc/image-xyz.jpg',
    };

    it('accepts valid body', () => {
      const result = uploadCompleteSchema.safeParse(validBody);
      expect(result.success).toBe(true);
    });

    it('rejects empty device_id', () => {
      const result = uploadCompleteSchema.safeParse({ ...validBody, device_id: '' });
      expect(result.success).toBe(false);
    });

    it('rejects device_id longer than 64 characters', () => {
      const result = uploadCompleteSchema.safeParse({
        ...validBody,
        device_id: 'x'.repeat(65),
      });
      expect(result.success).toBe(false);
    });

    it('rejects empty media_key', () => {
      const result = uploadCompleteSchema.safeParse({ ...validBody, media_key: '' });
      expect(result.success).toBe(false);
    });

    it('rejects media_key longer than 500 characters', () => {
      const result = uploadCompleteSchema.safeParse({
        ...validBody,
        media_key: 'x'.repeat(501),
      });
      expect(result.success).toBe(false);
    });

    it('accepts media_key at max length (500)', () => {
      const result = uploadCompleteSchema.safeParse({
        ...validBody,
        media_key: 'x'.repeat(500),
      });
      expect(result.success).toBe(true);
    });

    it('rejects missing device_id', () => {
      const result = uploadCompleteSchema.safeParse({ media_key: 'key' });
      expect(result.success).toBe(false);
    });

    it('rejects missing media_key', () => {
      const result = uploadCompleteSchema.safeParse({ device_id: 'dev-1' });
      expect(result.success).toBe(false);
    });

    it('rejects non-string media_key', () => {
      const result = uploadCompleteSchema.safeParse({ ...validBody, media_key: 12345 });
      expect(result.success).toBe(false);
    });
  });
});
