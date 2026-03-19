const mockSend = jest.fn();

jest.mock('@aws-sdk/client-sns', () => ({
  SNSClient: jest.fn().mockImplementation(() => ({ send: mockSend })),
  CreatePlatformEndpointCommand: jest.fn().mockImplementation((input) => ({ input })),
  PublishCommand: jest.fn().mockImplementation((input) => ({ input })),
  DeleteEndpointCommand: jest.fn().mockImplementation((input) => ({ input })),
}));

jest.mock('../../config', () => ({
  config: {
    aws: {
      region: 'us-east-1',
      snsAndroidArn: 'arn:aws:sns:us-east-1:123:app/GCM/android',
      snsIosArn: 'arn:aws:sns:us-east-1:123:app/APNS/ios',
    },
  },
}));

jest.mock('../../lib/logger', () => ({
  logger: { warn: jest.fn(), error: jest.fn(), info: jest.fn() },
}));

import { createEndpoint, deleteEndpoint, sendToDevice } from '../../lib/sns';

describe('sns lib', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('createEndpoint', () => {
    it('returns EndpointArn for android', async () => {
      mockSend.mockResolvedValueOnce({ EndpointArn: 'arn:endpoint/android' });
      const result = await createEndpoint('android', 'fcm-token', 'dev-1');
      expect(result).toBe('arn:endpoint/android');
    });

    it('throws when SNS returns no EndpointArn', async () => {
      mockSend.mockResolvedValueOnce({});
      await expect(createEndpoint('ios', 'token', 'dev-1')).rejects.toThrow(
        'SNS returned no EndpointArn',
      );
    });
  });

  describe('deleteEndpoint', () => {
    it('calls SNS delete', async () => {
      mockSend.mockResolvedValueOnce({});
      await expect(deleteEndpoint('arn:endpoint')).resolves.not.toThrow();
      expect(mockSend).toHaveBeenCalledTimes(1);
    });
  });

  describe('sendToDevice', () => {
    const notification = {
      title: 'Theft Nearby',
      body: 'A theft was reported near you',
      data: { report_id: 'r-1', type: 'theft', lat: '40.71', lng: '-74.0' },
    };

    it('returns true on success for android', async () => {
      mockSend.mockResolvedValueOnce({});
      const ok = await sendToDevice('arn:endpoint', 'android', notification);
      expect(ok).toBe(true);
    });

    it('returns true on success for ios', async () => {
      mockSend.mockResolvedValueOnce({});
      const ok = await sendToDevice('arn:endpoint', 'ios', notification);
      expect(ok).toBe(true);
    });

    it('returns false for EndpointDisabledException', async () => {
      mockSend.mockRejectedValueOnce({ name: 'EndpointDisabledException' });
      const ok = await sendToDevice('arn:endpoint', 'android', notification);
      expect(ok).toBe(false);
    });

    it('returns false for unexpected errors', async () => {
      mockSend.mockRejectedValueOnce(new Error('NetworkError'));
      const ok = await sendToDevice('arn:endpoint', 'android', notification);
      expect(ok).toBe(false);
    });
  });
});
