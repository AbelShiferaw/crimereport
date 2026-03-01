# Milestone 17: ECS Fargate Setup

## Status
Completed

## Goal
Deploy the containerized API on ECS Fargate behind an Application Load Balancer with auto-scaling, WAF protection, health checks, and full environment injection from upstream stacks.

## Dependencies
- **Milestone 14** — VPC, security groups (NetworkStack, SecurityStack)
- **Milestone 15** — Database secret, Redis endpoint (DatabaseStack, CacheStack)
- **Milestone 16** — S3 bucket names, CDN domain (MediaStack)
- **Milestone 14** — WAF WebACL ARN (WafStack)
- IamStack — ECS task role

## What Was Built

A single **ComputeStack** CDK stack containing:

1. **ECR Repository** — `crimereport-api` with image scanning and a lifecycle policy keeping the last 10 images
2. **ECS Cluster** — `crimereport-cluster` with Container Insights v2 enabled
3. **Fargate Task Definition** — 256 CPU / 512 MB, Docker image built from `backend/api/Dockerfile`, environment variables from all upstream stacks, DB secret from Secrets Manager
4. **Application Load Balancer** — Internet-facing, HTTP listener on port 80, target group with `/health` health checks and sticky sessions
5. **Fargate Service** — Runs in private subnets, deployment circuit breaker with rollback, min 50% / max 200% healthy during deploys
6. **Auto-Scaling** — CPU-based target tracking (70% target), scales 1–10 tasks
7. **WAF Association** — WafStack's WebACL attached to the ALB
8. **ECS Execution Role** — Created in ComputeStack (not IamStack) to avoid cross-stack cyclic references; has `AmazonECSTaskExecutionRolePolicy` and DB secret read access

Additionally:
- **IamStack** provides the ECS task role with S3, SNS, Rekognition, and SSM permissions
- **Dockerfile** uses a multi-stage build (builder → production) with auto-migration on startup

## Key Files

| File | Description |
|------|-------------|
| `infrastructure/aws/lib/compute/compute-stack.ts` | ECR, ECS cluster, task def, ALB, Fargate service, auto-scaling, WAF association |
| `infrastructure/aws/lib/iam/iam-stack.ts` | ECS task role (app-level permissions for S3, SNS, Rekognition, SSM) |
| `infrastructure/aws/lib/config/constants.ts` | ECS constants (CPU, memory, scaling limits, etc.) |
| `infrastructure/aws/bin/crimereport-stack.ts` | Stack wiring — ComputeStack depends on all other stacks |
| `backend/api/Dockerfile` | Multi-stage Docker build |
| `infrastructure/aws/test/compute/compute-stack.test.ts` | CDK assertion tests (20 tests) |

## Implementation Details

### 1. Compute Constants

```typescript
// infrastructure/aws/lib/config/constants.ts
export const API_PORT = 3000;
export const ECS_CPU = 256;
export const ECS_MEMORY = 512;
export const ECS_DESIRED_COUNT = 1;
export const ECS_MIN_TASKS = 1;
export const ECS_MAX_TASKS = 10;
export const ECS_CPU_TARGET_PERCENT = 70;
export const ECR_MAX_IMAGE_COUNT = 10;
```

### 2. ECR Repository

```typescript
// infrastructure/aws/lib/compute/compute-stack.ts

this.repository = new ecr.Repository(this, 'ApiRepo', {
  repositoryName: `${PROJECT_PREFIX}-api`,
  imageScanOnPush: true,
  removalPolicy: cdk.RemovalPolicy.DESTROY,
  emptyOnDelete: true,
  lifecycleRules: [
    {
      maxImageCount: ECR_MAX_IMAGE_COUNT,
      description: `Keep last ${ECR_MAX_IMAGE_COUNT} images`,
    },
  ],
});
```

### 3. ECS Cluster

```typescript
this.cluster = new ecs.Cluster(this, 'Cluster', {
  clusterName: `${PROJECT_PREFIX}-cluster`,
  vpc,
  containerInsightsV2: ecs.ContainerInsights.ENABLED,
});
```

### 4. ECS Execution Role

Created inside ComputeStack to avoid cyclic cross-stack references (CDK auto-grants this role log permissions pointing back at the log group in the same stack):

```typescript
this.executionRole = new iam.Role(this, 'EcsExecutionRole', {
  roleName: `${PROJECT_PREFIX}-ecs-execution`,
  assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
});

this.executionRole.addManagedPolicy(
  iam.ManagedPolicy.fromAwsManagedPolicyName(
    'service-role/AmazonECSTaskExecutionRolePolicy',
  ),
);

dbSecret.grantRead(this.executionRole);
```

### 5. Task Definition & Container

