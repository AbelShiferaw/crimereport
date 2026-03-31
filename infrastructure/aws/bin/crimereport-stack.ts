#!/usr/bin/env node
import 'source-map-support/register';
import * as path from 'path';
import * as cdk from 'aws-cdk-lib';
import { NetworkStack } from '../lib/network/network-stack';
import { WafStack } from '../lib/network/waf-stack';
import { SecurityStack } from '../lib/network/security-stack';
import { IamStack } from '../lib/iam/iam-stack';
import { DatabaseStack } from '../lib/data/database-stack';
import { CacheStack } from '../lib/data/cache-stack';
import { MediaStack } from '../lib/media/media-stack';
import { ComputeStack } from '../lib/compute/compute-stack';
import { MonitoringStack } from '../lib/monitoring/monitoring-stack';
import { DnsStack } from '../lib/network/dns-stack';
import { SnsStack } from '../lib/notifications/sns-stack';
import { CicdStack } from '../lib/cicd/cicd-stack';
import { DEFAULT_TAGS, PROJECT_PREFIX } from '../lib/config/constants';

const app = new cdk.App();

const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
};

for (const [key, value] of Object.entries(DEFAULT_TAGS)) {
  cdk.Tags.of(app).add(key, value);
}

const networkStack = new NetworkStack(app, 'CrimeReport-Network', {
  env,
  description: 'CrimeReport - VPC, subnets, NAT Gateway, Internet Gateway',
});

const wafStack = new WafStack(app, 'CrimeReport-Waf', {
  env,
  description: 'CrimeReport - WAF WebACL with rate-limiting and managed rules',
});

const securityStack = new SecurityStack(app, 'CrimeReport-Security', {
  env,
  description: 'CrimeReport - Security groups for ALB, ECS, DB, Redis',
  vpc: networkStack.vpc,
});
securityStack.addDependency(networkStack);

const iamStack = new IamStack(app, 'CrimeReport-Iam', {
  env,
  description: 'CrimeReport - IAM roles for ECS execution and task',
});

const databaseStack = new DatabaseStack(app, 'CrimeReport-Database', {
  env,
  description: 'CrimeReport - Aurora Serverless v2 PostgreSQL with PostGIS',
  vpc: networkStack.vpc,
  securityGroup: securityStack.dbSecurityGroup,
});
databaseStack.addDependency(networkStack);
databaseStack.addDependency(securityStack);

const cacheStack = new CacheStack(app, 'CrimeReport-Cache', {
  env,
  description: 'CrimeReport - ElastiCache Redis for caching and pub/sub',
  vpc: networkStack.vpc,
  securityGroup: securityStack.redisSecurityGroup,
});
cacheStack.addDependency(networkStack);
cacheStack.addDependency(securityStack);

const mediaStack = new MediaStack(app, 'CrimeReport-Media', {
  env,
  description: 'CrimeReport - S3 storage, CloudFront CDN, Step Functions media pipeline',
});

const snsStack = new SnsStack(app, 'CrimeReport-Sns', {
  env,
  description: 'CrimeReport - SNS platform applications for push notifications',
});

const computeStack = new ComputeStack(app, 'CrimeReport-Compute', {
  env,
  description: 'CrimeReport - ECS Fargate API service with ALB and auto-scaling',
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
  snsAndroidPlatformArn: snsStack.androidPlatformArn,
  snsIosPlatformArn: snsStack.iosPlatformArn,
});
computeStack.addDependency(networkStack);
computeStack.addDependency(securityStack);
computeStack.addDependency(iamStack);
computeStack.addDependency(databaseStack);
computeStack.addDependency(cacheStack);
computeStack.addDependency(wafStack);
computeStack.addDependency(mediaStack);
computeStack.addDependency(snsStack);

new CicdStack(app, 'CrimeReport-Cicd', {
  env,
  description: 'CrimeReport - GitHub Actions OIDC provider and deploy role',
});

const monitoringStack = new MonitoringStack(app, 'CrimeReport-Monitoring', {
  env,
  description: 'CrimeReport - CloudWatch alarms and operations dashboard',
  dbCluster: databaseStack.cluster,
  redisReplicationGroupId: `${PROJECT_PREFIX}-redis`,
  ecsCluster: computeStack.cluster,
  ecsService: computeStack.service,
  alb: computeStack.alb,
});
monitoringStack.addDependency(databaseStack);
monitoringStack.addDependency(cacheStack);
monitoringStack.addDependency(computeStack);

const dnsStack = new DnsStack(app, 'CrimeReport-Dns', {
  env,
  description: 'CrimeReport - Route 53 hosted zone and DNS records',
  alb: computeStack.alb,
  distribution: mediaStack.distribution,
});
dnsStack.addDependency(computeStack);
dnsStack.addDependency(mediaStack);
