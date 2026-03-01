# Milestone 14: AWS VPC & Network Security

## Status
Completed

## Goal
Set up the AWS networking foundation using CDK: VPC with public/private subnets, NAT gateway, security groups for all services, WAF with managed rules, and VPC flow logs.

## Dependencies
- AWS account with CDK bootstrap (`cdk bootstrap`)
- Node.js 20+, AWS CDK CLI

## What Was Built
A three-stack networking layer deployed via AWS CDK (TypeScript):

1. **NetworkStack** — VPC with 2 AZs, public + private subnets, single NAT gateway, VPC flow logs to CloudWatch
2. **SecurityStack** — Four security groups (ALB, ECS, DB, Redis) with least-privilege ingress rules
3. **WafStack** — Regional WAF WebACL with IP rate limiting and three AWS managed rule sets, plus WAF logging

All stacks are wired together in `crimereport-stack.ts` with explicit dependency ordering.

## Key Files

| File | Description |
|------|-------------|
| `infrastructure/aws/lib/network/network-stack.ts` | VPC, subnets, NAT gateway, flow logs |
| `infrastructure/aws/lib/network/security-stack.ts` | ALB, ECS, DB, and Redis security groups |
| `infrastructure/aws/lib/network/waf-stack.ts` | WAF WebACL, rate limiting, managed rules, WAF logging |
| `infrastructure/aws/lib/config/constants.ts` | Shared constants (CIDR, ports, rate limits, etc.) |
| `infrastructure/aws/bin/crimereport-stack.ts` | App entry point — stack instantiation and dependency wiring |
| `infrastructure/aws/test/network/network-stack.test.ts` | Network stack CDK assertions |
| `infrastructure/aws/test/network/security-stack.test.ts` | Security group CDK assertions |
| `infrastructure/aws/test/network/waf-stack.test.ts` | WAF CDK assertions |

## Implementation Details

### 1. Shared Constants

All networking constants live in a single config file referenced by every stack:

```typescript
// infrastructure/aws/lib/config/constants.ts
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
```

### 2. VPC (NetworkStack)

The VPC uses CDK's high-level `ec2.Vpc` construct which automatically creates subnets, route tables, an Internet Gateway, and a NAT gateway:

```typescript
// infrastructure/aws/lib/network/network-stack.ts
this.vpc = new ec2.Vpc(this, 'CrimeReportVpc', {
  vpcName: `${PROJECT_PREFIX}-vpc`,
  maxAzs: MAX_AZS,
  natGateways: NAT_GATEWAYS,
  ipAddresses: ec2.IpAddresses.cidr(VPC_CIDR),
  subnetConfiguration: [
    {
      name: 'Public',
      subnetType: ec2.SubnetType.PUBLIC,
      cidrMask: 24,
      mapPublicIpOnLaunch: true,
    },
    {
      name: 'Private',
      subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      cidrMask: 24,
    },
  ],
});
```

Result: 2 public subnets (ALB), 2 private subnets (ECS, Aurora, Redis), 1 NAT gateway for private subnet egress.

VPC flow logs capture ALL traffic to a CloudWatch log group with 30-day retention:

```typescript
const flowLogGroup = new logs.LogGroup(this, 'VpcFlowLogs', {
  logGroupName: `/vpc/${PROJECT_PREFIX}-flow-logs`,
  retention: logs.RetentionDays.ONE_MONTH,
  removalPolicy: cdk.RemovalPolicy.DESTROY,
});

this.vpc.addFlowLog('FlowLog', {
  destination: ec2.FlowLogDestination.toCloudWatchLogs(flowLogGroup),
  trafficType: ec2.FlowLogTrafficType.ALL,
});
```

### 3. Security Groups (SecurityStack)

Four security groups with least-privilege rules. DB and Redis SGs explicitly block all outbound (`allowAllOutbound: false`):

```typescript
// infrastructure/aws/lib/network/security-stack.ts

// ALB — accepts HTTP/HTTPS from internet (IPv4 + IPv6)
this.albSecurityGroup = new ec2.SecurityGroup(this, 'AlbSg', {
  vpc,
  securityGroupName: `${PROJECT_PREFIX}-alb-sg`,
  description: 'API Gateway ALB - accepts HTTP/HTTPS from internet',
  allowAllOutbound: true,
});
this.albSecurityGroup.addIngressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(443), 'HTTPS from internet (IPv4)');
this.albSecurityGroup.addIngressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(80), 'HTTP from internet (IPv4, redirect to HTTPS)');
this.albSecurityGroup.addIngressRule(ec2.Peer.anyIpv6(), ec2.Port.tcp(443), 'HTTPS from internet (IPv6)');
this.albSecurityGroup.addIngressRule(ec2.Peer.anyIpv6(), ec2.Port.tcp(80), 'HTTP from internet (IPv6, redirect to HTTPS)');

// ECS — only from ALB on API_PORT (3000)
this.ecsSecurityGroup = new ec2.SecurityGroup(this, 'EcsSg', {
  vpc,
  securityGroupName: `${PROJECT_PREFIX}-ecs-sg`,
  description: 'Report API Service - accepts traffic from ALB only',
  allowAllOutbound: true,
});
this.ecsSecurityGroup.addIngressRule(this.albSecurityGroup, ec2.Port.tcp(API_PORT), 'API traffic from ALB');

// DB — only from ECS on DB_PORT (5432), no outbound
this.dbSecurityGroup = new ec2.SecurityGroup(this, 'DbSg', {
  vpc,
  securityGroupName: `${PROJECT_PREFIX}-db-sg`,
  description: 'Crime Reports DB - accepts connections from ECS only',
  allowAllOutbound: false,
});
this.dbSecurityGroup.addIngressRule(this.ecsSecurityGroup, ec2.Port.tcp(DB_PORT), 'PostgreSQL from ECS tasks');

// Redis — only from ECS on REDIS_PORT (6379), no outbound
this.redisSecurityGroup = new ec2.SecurityGroup(this, 'RedisSg', {
  vpc,
  securityGroupName: `${PROJECT_PREFIX}-redis-sg`,
  description: 'Feed Cache + Socket Adapter - accepts connections from ECS only',
  allowAllOutbound: false,
});
this.redisSecurityGroup.addIngressRule(this.ecsSecurityGroup, ec2.Port.tcp(REDIS_PORT), 'Redis from ECS tasks');
```

