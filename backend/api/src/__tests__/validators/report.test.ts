import { createReportSchema, nearbyQuerySchema, upvoteSchema, CRIME_TYPES } from '../../validators/report';

describe('report validators', () => {
  describe('createReportSchema', () => {
    const validBody = {
      device_id: 'device-123',
      type: 'theft' as const,
      lat: 40.7128,
      lng: -74.006,
    };

    it('accepts a valid minimal body', () => {
      const result = createReportSchema.safeParse(validBody);
      expect(result.success).toBe(true);
    });

    it('accepts a body with optional description and address', () => {
      const result = createReportSchema.safeParse({
        ...validBody,
        description: 'Bike stolen from rack',
        address: '123 Main St',
      });
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.description).toBe('Bike stolen from rack');
        expect(result.data.address).toBe('123 Main St');
      }
    });

    it('rejects empty device_id', () => {
      const result = createReportSchema.safeParse({ ...validBody, device_id: '' });
      expect(result.success).toBe(false);
    });

    it('rejects device_id longer than 64 characters', () => {
      const result = createReportSchema.safeParse({
        ...validBody,
        device_id: 'x'.repeat(65),
      });
      expect(result.success).toBe(false);
    });

    it('accepts device_id at max length (64)', () => {
      const result = createReportSchema.safeParse({
        ...validBody,
        device_id: 'x'.repeat(64),
      });
      expect(result.success).toBe(true);
    });

    it('accepts device_id at min length (1)', () => {
      const result = createReportSchema.safeParse({
        ...validBody,
        device_id: 'x',
      });
      expect(result.success).toBe(true);
    });

    it.each(CRIME_TYPES)('accepts crime type: %s', (type) => {
      const result = createReportSchema.safeParse({ ...validBody, type });
      expect(result.success).toBe(true);
    });

    it('rejects invalid crime type', () => {
      const result = createReportSchema.safeParse({ ...validBody, type: 'arson' });
      expect(result.success).toBe(false);
    });

    it('rejects lat below -90', () => {
      const result = createReportSchema.safeParse({ ...validBody, lat: -90.1 });
      expect(result.success).toBe(false);
    });

    it('rejects lat above 90', () => {
      const result = createReportSchema.safeParse({ ...validBody, lat: 90.1 });
      expect(result.success).toBe(false);
    });

    it('accepts lat at boundaries (-90, 90)', () => {
      expect(createReportSchema.safeParse({ ...validBody, lat: -90 }).success).toBe(true);
      expect(createReportSchema.safeParse({ ...validBody, lat: 90 }).success).toBe(true);
    });

    it('rejects lng below -180', () => {
      const result = createReportSchema.safeParse({ ...validBody, lng: -180.1 });
      expect(result.success).toBe(false);
    });

    it('rejects lng above 180', () => {
      const result = createReportSchema.safeParse({ ...validBody, lng: 180.1 });
      expect(result.success).toBe(false);
    });

    it('accepts lng at boundaries (-180, 180)', () => {
      expect(createReportSchema.safeParse({ ...validBody, lng: -180 }).success).toBe(true);
      expect(createReportSchema.safeParse({ ...validBody, lng: 180 }).success).toBe(true);
    });

    it('rejects non-numeric lat', () => {
      const result = createReportSchema.safeParse({ ...validBody, lat: 'abc' });
      expect(result.success).toBe(false);
    });

    it('rejects non-numeric lng', () => {
      const result = createReportSchema.safeParse({ ...validBody, lng: null });
      expect(result.success).toBe(false);
    });

    it('rejects missing type', () => {
      const { type, ...noType } = validBody;
      const result = createReportSchema.safeParse(noType);
      expect(result.success).toBe(false);
    });

    it('rejects missing lat', () => {
      const { lat, ...noLat } = validBody;
      const result = createReportSchema.safeParse(noLat);
      expect(result.success).toBe(false);
    });

    it('rejects missing lng', () => {
      const { lng, ...noLng } = validBody;
      const result = createReportSchema.safeParse(noLng);
      expect(result.success).toBe(false);
    });

    it('rejects missing device_id', () => {
      const { device_id, ...noDevice } = validBody;
      const result = createReportSchema.safeParse(noDevice);
      expect(result.success).toBe(false);
    });

    it('rejects description exceeding 2000 characters', () => {
      const result = createReportSchema.safeParse({
        ...validBody,
        description: 'a'.repeat(2001),
      });
      expect(result.success).toBe(false);
    });

    it('accepts description at max length (2000)', () => {
      const result = createReportSchema.safeParse({
        ...validBody,
        description: 'a'.repeat(2000),
      });
      expect(result.success).toBe(true);
    });

    it('rejects address exceeding 255 characters', () => {
      const result = createReportSchema.safeParse({
        ...validBody,
        address: 'a'.repeat(256),
      });
      expect(result.success).toBe(false);
    });

    it('accepts address at max length (255)', () => {
      const result = createReportSchema.safeParse({
        ...validBody,
        address: 'a'.repeat(255),
      });
      expect(result.success).toBe(true);
    });
  });

  describe('nearbyQuerySchema', () => {
    const validQuery = { lat: '40.7128', lng: '-74.006' };

    it('accepts valid query with defaults', () => {
      const result = nearbyQuerySchema.safeParse(validQuery);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.radius).toBe(5000);
        expect(result.data.limit).toBe(20);
        expect(result.data.offset).toBe(0);
      }
    });

    it('coerces string values to numbers', () => {
      const result = nearbyQuerySchema.safeParse({
        lat: '40.7128',
        lng: '-74.006',
        radius: '3000',
        limit: '10',
        offset: '5',
      });
      expect(result.success).toBe(true);
      if (result.success) {
        expect(typeof result.data.lat).toBe('number');
        expect(typeof result.data.lng).toBe('number');
        expect(typeof result.data.radius).toBe('number');
        expect(typeof result.data.limit).toBe('number');
        expect(typeof result.data.offset).toBe('number');
      }
    });

    it('rejects radius below 100', () => {
      const result = nearbyQuerySchema.safeParse({ ...validQuery, radius: '99' });
      expect(result.success).toBe(false);
    });

    it('rejects radius above 50000', () => {
      const result = nearbyQuerySchema.safeParse({ ...validQuery, radius: '50001' });
      expect(result.success).toBe(false);
    });

    it('accepts radius at boundaries (100, 50000)', () => {
      expect(nearbyQuerySchema.safeParse({ ...validQuery, radius: '100' }).success).toBe(true);
      expect(nearbyQuerySchema.safeParse({ ...validQuery, radius: '50000' }).success).toBe(true);
    });

    it('rejects limit below 1', () => {
      const result = nearbyQuerySchema.safeParse({ ...validQuery, limit: '0' });
      expect(result.success).toBe(false);
    });

    it('rejects limit above 100', () => {
      const result = nearbyQuerySchema.safeParse({ ...validQuery, limit: '101' });
      expect(result.success).toBe(false);
    });

    it('accepts limit at boundaries (1, 100)', () => {
      expect(nearbyQuerySchema.safeParse({ ...validQuery, limit: '1' }).success).toBe(true);
      expect(nearbyQuerySchema.safeParse({ ...validQuery, limit: '100' }).success).toBe(true);
    });

    it('rejects negative offset', () => {
      const result = nearbyQuerySchema.safeParse({ ...validQuery, offset: '-1' });
      expect(result.success).toBe(false);
    });

    it('accepts offset of 0', () => {
      const result = nearbyQuerySchema.safeParse({ ...validQuery, offset: '0' });
      expect(result.success).toBe(true);
    });

    it('rejects non-numeric lat string', () => {
      const result = nearbyQuerySchema.safeParse({ lat: 'abc', lng: '-74.006' });
      expect(result.success).toBe(false);
    });

    it('rejects missing lat', () => {
      const result = nearbyQuerySchema.safeParse({ lng: '-74.006' });
      expect(result.success).toBe(false);
    });

    it('rejects missing lng', () => {
      const result = nearbyQuerySchema.safeParse({ lat: '40.7128' });
      expect(result.success).toBe(false);
    });

    it('rejects non-integer limit', () => {
      const result = nearbyQuerySchema.safeParse({ ...validQuery, limit: '10.5' });
      expect(result.success).toBe(false);
    });

    it('rejects non-integer offset', () => {
      const result = nearbyQuerySchema.safeParse({ ...validQuery, offset: '5.5' });
      expect(result.success).toBe(false);
    });
  });

  describe('upvoteSchema', () => {
    it('accepts valid device_id', () => {
      const result = upvoteSchema.safeParse({ device_id: 'device-123' });
      expect(result.success).toBe(true);
    });

    it('rejects empty device_id', () => {
      const result = upvoteSchema.safeParse({ device_id: '' });
      expect(result.success).toBe(false);
    });

    it('rejects device_id exceeding 64 characters', () => {
      const result = upvoteSchema.safeParse({ device_id: 'x'.repeat(65) });
      expect(result.success).toBe(false);
    });

    it('accepts device_id at max length (64)', () => {
      const result = upvoteSchema.safeParse({ device_id: 'x'.repeat(64) });
      expect(result.success).toBe(true);
    });

    it('rejects missing device_id', () => {
      const result = upvoteSchema.safeParse({});
      expect(result.success).toBe(false);
    });

    it('rejects non-string device_id', () => {
      const result = upvoteSchema.safeParse({ device_id: 12345 });
      expect(result.success).toBe(false);
    });
  });

  describe('CRIME_TYPES constant', () => {
    it('contains expected types', () => {
      expect(CRIME_TYPES).toContain('theft');
      expect(CRIME_TYPES).toContain('assault');
      expect(CRIME_TYPES).toContain('vandalism');
      expect(CRIME_TYPES).toContain('robbery');
      expect(CRIME_TYPES).toContain('other');
    });

    it('has 11 types', () => {
      expect(CRIME_TYPES).toHaveLength(11);
    });
  });
});
