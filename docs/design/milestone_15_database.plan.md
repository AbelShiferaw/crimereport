# Milestone 15: Database Layer

## Status
Completed

## Goal
Deploy Aurora Serverless v2 PostgreSQL with PostGIS support and ElastiCache Redis, both in private subnets with encrypted connections and auto-generated credentials.

## Dependencies
- **Milestone 14** complete (VPC and security groups)
- CDK `NetworkStack` provides the VPC
- CDK `SecurityStack` provides DB and Redis security groups

## What Was Built

1. **DatabaseStack** — Aurora Serverless v2 PostgreSQL 16.4 cluster with a single writer instance, auto-generated Secrets Manager credentials, a custom parameter group enabling `pg_stat_statements` and forced SSL, 7-day backup retention, and Data API enabled.
2. **CacheStack** — Single-node ElastiCache Redis 7.1 (`cache.t4g.micro`) in a private subnet group with at-rest and in-transit encryption.
3. **Database Schema** — A SQL migration (`1709000000000_initial-schema.sql`) creating the full schema: reports with PostGIS geography, media, comments, upvote tracking, device activity, and an `updated_at` trigger.

## Key Files

| File | Description |
|------|-------------|
| `infrastructure/aws/lib/data/database-stack.ts` | Aurora Serverless v2 cluster, parameter group, Secrets Manager |
| `infrastructure/aws/lib/data/cache-stack.ts` | ElastiCache Redis replication group and subnet group |
| `infrastructure/aws/lib/config/constants.ts` | DB/Redis constants (name, port, ACU limits, node type) |
| `infrastructure/aws/bin/crimereport-stack.ts` | Stack wiring with dependency ordering |
| `backend/api/migrations/1709000000000_initial-schema.sql` | Full database schema with PostGIS |
| `infrastructure/aws/test/data/database-stack.test.ts` | Aurora CDK assertions |
| `infrastructure/aws/test/data/cache-stack.test.ts` | Redis CDK assertions |

## Implementation Details

### 1. Database Constants

```typescript
// infrastructure/aws/lib/config/constants.ts
export const DB_NAME = 'crimereport';
export const DB_ADMIN_USER = 'crimereport_admin';
export const DB_MIN_ACU = 0.5;
export const DB_MAX_ACU = 4;
export const DB_PORT = 5432;

export const REDIS_NODE_TYPE = 'cache.t4g.micro';
export const REDIS_PORT = 6379;
```

### 2. Aurora Serverless v2 PostgreSQL (DatabaseStack)

```typescript
// infrastructure/aws/lib/data/database-stack.ts

const parameterGroup = new rds.ParameterGroup(this, 'AuroraParams', {
  engine: rds.DatabaseClusterEngine.auroraPostgres({
    version: rds.AuroraPostgresEngineVersion.VER_16_4,
  }),
  description: 'CrimeReport Aurora PostgreSQL params with PostGIS',
  parameters: {
    'shared_preload_libraries': 'pg_stat_statements',
    'rds.force_ssl': '1',
  },
});

this.cluster = new rds.DatabaseCluster(this, 'CrimeReportDb', {
  clusterIdentifier: `${PROJECT_PREFIX}-db`,
  engine: rds.DatabaseClusterEngine.auroraPostgres({
    version: rds.AuroraPostgresEngineVersion.VER_16_4,
  }),
  credentials: rds.Credentials.fromGeneratedSecret(DB_ADMIN_USER, {
    secretName: `${PROJECT_PREFIX}/db-credentials`,
  }),
  defaultDatabaseName: DB_NAME,
  parameterGroup,
  serverlessV2MinCapacity: DB_MIN_ACU,
  serverlessV2MaxCapacity: DB_MAX_ACU,
  writer: rds.ClusterInstance.serverlessV2('Writer', {
    publiclyAccessible: false,
  }),
  vpc,
  vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
  securityGroups: [securityGroup],
  port: DB_PORT,
  enableDataApi: true,
  storageEncrypted: true,
  backup: {
    retention: cdk.Duration.days(7),
  },
  deletionProtection: false,
  removalPolicy: cdk.RemovalPolicy.DESTROY,
});
```

Key decisions:
- **Credentials**: Auto-generated via `Credentials.fromGeneratedSecret()` and stored in Secrets Manager at `crimereport/db-credentials`. No manual password management.
- **Data API**: Enabled for serverless query access without VPC connectivity.
- **Scaling**: 0.5–4 ACUs for cost-effective MVP sizing.
- **SSL forced** via parameter group (`rds.force_ssl = 1`).
- **Single writer instance** — no read replica for MVP.

### 3. ElastiCache Redis (CacheStack)

