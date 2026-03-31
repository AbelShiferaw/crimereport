import { registerDeviceSchema, unregisterDeviceSchema, updatePreferencesSchema } from '../../validators/push-subscription';

describe('push-subscription validators', () => {
  describe('registerDeviceSchema', () => {
    const validBody = {
      device_id: 'device-123',
      fcm_token: 'fcm-token-abc-xyz',
      platform: 'android' as const,
      lat: 40.7128,
      lng: -74.006,
    };

    it('accepts valid registration body', () => {
      const result = registerDeviceSchema.safeParse(validBody);
      expect(result.success).toBe(true);
    });

    it('accepts ios platform', () => {
      const result = registerDeviceSchema.safeParse({ ...validBody, platform: 'ios' });
      expect(result.success).toBe(true);
    });

    it('accepts android platform', () => {
      const result = registerDeviceSchema.safeParse({ ...validBody, platform: 'android' });
      expect(result.success).toBe(true);
    });

    it('rejects invalid platform', () => {
      const result = registerDeviceSchema.safeParse({ ...validBody, platform: 'web' });
      expect(result.success).toBe(false);
    });

    it('rejects empty device_id', () => {
      const result = registerDeviceSchema.safeParse({ ...validBody, device_id: '' });
      expect(result.success).toBe(false);
    });

    it('rejects device_id longer than 64 characters', () => {
      const result = registerDeviceSchema.safeParse({
        ...validBody,
        device_id: 'x'.repeat(65),
      });
      expect(result.success).toBe(false);
    });

    it('rejects empty fcm_token', () => {
      const result = registerDeviceSchema.safeParse({ ...validBody, fcm_token: '' });
      expect(result.success).toBe(false);
    });

    it('rejects fcm_token longer than 500 characters', () => {
      const result = registerDeviceSchema.safeParse({
        ...validBody,
        fcm_token: 'x'.repeat(501),
      });
      expect(result.success).toBe(false);
    });

    it('accepts fcm_token at max length (500)', () => {
      const result = registerDeviceSchema.safeParse({
        ...validBody,
        fcm_token: 'x'.repeat(500),
      });
      expect(result.success).toBe(true);
    });

    it('rejects lat below -90', () => {
      const result = registerDeviceSchema.safeParse({ ...validBody, lat: -90.1 });
      expect(result.success).toBe(false);
    });

    it('rejects lat above 90', () => {
      const result = registerDeviceSchema.safeParse({ ...validBody, lat: 90.1 });
      expect(result.success).toBe(false);
    });

    it('accepts lat at boundaries (-90, 90)', () => {
      expect(registerDeviceSchema.safeParse({ ...validBody, lat: -90 }).success).toBe(true);
      expect(registerDeviceSchema.safeParse({ ...validBody, lat: 90 }).success).toBe(true);
    });

    it('rejects lng below -180', () => {
      const result = registerDeviceSchema.safeParse({ ...validBody, lng: -180.1 });
      expect(result.success).toBe(false);
    });

    it('rejects lng above 180', () => {
      const result = registerDeviceSchema.safeParse({ ...validBody, lng: 180.1 });
      expect(result.success).toBe(false);
    });

    it('accepts lng at boundaries (-180, 180)', () => {
      expect(registerDeviceSchema.safeParse({ ...validBody, lng: -180 }).success).toBe(true);
      expect(registerDeviceSchema.safeParse({ ...validBody, lng: 180 }).success).toBe(true);
    });

    it('rejects non-numeric lat', () => {
      const result = registerDeviceSchema.safeParse({ ...validBody, lat: 'abc' });
      expect(result.success).toBe(false);
    });

    it('rejects non-numeric lng', () => {
      const result = registerDeviceSchema.safeParse({ ...validBody, lng: 'abc' });
      expect(result.success).toBe(false);
    });

    it('rejects missing fcm_token', () => {
      const { fcm_token, ...rest } = validBody;
      const result = registerDeviceSchema.safeParse(rest);
      expect(result.success).toBe(false);
    });

    it('rejects missing platform', () => {
      const { platform, ...rest } = validBody;
      const result = registerDeviceSchema.safeParse(rest);
      expect(result.success).toBe(false);
    });

    it('rejects missing lat', () => {
      const { lat, ...rest } = validBody;
      const result = registerDeviceSchema.safeParse(rest);
      expect(result.success).toBe(false);
    });

    it('rejects missing lng', () => {
      const { lng, ...rest } = validBody;
      const result = registerDeviceSchema.safeParse(rest);
      expect(result.success).toBe(false);
    });

    it('rejects null values', () => {
      const result = registerDeviceSchema.safeParse({
        ...validBody,
        device_id: null,
      });
      expect(result.success).toBe(false);
    });
  });

  describe('unregisterDeviceSchema', () => {
    it('accepts valid device_id', () => {
      const result = unregisterDeviceSchema.safeParse({ device_id: 'device-123' });
      expect(result.success).toBe(true);
    });

    it('rejects empty device_id', () => {
      const result = unregisterDeviceSchema.safeParse({ device_id: '' });
      expect(result.success).toBe(false);
    });

    it('rejects device_id longer than 64 characters', () => {
      const result = unregisterDeviceSchema.safeParse({ device_id: 'x'.repeat(65) });
      expect(result.success).toBe(false);
    });

    it('accepts device_id at max length (64)', () => {
      const result = unregisterDeviceSchema.safeParse({ device_id: 'x'.repeat(64) });
      expect(result.success).toBe(true);
    });

    it('rejects missing device_id', () => {
      const result = unregisterDeviceSchema.safeParse({});
      expect(result.success).toBe(false);
    });

    it('rejects non-string device_id', () => {
      const result = unregisterDeviceSchema.safeParse({ device_id: 12345 });
      expect(result.success).toBe(false);
    });
  });

  describe('updatePreferencesSchema', () => {
    it('accepts device_id alone (all optional fields omitted)', () => {
      const result = updatePreferencesSchema.safeParse({ device_id: 'device-123' });
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.enabled).toBeUndefined();
        expect(result.data.radius).toBeUndefined();
        expect(result.data.types).toBeUndefined();
      }
    });

    it('accepts enabled boolean', () => {
      const result = updatePreferencesSchema.safeParse({
        device_id: 'dev-1',
        enabled: false,
      });
      expect(result.success).toBe(true);
      if (result.success) expect(result.data.enabled).toBe(false);
    });

    it('accepts radius within range', () => {
      const result = updatePreferencesSchema.safeParse({
        device_id: 'dev-1',
        radius: 10000,
      });
      expect(result.success).toBe(true);
    });

    it('rejects radius below 1000', () => {
      const result = updatePreferencesSchema.safeParse({
        device_id: 'dev-1',
        radius: 999,
      });
      expect(result.success).toBe(false);
    });

    it('rejects radius above 50000', () => {
      const result = updatePreferencesSchema.safeParse({
        device_id: 'dev-1',
        radius: 50001,
      });
      expect(result.success).toBe(false);
    });

    it('accepts radius at boundaries (1000, 50000)', () => {
      expect(
        updatePreferencesSchema.safeParse({ device_id: 'd', radius: 1000 }).success,
      ).toBe(true);
      expect(
        updatePreferencesSchema.safeParse({ device_id: 'd', radius: 50000 }).success,
      ).toBe(true);
    });

    it('rejects non-integer radius', () => {
      const result = updatePreferencesSchema.safeParse({
        device_id: 'dev-1',
        radius: 10000.5,
      });
      expect(result.success).toBe(false);
    });

    it('accepts types array with valid crime types', () => {
      const result = updatePreferencesSchema.safeParse({
        device_id: 'dev-1',
        types: ['theft', 'assault', 'robbery'],
      });
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.types).toEqual(['theft', 'assault', 'robbery']);
      }
    });

    it('rejects types array with invalid crime type', () => {
      const result = updatePreferencesSchema.safeParse({
        device_id: 'dev-1',
        types: ['theft', 'arson'],
      });
      expect(result.success).toBe(false);
    });

    it('accepts empty types array', () => {
      const result = updatePreferencesSchema.safeParse({
        device_id: 'dev-1',
        types: [],
      });
      expect(result.success).toBe(true);
    });

    it('accepts all optional fields together', () => {
      const result = updatePreferencesSchema.safeParse({
        device_id: 'dev-1',
        enabled: true,
        radius: 15000,
        types: ['theft', 'vandalism'],
      });
      expect(result.success).toBe(true);
    });

    it('rejects non-boolean enabled', () => {
      const result = updatePreferencesSchema.safeParse({
        device_id: 'dev-1',
        enabled: 'yes',
      });
      expect(result.success).toBe(false);
    });

    it('rejects empty device_id', () => {
      const result = updatePreferencesSchema.safeParse({ device_id: '' });
      expect(result.success).toBe(false);
    });

    it('rejects missing device_id', () => {
      const result = updatePreferencesSchema.safeParse({ enabled: true });
      expect(result.success).toBe(false);
    });

    it('rejects non-array types', () => {
      const result = updatePreferencesSchema.safeParse({
        device_id: 'dev-1',
        types: 'theft',
      });
      expect(result.success).toBe(false);
    });
  });
});
