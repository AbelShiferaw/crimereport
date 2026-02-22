#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { NetworkStack } from '../lib/network/network-stack';
import { WafStack } from '../lib/network/waf-stack';
import { SecurityStack } from '../lib/network/security-stack';
import { IamStack } from '../lib/iam/iam-stack';
import { DEFAULT_TAGS } from '../lib/config/constants';

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
