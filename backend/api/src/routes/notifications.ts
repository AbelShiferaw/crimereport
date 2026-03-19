import { Router, Request, Response } from 'express';
import { validate } from '../middleware/validate';
import { writeLimiter } from '../middleware/rate-limit';
import {
  registerDeviceSchema,
  unregisterDeviceSchema,
  updatePreferencesSchema,
} from '../validators/push-subscription';
import { HttpError } from '../lib/errors';
import * as pushModel from '../models/push-subscription';
import * as sns from '../lib/sns';
import { logger } from '../lib/logger';

const router = Router();

router.post(
  '/register',
  writeLimiter,
  validate(registerDeviceSchema),
  async (req: Request, res: Response) => {
    const { device_id, fcm_token, platform, lat, lng } = req.body;

    const endpointArn = await sns.createEndpoint(platform, fcm_token, device_id);
    const subscription = await pushModel.upsert(
      { device_id, fcm_token, platform, lat, lng },
      endpointArn,
    );

    logger.info({ device_id, platform }, 'device registered for push');
    res.status(201).json(subscription);
  },
);

router.delete(
  '/unregister',
  writeLimiter,
  validate(unregisterDeviceSchema),
  async (req: Request, res: Response) => {
    const { device_id } = req.body;

    const endpointArn = await pushModel.remove(device_id);
    if (endpointArn) {
      await sns.deleteEndpoint(endpointArn).catch((err) =>
        logger.error({ err, endpointArn }, 'failed to delete SNS endpoint'),
      );
    }

    logger.info({ device_id }, 'device unregistered from push');
    res.json({ message: 'Device unregistered' });
  },
);

router.put(
  '/preferences',
  writeLimiter,
  validate(updatePreferencesSchema),
  async (req: Request, res: Response) => {
    const { device_id, enabled, radius, types } = req.body;

    const updated = await pushModel.updatePreferences(device_id, {
      enabled,
      radius,
      types,
    });

    if (!updated) {
      throw HttpError.notFound('No push subscription found for this device');
    }

    res.json(updated);
  },
);

export default router;