### 4. WAF (WafStack)

A REGIONAL WebACL with four rules attached to the ALB (association happens in the ComputeStack):

```typescript
// infrastructure/aws/lib/network/waf-stack.ts
const webAcl = new wafv2.CfnWebACL(this, 'CrimeReportWaf', {
  name: `${PROJECT_PREFIX}-waf`,
  scope: 'REGIONAL',
  defaultAction: { allow: {} },
  rules: [
    // 1. Rate limiting — block IPs exceeding 2000 req/5min
    {
      name: 'RateLimitPerIP',
      priority: 1,
      action: { block: {} },
      statement: {
        rateBasedStatement: { limit: WAF_RATE_LIMIT, aggregateKeyType: 'IP' },
      },
      // ... visibilityConfig
    },
    // 2. AWS Common Rule Set (XSS, bad bots, etc.)
    {
      name: 'AWSManagedRulesCommonRuleSet',
      priority: 2,
      overrideAction: { none: {} },
      statement: {
        managedRuleGroupStatement: { vendorName: 'AWS', name: 'AWSManagedRulesCommonRuleSet' },
      },
    },
    // 3. Known Bad Inputs (Log4j, etc.)
    {
      name: 'AWSManagedRulesKnownBadInputs',
      priority: 3,
      overrideAction: { none: {} },
      statement: {
        managedRuleGroupStatement: { vendorName: 'AWS', name: 'AWSManagedRulesKnownBadInputsRuleSet' },
      },
    },
    // 4. SQL Injection protection
    {
      name: 'AWSManagedRulesSQLiRuleSet',
      priority: 4,
      overrideAction: { none: {} },
      statement: {
        managedRuleGroupStatement: { vendorName: 'AWS', name: 'AWSManagedRulesSQLiRuleSet' },
      },
    },
  ],
});
```

WAF logging goes to a CloudWatch log group (name must start with `aws-waf-logs-`):

```typescript
const wafLogGroup = new logs.LogGroup(this, 'WafLogGroup', {
  logGroupName: `aws-waf-logs-${PROJECT_PREFIX}`,
  retention: logs.RetentionDays.ONE_MONTH,
  removalPolicy: cdk.RemovalPolicy.DESTROY,
});

new wafv2.CfnLoggingConfiguration(this, 'WafLogging', {
  resourceArn: webAcl.attrArn,
  logDestinationConfigs: [wafLogGroup.logGroupArn],
});
```

### 5. Stack Wiring

```typescript
// infrastructure/aws/bin/crimereport-stack.ts
const networkStack = new NetworkStack(app, 'CrimeReport-Network', { env });
const wafStack = new WafStack(app, 'CrimeReport-Waf', { env });

const securityStack = new SecurityStack(app, 'CrimeReport-Security', {
  env,
  vpc: networkStack.vpc,
});
securityStack.addDependency(networkStack);
```

The `webAclArn` is exported from WafStack and consumed by ComputeStack to associate the WAF with the ALB.

## Testing

CDK assertion tests in `infrastructure/aws/test/network/`:

**network-stack.test.ts** (7 tests):
- VPC created with correct CIDR (`10.0.0.0/16`)
- Exactly 2 public subnets with public IPs
- Exactly 2 private subnets
- Exactly 1 NAT gateway
- Internet Gateway created and attached
- VPC flow logs to CloudWatch
- Flow log log group with correct name and 30-day retention

**security-stack.test.ts** (7 tests):
- Exactly 4 security groups created
- ALB SG allows HTTPS from IPv4 and IPv6
- ECS SG allows inbound on port 3000 from ALB SG only
- DB SG allows inbound on port 5432 from ECS SG only
- Redis SG allows inbound on port 6379 from ECS SG only
- DB and Redis SGs block all outbound

**waf-stack.test.ts** (7 tests):
- WebACL with REGIONAL scope and Allow default action
- Rate-limiting rule with limit of 2000
- All three AWS managed rule sets attached
- WAF logging configured to CloudWatch
- WAF log group with `aws-waf-logs-` prefix and 30-day retention

## Notes

- **Deviation from original plan**: The original plan used Terraform HCL. The actual implementation uses AWS CDK (TypeScript) with high-level constructs.
- **IAM roles** were moved to a separate `IamStack` (Milestone 17 / compute dependency) rather than living in the network layer.
- **WAF was not in the original plan** but was added as a separate stack for defense-in-depth (rate limiting + managed rules).
- **VPC flow logs were not in the original plan** but were added for network traffic auditing.
- **IPv6 ingress** on the ALB SG was added beyond the original plan's IPv4-only rules.
- **DB and Redis SGs** explicitly disable all outbound traffic (`allowAllOutbound: false`), which is stricter than the original plan.
- The single NAT gateway is a cost-saving measure for MVP; production should use one per AZ.
