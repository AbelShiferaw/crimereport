import { createMetricsLogger, Unit, MetricsLogger } from 'aws-embedded-metrics';
import { logger } from './logger';

const NAMESPACE = 'CrimeReport';
const SERVICE_DIMENSION = 'api';

function createLogger(): MetricsLogger {
  const metrics = createMetricsLogger();
  metrics.setNamespace(NAMESPACE);
  metrics.putDimensions({ Service: SERVICE_DIMENSION });
  return metrics;
}

async function safeFlush(metrics: MetricsLogger): Promise<void> {
  try {
    await metrics.flush();
  } catch (err) {
    logger.warn({ err }, 'failed to flush EMF metrics');
  }
}

export async function recordReportCreated(crimeType: string): Promise<void> {
  const metrics = createLogger();
  metrics.putDimensions({ CrimeType: crimeType });
  metrics.putMetric('ReportsCreated', 1, Unit.Count);
  await safeFlush(metrics);
}

export async function recordMediaUploadCompleted(): Promise<void> {
  const metrics = createLogger();
  metrics.putMetric('MediaUploadsCompleted', 1, Unit.Count);
  await safeFlush(metrics);
}

export async function recordMediaFailure(): Promise<void> {
  const metrics = createLogger();
  metrics.putMetric('MediaFailureRate', 1, Unit.Count);
  await safeFlush(metrics);
}

export async function recordMediaProcessingLatency(durationMs: number): Promise<void> {
  const metrics = createLogger();
  metrics.putMetric('MediaProcessingLatency', durationMs, Unit.Milliseconds);
  await safeFlush(metrics);
}

export async function recordWebSocketConnections(count: number): Promise<void> {
  const metrics = createLogger();
  metrics.putMetric('WebSocketConnections', count, Unit.Count);
  await safeFlush(metrics);
}

export async function recordRateLimitHit(limiterName: string): Promise<void> {
  const metrics = createLogger();
  metrics.putDimensions({ Limiter: limiterName });
  metrics.putMetric('RateLimitHits', 1, Unit.Count);
  await safeFlush(metrics);
}

export { NAMESPACE, SERVICE_DIMENSION };