```typescript
const taskDef = new ecs.FargateTaskDefinition(this, 'ApiTaskDef', {
  family: `${PROJECT_PREFIX}-api`,
  cpu: ECS_CPU,
  memoryLimitMiB: ECS_MEMORY,
  executionRole: this.executionRole,
  taskRole,
});

const imageAsset = new ecrAssets.DockerImageAsset(this, 'ApiImage', {
  directory: dockerDir,
  platform: ecrAssets.Platform.LINUX_AMD64,
});

const container = taskDef.addContainer('api', {
  image: ecs.ContainerImage.fromDockerImageAsset(imageAsset),
  logging: ecs.LogDrivers.awsLogs({ logGroup, streamPrefix: 'api' }),
  environment: {
    NODE_ENV: 'production',
    PORT: String(API_PORT),
    REDIS_HOST: redisEndpoint,
    REDIS_PORT: redisPort,
    S3_UPLOADS_BUCKET: s3UploadsBucket,
    S3_MEDIA_BUCKET: s3MediaBucket,
    CDN_DOMAIN: cdnDomain,
  },
  secrets: {
    DATABASE_URL: ecs.Secret.fromSecretsManager(dbSecret),
  },
  healthCheck: {
    command: ['CMD-SHELL', `curl -f http://localhost:${API_PORT}/health || exit 1`],
    interval: cdk.Duration.seconds(30),
    timeout: cdk.Duration.seconds(5),
    retries: 3,
    startPeriod: cdk.Duration.seconds(120),
  },
});

container.addPortMappings({
  containerPort: API_PORT,
  protocol: ecs.Protocol.TCP,
});
```

Environment variables injected into the container:
| Variable | Source |
|----------|--------|
| `NODE_ENV` | Hardcoded `production` |
| `PORT` | From `API_PORT` constant (3000) |
| `REDIS_HOST` | From CacheStack's `redisEndpoint` |
| `REDIS_PORT` | From CacheStack's `redisPort` |
| `S3_UPLOADS_BUCKET` | From MediaStack's `uploadsBucket.bucketName` |
| `S3_MEDIA_BUCKET` | From MediaStack's `mediaBucket.bucketName` |
| `CDN_DOMAIN` | From MediaStack's `distribution.distributionDomainName` |
| `DATABASE_URL` | Secret from DatabaseStack's `cluster.secret` (via Secrets Manager) |

### 6. Application Load Balancer

```typescript
this.alb = new elbv2.ApplicationLoadBalancer(this, 'Alb', {
  loadBalancerName: `${PROJECT_PREFIX}-alb`,
  vpc,
  internetFacing: true,
  securityGroup: albSecurityGroup,
  vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC },
});

const targetGroup = new elbv2.ApplicationTargetGroup(this, 'ApiTargetGroup', {
  targetGroupName: `${PROJECT_PREFIX}-api-tg`,
  vpc,
  port: API_PORT,
  protocol: elbv2.ApplicationProtocol.HTTP,
  targetType: elbv2.TargetType.IP,
  healthCheck: {
    path: '/health',
    interval: cdk.Duration.seconds(30),
    timeout: cdk.Duration.seconds(5),
    healthyThresholdCount: 2,
    unhealthyThresholdCount: 3,
    healthyHttpCodes: '200',
  },
  stickinessCookieDuration: cdk.Duration.days(1),
});

this.listener = this.alb.addListener('HttpListener', {
  port: 80,
  protocol: elbv2.ApplicationProtocol.HTTP,
  defaultTargetGroups: [targetGroup],
});
```

Currently using an HTTP listener on port 80. HTTPS (443) requires an ACM certificate to be provisioned separately.

### 7. Fargate Service

```typescript
this.service = new ecs.FargateService(this, 'ApiService', {
  serviceName: `${PROJECT_PREFIX}-api`,
  cluster: this.cluster,
  taskDefinition: taskDef,
  desiredCount: ECS_DESIRED_COUNT,
  securityGroups: [ecsSecurityGroup],
  vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
  assignPublicIp: false,
  minHealthyPercent: 50,
  maxHealthyPercent: 200,
  circuitBreaker: { enable: true, rollback: true },
});

this.service.attachToApplicationTargetGroup(targetGroup);
```

Deployment circuit breaker automatically rolls back failed deployments.

### 8. Auto-Scaling

```typescript
const scaling = this.service.autoScaleTaskCount({
  minCapacity: ECS_MIN_TASKS,
  maxCapacity: ECS_MAX_TASKS,
});

scaling.scaleOnCpuUtilization('CpuScaling', {
  targetUtilizationPercent: ECS_CPU_TARGET_PERCENT,
  scaleInCooldown: cdk.Duration.seconds(300),
  scaleOutCooldown: cdk.Duration.seconds(60),
});
```

Scales 1–10 tasks based on CPU utilization (target 70%). 5-minute cooldown for scale-in, 1-minute for scale-out.

### 9. WAF Association

```typescript
new wafv2.CfnWebACLAssociation(this, 'WafAlbAssociation', {
  resourceArn: this.alb.loadBalancerArn,
  webAclArn: wafAclArn,
});
```

### 10. ECS Task Role (IamStack)

The task role gives the running application permissions for S3, SNS, Rekognition, and SSM:

```typescript
// infrastructure/aws/lib/iam/iam-stack.ts

this.ecsTaskRole = new iam.Role(this, 'EcsTaskRole', {
  roleName: `${PROJECT_PREFIX}-ecs-task`,
  assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
  description: 'ECS task role - app-level permissions for S3, SNS, Rekognition, SSM',
});

