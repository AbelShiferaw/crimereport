import { query } from '../lib/db';
import { DeviceActivity } from './types';

export async function getOrCreate(deviceId: string): Promise<DeviceActivity> {
  const { rows } = await query<DeviceActivity>(
    `INSERT INTO device_activity (device_id)
     VALUES ($1)
     ON CONFLICT (device_id) DO UPDATE SET device_id = EXCLUDED.device_id
     RETURNING device_id, report_count_today, last_report_at, flagged, created_at`,
    [deviceId],
  );
  return rows[0];
}

export async function incrementReportCount(deviceId: string): Promise<DeviceActivity> {
  const { rows } = await query<DeviceActivity>(
    `UPDATE device_activity
     SET report_count_today = report_count_today + 1,
         last_report_at = NOW()
     WHERE device_id = $1
     RETURNING device_id, report_count_today, last_report_at, flagged, created_at`,
    [deviceId],
  );
  return rows[0];
}

export async function flag(deviceId: string, flagged: boolean): Promise<void> {
  await query(
    'UPDATE device_activity SET flagged = $2 WHERE device_id = $1',
    [deviceId, flagged],
  );
}

export async function resetDailyCounts(): Promise<number> {
  const result = await query(
    'UPDATE device_activity SET report_count_today = 0 WHERE report_count_today > 0',
  );
  return result.rowCount ?? 0;
}
