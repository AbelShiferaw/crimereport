import { createCommentSchema, flagCommentSchema, commentListQuerySchema } from '../../validators/comment';

describe('comment validators', () => {
  describe('createCommentSchema', () => {
    const validBody = { device_id: 'device-123', content: 'Be careful in this area!' };

    it('accepts valid body', () => {
      const result = createCommentSchema.safeParse(validBody);
      expect(result.success).toBe(true);
    });

    it('trims whitespace from content', () => {
      const result = createCommentSchema.safeParse({
        ...validBody,
        content: '  padded content  ',
      });
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.content).toBe('padded content');
      }
    });

    it('rejects empty content (after trim)', () => {
      const result = createCommentSchema.safeParse({
        ...validBody,
        content: '   ',
      });
      expect(result.success).toBe(false);
    });

    it('rejects content exceeding 1000 characters', () => {
      const result = createCommentSchema.safeParse({
        ...validBody,
        content: 'a'.repeat(1001),
      });
      expect(result.success).toBe(false);
    });

    it('accepts content at max length (1000)', () => {
      const result = createCommentSchema.safeParse({
        ...validBody,
        content: 'a'.repeat(1000),
      });
      expect(result.success).toBe(true);
    });

    it('accepts content at min length (1)', () => {
      const result = createCommentSchema.safeParse({
        ...validBody,
        content: 'x',
      });
      expect(result.success).toBe(true);
    });

    it('rejects missing content', () => {
      const result = createCommentSchema.safeParse({ device_id: 'device-123' });
      expect(result.success).toBe(false);
    });

    it('rejects empty device_id', () => {
      const result = createCommentSchema.safeParse({ ...validBody, device_id: '' });
      expect(result.success).toBe(false);
    });

    it('rejects device_id longer than 64 characters', () => {
      const result = createCommentSchema.safeParse({
        ...validBody,
        device_id: 'x'.repeat(65),
      });
      expect(result.success).toBe(false);
    });

    it('rejects missing device_id', () => {
      const result = createCommentSchema.safeParse({ content: 'test' });
      expect(result.success).toBe(false);
    });

    it('rejects non-string content', () => {
      const result = createCommentSchema.safeParse({ ...validBody, content: 12345 });
      expect(result.success).toBe(false);
    });
  });

  describe('flagCommentSchema', () => {
    it('accepts valid device_id', () => {
      const result = flagCommentSchema.safeParse({ device_id: 'device-123' });
      expect(result.success).toBe(true);
    });

    it('rejects empty device_id', () => {
      const result = flagCommentSchema.safeParse({ device_id: '' });
      expect(result.success).toBe(false);
    });

    it('rejects device_id longer than 64 characters', () => {
      const result = flagCommentSchema.safeParse({ device_id: 'x'.repeat(65) });
      expect(result.success).toBe(false);
    });

    it('accepts device_id at max length (64)', () => {
      const result = flagCommentSchema.safeParse({ device_id: 'x'.repeat(64) });
      expect(result.success).toBe(true);
    });

    it('rejects missing device_id', () => {
      const result = flagCommentSchema.safeParse({});
      expect(result.success).toBe(false);
    });

    it('rejects non-string device_id', () => {
      const result = flagCommentSchema.safeParse({ device_id: null });
      expect(result.success).toBe(false);
    });
  });

  describe('commentListQuerySchema', () => {
    it('applies defaults for empty query', () => {
      const result = commentListQuerySchema.safeParse({});
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.limit).toBe(20);
        expect(result.data.offset).toBe(0);
      }
    });

    it('coerces string values to numbers', () => {
      const result = commentListQuerySchema.safeParse({ limit: '10', offset: '5' });
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.limit).toBe(10);
        expect(result.data.offset).toBe(5);
      }
    });

    it('rejects limit below 1', () => {
      const result = commentListQuerySchema.safeParse({ limit: '0' });
      expect(result.success).toBe(false);
    });

    it('rejects limit above 100', () => {
      const result = commentListQuerySchema.safeParse({ limit: '101' });
      expect(result.success).toBe(false);
    });

    it('accepts limit at boundaries (1, 100)', () => {
      expect(commentListQuerySchema.safeParse({ limit: '1' }).success).toBe(true);
      expect(commentListQuerySchema.safeParse({ limit: '100' }).success).toBe(true);
    });

    it('rejects negative offset', () => {
      const result = commentListQuerySchema.safeParse({ offset: '-1' });
      expect(result.success).toBe(false);
    });

    it('accepts offset of 0', () => {
      const result = commentListQuerySchema.safeParse({ offset: '0' });
      expect(result.success).toBe(true);
    });

    it('rejects non-integer limit', () => {
      const result = commentListQuerySchema.safeParse({ limit: '10.5' });
      expect(result.success).toBe(false);
    });

    it('rejects non-numeric limit', () => {
      const result = commentListQuerySchema.safeParse({ limit: 'abc' });
      expect(result.success).toBe(false);
    });
  });
});
