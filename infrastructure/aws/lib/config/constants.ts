export const PROJECT_NAME = 'crimereport';
export const PROJECT_PREFIX = 'crimereport';

export const VPC_CIDR = '10.0.0.0/16';
export const MAX_AZS = 2;
export const NAT_GATEWAYS = 1;

export const API_PORT = 3000;
export const DB_PORT = 5432;
export const REDIS_PORT = 6379;

export const WAF_RATE_LIMIT = 2000;

export const DEFAULT_TAGS: Record<string, string> = {
  Project: 'CrimeReport',
  ManagedBy: 'CDK',
};
