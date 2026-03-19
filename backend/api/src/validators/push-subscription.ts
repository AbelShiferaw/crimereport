import { z } from 'zod';
import { CRIME_TYPES } from './report';

export const registerDeviceSchema = z.object({
  device_id: z.string().min(1).max(64),
  fcm_token: z.string().min(1).max(500),
  platform: z.enum(['ios', 'android']),
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
});

export const unregisterDeviceSchema = z.object({
  device_id: z.string().min(1).max(64),
});

export const updatePreferencesSchema = z.object({
  device_id: z.string().min(1).max(64),
  enabled: z.boolean().optional(),
  radius: z.number().int().min(1_000).max(50_000).optional(),
  types: z.array(z.enum(CRIME_TYPES)).optional(),
});

export type RegisterDeviceBody = z.infer<typeof registerDeviceSchema>;
export type UnregisterDeviceBody = z.infer<typeof unregisterDeviceSchema>;
export type UpdatePreferencesBody = z.infer<typeof updatePreferencesSchema>;