```typescript
// infrastructure/aws/lib/data/cache-stack.ts

const subnetGroup = new elasticache.CfnSubnetGroup(this, 'RedisSubnetGroup', {
  cacheSubnetGroupName: `${PROJECT_PREFIX}-redis-subnet`,
  description: 'CrimeReport Redis subnet group (private subnets)',
  subnetIds: vpc.privateSubnets.map(s => s.subnetId),
});

const redis = new elasticache.CfnReplicationGroup(this, 'CrimeReportRedis', {
  replicationGroupDescription: 'CrimeReport Redis - feed cache, rate limiting, Socket.io adapter',
  replicationGroupId: `${PROJECT_PREFIX}-redis`,
  engine: 'redis',
  engineVersion: '7.1',
  cacheNodeType: REDIS_NODE_TYPE,
  numCacheClusters: 1,
  cacheSubnetGroupName: subnetGroup.cacheSubnetGroupName,
  securityGroupIds: [securityGroup.securityGroupId],
  port: REDIS_PORT,
  atRestEncryptionEnabled: true,
  transitEncryptionEnabled: true,
  automaticFailoverEnabled: false,
  multiAzEnabled: false,
});
```

Key decisions:
- **Single node** (`numCacheClusters: 1`, no multi-AZ, no automatic failover) for MVP cost savings.
- **Encryption**: Both at-rest and in-transit enabled.
- Uses L1 `CfnReplicationGroup` construct since CDK doesn't have a high-level ElastiCache construct.
- Endpoint and port are exported as stack properties for consumption by the ComputeStack.

### 4. Database Schema

The migration at `backend/api/migrations/1709000000000_initial-schema.sql` creates:

```sql
-- Enable extensions
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Reports table with PostGIS geography column
CREATE TABLE reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id VARCHAR(64) NOT NULL,
    type VARCHAR(50) NOT NULL,
    description TEXT,
    location GEOGRAPHY(POINT, 4326) NOT NULL,
    address VARCHAR(255),
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    upvotes INTEGER NOT NULL DEFAULT 0,
    comment_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_reports_location ON reports USING GIST(location);
CREATE INDEX idx_reports_created_at ON reports(created_at DESC);
CREATE INDEX idx_reports_device_id ON reports(device_id);
CREATE INDEX idx_reports_type ON reports(type);
CREATE INDEX idx_reports_status ON reports(status);
```

Additional tables: `media`, `comments`, `report_upvotes`, `device_activity`.

The migration also creates an `update_updated_at()` trigger function:

```sql
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_reports_updated_at
    BEFORE UPDATE ON reports
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();
```

The migration includes a full down-migration section that drops everything in reverse order.

### 5. Stack Wiring

```typescript
// infrastructure/aws/bin/crimereport-stack.ts

const databaseStack = new DatabaseStack(app, 'CrimeReport-Database', {
  env,
  vpc: networkStack.vpc,
  securityGroup: securityStack.dbSecurityGroup,
});
databaseStack.addDependency(networkStack);
databaseStack.addDependency(securityStack);

const cacheStack = new CacheStack(app, 'CrimeReport-Cache', {
  env,
  vpc: networkStack.vpc,
  securityGroup: securityStack.redisSecurityGroup,
});
cacheStack.addDependency(networkStack);
cacheStack.addDependency(securityStack);
```

The `databaseStack.cluster.secret` and `cacheStack.redisEndpoint` / `cacheStack.redisPort` are passed downstream to ComputeStack for ECS task environment injection.

## Testing

CDK assertion tests in `infrastructure/aws/test/data/`:

**database-stack.test.ts** (7 tests):
- Creates Aurora PostgreSQL cluster with correct engine, DB name, port, and storage encryption
- Configures Serverless v2 scaling (min 0.5, max 4 ACUs)
- Creates exactly one writer instance with `db.serverless` class, not publicly accessible
- Creates Secrets Manager secret at `crimereport/db-credentials`
- Configures 7-day backup retention
- Enforces SSL via parameter group (`rds.force_ssl = 1`)
- Disables deletion protection for MVP

**cache-stack.test.ts** (4 tests):
- Creates Redis replication group (engine 7.1, `cache.t4g.micro`, port 6379)
- Configures single-node for MVP (no failover, no multi-AZ)
- Enables encryption at rest and in transit
- Creates subnet group in private subnets

## Notes

- **Deviation from original plan**: The original plan used Terraform HCL with engine version 15.4. The actual implementation uses CDK TypeScript with Aurora PostgreSQL 16.4.
- **Secrets Manager** credentials are auto-generated by CDK (not manually managed as in the original plan).
- **Redis is single-node** for MVP, unlike the original plan's 2-node multi-AZ setup. Upgrade path: change `numCacheClusters` to 2, set `automaticFailoverEnabled` and `multiAzEnabled` to `true`.
- **PostGIS is enabled via migration**, not via a cluster parameter — Aurora supports `CREATE EXTENSION` natively for PostGIS.
- **`uuid-ossp` extension** is also enabled in the actual migration (not in the original plan).
- **Two additional indexes** (`idx_reports_type`, `idx_reports_status`) exist in the actual migration that weren't in the original plan.
- **`updated_at` trigger** was added in the actual migration to auto-update timestamps.
- The migration runs automatically on container startup via `scripts/migrate.js` (see Milestone 17 Dockerfile).