// S3: GetObject, PutObject, DeleteObject, ListBucket on crimereport-* buckets
// SNS: Publish to crimereport-* topics
// Rekognition: DetectModerationLabels
// SSM: GetParameter(s) under /crimereport/* path
```

### 11. Dockerfile

Multi-stage build with auto-migration on startup:

```dockerfile
# backend/api/Dockerfile

FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

FROM node:20-alpine
WORKDIR /app
RUN apk add --no-cache curl
COPY package*.json ./
RUN npm ci --omit=dev
COPY --from=builder /app/dist ./dist
COPY migrations ./migrations
COPY scripts ./scripts
EXPOSE 3000
USER node
CMD ["sh", "-c", "node scripts/migrate.js && node dist/index.js"]
```

Key details:
- **Multi-stage**: Builder stage compiles TypeScript, production stage only has runtime dependencies
- `curl` is installed for the container health check (`CMD-SHELL curl -f ...`)
- Runs as non-root `node` user
- Migrations execute automatically before the API starts
- Includes `migrations/` and `scripts/` directories in the final image

### 12. Stack Wiring

ComputeStack depends on every other stack:

```typescript
// infrastructure/aws/bin/crimereport-stack.ts

const computeStack = new ComputeStack(app, 'CrimeReport-Compute', {
  env,
  vpc: networkStack.vpc,
  albSecurityGroup: securityStack.albSecurityGroup,
  ecsSecurityGroup: securityStack.ecsSecurityGroup,
  taskRole: iamStack.ecsTaskRole,
  dbSecret: databaseStack.cluster.secret!,
  redisEndpoint: cacheStack.redisEndpoint,
  redisPort: cacheStack.redisPort,
  wafAclArn: wafStack.webAclArn,
  dockerDir: path.join(__dirname, '..', '..', '..', 'backend', 'api'),
  s3UploadsBucket: mediaStack.uploadsBucket.bucketName,
  s3MediaBucket: mediaStack.mediaBucket.bucketName,
  cdnDomain: mediaStack.distribution.distributionDomainName,
});
computeStack.addDependency(networkStack);
computeStack.addDependency(securityStack);
computeStack.addDependency(iamStack);
computeStack.addDependency(databaseStack);
computeStack.addDependency(cacheStack);
computeStack.addDependency(wafStack);
computeStack.addDependency(mediaStack);
```

## Testing

CDK assertion tests in `infrastructure/aws/test/compute/compute-stack.test.ts` (20 tests):

**ECR:**
- Repository with `crimereport-api` name and image scanning enabled
- Lifecycle policy configured

**CloudWatch Logs:**
- Log group `/ecs/crimereport-api` with 30-day retention

**Execution Role:**
- `crimereport-ecs-execution` role with `AmazonECSTaskExecutionRolePolicy`

**ECS Cluster:**
- `crimereport-cluster` with Container Insights enabled

**Task Definition:**
- Fargate, 256 CPU, 512 MB, `awsvpc` network mode
- Container `api` with port 3000
- Container health check (`curl -f http://localhost:3000/health`)
- Environment variables: `NODE_ENV`, `PORT`, `REDIS_HOST`
- Database secret injected as `DATABASE_URL`
- CloudWatch log configuration with `api` stream prefix

**ALB:**
- Internet-facing application load balancer (`crimereport-alb`)
- HTTP listener on port 80
- Target group `crimereport-api-tg` with `/health` health check

**Fargate Service:**
- `crimereport-api` with desired count 1, min 50% / max 200% healthy
- Deployment circuit breaker with rollback enabled
- Public IP disabled (runs in private subnets)

**Auto-Scaling:**
- Scalable target: 1–10 tasks
- CPU target tracking at 70%

**WAF:**
- WebACL associated with ALB

## Notes

- **Deviation from original plan**: The original plan used Terraform HCL with separate `.tf` files. The actual implementation is a single CDK TypeScript stack.
- **CPU/Memory reduced**: The original plan had 512 CPU / 1024 MB. The actual implementation uses 256 CPU / 512 MB for MVP cost savings.
- **Desired count reduced**: 1 task instead of the original plan's 2, with auto-scaling from 1–10.
- **No HTTPS listener yet**: The ALB currently has only an HTTP listener on port 80. The original plan included HTTPS on 443 with ACM. An ACM certificate and HTTPS listener should be added before production.
- **No ALB request count scaling**: The original plan had a second scaling policy on `ALBRequestCountPerTarget`. The actual implementation uses only CPU-based scaling.
- **Docker image is built by CDK**: Using `DockerImageAsset` which builds and pushes the image during `cdk deploy`, rather than a separate CI/CD push to ECR.
- **Circuit breaker**: The actual implementation adds a deployment circuit breaker with automatic rollback, which wasn't in the original plan.
- **Container Insights v2**: Uses `containerInsightsV2` (enhanced observability) instead of the basic container insights from the original plan.
- **Execution role in ComputeStack**: Placed here instead of IamStack to avoid cyclic cross-stack references from CDK's automatic log group grants.
- **120-second start period**: Container health check allows 2 minutes for startup (vs 60 seconds in the original plan) to accommodate migration execution.
