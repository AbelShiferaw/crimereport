import { createMetricsLogger, Unit } from 'aws-embedded-metrics';

jest.mock('aws-embedded-metrics');

const mockFlush = jest.fn().mockResolvedValue(undefined);
const mockPutMetric = jest.fn();
const mockPutDimensions = jest.fn();
const mockSetNamespace = jest.fn();

const mockLogger = {
  flush: mockFlush,
  putMetric: mockPutMetric,
  putDimensions: mockPutDimensions,
  setNamespace: mockSetNamespace,
};

(createMetricsLogger as jest.Mock).mockReturnValue(mockLogger);

import {
  recordReportCreated,
  recordMediaUploadCompleted,
  recordMediaFailure,
  recordMediaProcessingLatency,
  recordWebSocketConnections,
  recordRateLimitHit,
  NAMESPACE,
  SERVICE_DIMENSION,
} from '../../lib/metrics';

beforeEach(() => {
  jest.clearAllMocks();
  (createMetricsLogger as jest.Mock).mockReturnValue(mockLogger);
});

describe('metrics helper', () => {
  describe('constants', () => {
    it('exports correct namespace', () => {
      expect(NAMESPACE).toBe('CrimeReport');
    });

    it('exports correct service dimension', () => {
      expect(SERVICE_DIMENSION).toBe('api');
    });
  });

  describe('recordReportCreated', () => {
    it('emits ReportsCreated metric with crime type dimension', async () => {
      await recordReportCreated('theft');

      expect(mockSetNamespace).toHaveBeenCalledWith('CrimeReport');
      expect(mockPutDimensions).toHaveBeenCalledWith({ Service: 'api' });
      expect(mockPutDimensions).toHaveBeenCalledWith({ CrimeType: 'theft' });
      expect(mockPutMetric).toHaveBeenCalledWith('ReportsCreated', 1, Unit.Count);
      expect(mockFlush).toHaveBeenCalledTimes(1);
    });

    it('works with different crime types', async () => {
      await recordReportCreated('vandalism');

      expect(mockPutDimensions).toHaveBeenCalledWith({ CrimeType: 'vandalism' });
      expect(mockPutMetric).toHaveBeenCalledWith('ReportsCreated', 1, Unit.Count);
    });
  });

  describe('recordMediaUploadCompleted', () => {
    it('emits MediaUploadsCompleted metric', async () => {
      await recordMediaUploadCompleted();

      expect(mockSetNamespace).toHaveBeenCalledWith('CrimeReport');
      expect(mockPutMetric).toHaveBeenCalledWith('MediaUploadsCompleted', 1, Unit.Count);
      expect(mockFlush).toHaveBeenCalledTimes(1);
    });
  });

  describe('recordMediaFailure', () => {
    it('emits MediaFailureRate metric', async () => {
      await recordMediaFailure();

      expect(mockPutMetric).toHaveBeenCalledWith('MediaFailureRate', 1, Unit.Count);
      expect(mockFlush).toHaveBeenCalledTimes(1);
    });
  });

  describe('recordMediaProcessingLatency', () => {
    it('emits MediaProcessingLatency with duration in milliseconds', async () => {
      await recordMediaProcessingLatency(1500);

      expect(mockPutMetric).toHaveBeenCalledWith('MediaProcessingLatency', 1500, Unit.Milliseconds);
      expect(mockFlush).toHaveBeenCalledTimes(1);
    });

    it('handles zero latency', async () => {
      await recordMediaProcessingLatency(0);

      expect(mockPutMetric).toHaveBeenCalledWith('MediaProcessingLatency', 0, Unit.Milliseconds);
    });
  });

  describe('recordWebSocketConnections', () => {
    it('emits WebSocketConnections gauge', async () => {
      await recordWebSocketConnections(42);

      expect(mockPutMetric).toHaveBeenCalledWith('WebSocketConnections', 42, Unit.Count);
      expect(mockFlush).toHaveBeenCalledTimes(1);
    });

    it('emits zero when no connections', async () => {
      await recordWebSocketConnections(0);

      expect(mockPutMetric).toHaveBeenCalledWith('WebSocketConnections', 0, Unit.Count);
    });
  });

  describe('recordRateLimitHit', () => {
    it('emits RateLimitHits metric with limiter dimension', async () => {
      await recordRateLimitHit('global');

      expect(mockPutDimensions).toHaveBeenCalledWith({ Limiter: 'global' });
      expect(mockPutMetric).toHaveBeenCalledWith('RateLimitHits', 1, Unit.Count);
      expect(mockFlush).toHaveBeenCalledTimes(1);
    });

    it('distinguishes write limiter', async () => {
      await recordRateLimitHit('write');

      expect(mockPutDimensions).toHaveBeenCalledWith({ Limiter: 'write' });
    });
  });

  describe('flush error handling', () => {
    it('does not throw when flush fails', async () => {
      mockFlush.mockRejectedValueOnce(new Error('CloudWatch unavailable'));

      await expect(recordReportCreated('theft')).resolves.toBeUndefined();
    });

    it('swallows flush errors for all metric types', async () => {
      mockFlush.mockRejectedValue(new Error('network error'));

      await expect(recordMediaUploadCompleted()).resolves.toBeUndefined();
      await expect(recordMediaFailure()).resolves.toBeUndefined();
      await expect(recordMediaProcessingLatency(100)).resolves.toBeUndefined();
      await expect(recordWebSocketConnections(5)).resolves.toBeUndefined();
      await expect(recordRateLimitHit('global')).resolves.toBeUndefined();
    });
  });
});
