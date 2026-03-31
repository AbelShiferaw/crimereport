export const PROJECT_NAME = 'crimereport';
export const PROJECT_PREFIX = 'crimereport';

export const VPC_CIDR = '10.0.0.0/16';
export const MAX_AZS = 2;
export const NAT_GATEWAYS = 1;

export const API_PORT = 3000;
export const DB_PORT = 5432;
export const REDIS_PORT = 6379;

export const WAF_RATE_LIMIT = 2000;

export const DB_NAME = 'crimereport';
export const DB_ADMIN_USER = 'crimereport_admin';
export const DB_MIN_ACU = 0.5;
export const DB_MAX_ACU = 8;

export const REDIS_NODE_TYPE = 'cache.t4g.micro';

export const ECS_CPU = 512;
export const ECS_MEMORY = 1024;
export const ECS_DESIRED_COUNT = 2;
export const ECS_MIN_TASKS = 2;
export const ECS_MAX_TASKS = 10;
export const ECS_CPU_TARGET_PERCENT = 70;
export const ECR_MAX_IMAGE_COUNT = 10;
export const LOG_RETENTION_DAYS = 30;

export const DB_BACKUP_RETENTION_DAYS = 7;
export const ALARM_EMAIL = 'ops@reportcrime.app'; // placeholder

export const DOMAIN_NAME = 'reportcrime.app';
export const API_SUBDOMAIN = 'api';
export const CDN_SUBDOMAIN = 'cdn';

export const MODERATION_CONFIDENCE_THRESHOLD = 80;
export const MAX_UPLOAD_SIZE_BYTES = 100 * 1024 * 1024; // 100 MB

export const GITHUB_REPO = 'AbelShiferaw/crimereport';

export const DEFAULT_TAGS: Record<string, string> = {
  Project: 'CrimeReport',
  ManagedBy: 'CDK',
};
