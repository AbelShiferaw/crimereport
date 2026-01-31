#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { CrimeReportStack } from '../lib/crimereport-stack';

const app = new cdk.App();

new CrimeReportStack(app, 'CrimeReportStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
  },
  description: 'CrImEreport - Anonymous crime reporting infrastructure',
});
