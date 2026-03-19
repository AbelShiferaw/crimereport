import {
  SNSClient,
  CreatePlatformEndpointCommand,
  PublishCommand,
  DeleteEndpointCommand,
} from '@aws-sdk/client-sns';
import { config } from '../config';
import { logger } from './logger';

const sns = new SNSClient({ region: config.aws.region });

export async function createEndpoint(
  platform: 'ios' | 'android',
  fcmToken: string,
  deviceId: string,
): Promise<string> {
  const platformArn =
    platform === 'ios' ? config.aws.snsIosArn : config.aws.snsAndroidArn;

  const { EndpointArn } = await sns.send(
    new CreatePlatformEndpointCommand({
      PlatformApplicationArn: platformArn,
      Token: fcmToken,
      CustomUserData: deviceId,
    }),
  );

  if (!EndpointArn) throw new Error('SNS returned no EndpointArn');
  return EndpointArn;
}

export async function deleteEndpoint(endpointArn: string): Promise<void> {
  await sns.send(new DeleteEndpointCommand({ EndpointArn: endpointArn }));
}

export async function sendToDevice(
  endpointArn: string,
  platform: 'ios' | 'android',
  notification: { title: string; body: string; data: Record<string, string> },
): Promise<boolean> {
  try {
    const apnsPayload = JSON.stringify({
      aps: {
        alert: { title: notification.title, body: notification.body },
        sound: 'default',
        badge: 1,
      },
      data: notification.data,
    });

    const message =
      platform === 'ios'
        ? {
            APNS: apnsPayload,
            APNS_SANDBOX: apnsPayload,
          }
        : {
            GCM: JSON.stringify({
              notification: {
                title: notification.title,
                body: notification.body,
              },
              data: notification.data,
            }),
          };

    await sns.send(
      new PublishCommand({
        TargetArn: endpointArn,
        Message: JSON.stringify(message),
        MessageStructure: 'json',
      }),
    );
    return true;
  } catch (err: any) {
    if (err.name === 'EndpointDisabledException') {
      logger.warn({ endpointArn }, 'SNS endpoint disabled');
      return false;
    }
    logger.error({ err, endpointArn }, 'SNS publish failed');
    return false;
  }
}
