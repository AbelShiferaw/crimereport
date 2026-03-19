import { query } from '../lib/db';
import {
  PushSubscription,
  CreatePushSubscriptionInput,
  UpdatePushPreferencesInput,
} from './types';

export async function findByDeviceId(deviceId: string): Promise<PushSubscription | null> {
  const { rows } = await query<PushSubscription>(
    `SELECT device_id, fcm_token, platform, endpoint_arn,
            ST_Y(location::geometry) AS lat,
            ST_X(location::geometry) AS lng,
            radius, types, enabled, created_at, updated_at
     FROM push_subscriptions WHERE device_id = $1`,
    [deviceId],
  );
  return rows[0] ?? null;
}

export async function upsert(
  input: CreatePushSubscriptionInput,
  endpointArn: string,
): Promise<PushSubscription> {
  const { rows } = await query<PushSubscription>(
    `INSERT INTO push_subscriptions (device_id, fcm_token, platform, endpoint_arn, location)
     VALUES ($1, $2, $3, $4, ST_SetSRID(ST_MakePoint($6, $5), 4326)::geography)
     ON CONFLICT (device_id) DO UPDATE SET
       fcm_token    = EXCLUDED.fcm_token,
       endpoint_arn = EXCLUDED.endpoint_arn,
       location     = EXCLUDED.location,
       updated_at   = NOW()
     RETURNING device_id, fcm_token, platform, endpoint_arn,
               ST_Y(location::geometry) AS lat,
               ST_X(location::geometry) AS lng,
               radius, types, enabled, created_at, updated_at`,
    [input.device_id, input.fcm_token, input.platform, endpointArn, input.lat, input.lng],
  );
  return rows[0];
}

export async function remove(deviceId: string): Promise<string | null> {
  const { rows } = await query<{ endpoint_arn: string | null }>(
    'DELETE FROM push_subscriptions WHERE device_id = $1 RETURNING endpoint_arn',
    [deviceId],
  );
  return rows[0]?.endpoint_arn ?? null;
}

export async function updatePreferences(
  deviceId: string,
  input: UpdatePushPreferencesInput,
): Promise<PushSubscription | null> {
  const { rows } = await query<PushSubscription>(
    `UPDATE push_subscriptions SET
       enabled    = COALESCE($2, enabled),
       radius     = COALESCE($3, radius),
       types      = COALESCE($4, types),
       updated_at = NOW()
     WHERE device_id = $1
     RETURNING device_id, fcm_token, platform, endpoint_arn,
               ST_Y(location::geometry) AS lat,
               ST_X(location::geometry) AS lng,
               radius, types, enabled, created_at, updated_at`,
    [deviceId, input.enabled ?? null, input.radius ?? null, input.types ?? null],
  );
  return rows[0] ?? null;
}

export async function findNearbyEnabled(
  lat: number,
  lng: number,
  type: string,
  excludeDeviceId: string,
): Promise<PushSubscription[]> {
  const { rows } = await query<PushSubscription>(
    `SELECT device_id, fcm_token, platform, endpoint_arn,
            ST_Y(location::geometry) AS lat,
            ST_X(location::geometry) AS lng,
            radius, types, enabled, created_at, updated_at
     FROM push_subscriptions
     WHERE enabled = true
       AND device_id != $4
       AND ST_DWithin(
             location,
             ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography,
             radius
           )
       AND (types IS NULL OR $3 = ANY(types))`,
    [lat, lng, type, excludeDeviceId],
  );
  return rows;
}

export async function disableByEndpointArn(endpointArn: string): Promise<void> {
  await query(
    'UPDATE push_subscriptions SET enabled = false, updated_at = NOW() WHERE endpoint_arn = $1',
    [endpointArn],
  );
}
