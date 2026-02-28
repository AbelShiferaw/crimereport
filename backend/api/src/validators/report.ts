import { z } from 'zod';

export const CRIME_TYPES = [
  'theft',
  'assault',
  'vandalism',
  'robbery',
  'burglary',
  'suspicious',
  'shooting',
  'carjacking',
  'harassment',
  'drug_activity',
  'other',
] as const;

export const createReportSchema = z.object({
  device_id: z.string().min(1).max(64),
  type: z.enum(CRIME_TYPES),
  description: z.string().max(2000).optional(),
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  address: z.string().max(255).optional(),
});

export const nearbyQuerySchema = z.object({
  lat: z.coerce.number().min(-90).max(90),
  lng: z.coerce.number().min(-180).max(180),
  radius: z.coerce.number().min(100).max(50_000).default(5_000),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  offset: z.coerce.number().int().min(0).default(0),
});

export const upvoteSchema = z.object({
  device_id: z.string().min(1).max(64),
});

export type CreateReportBody = z.infer<typeof createReportSchema>;
export type NearbyQuery = z.infer<typeof nearbyQuerySchema>;
export type UpvoteBody = z.infer<typeof upvoteSchema>;
