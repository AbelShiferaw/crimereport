import * as cdk from 'aws-cdk-lib';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as s3 from 'aws-cdk-lib/aws-s3';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { DnsStack } from '../../lib/network/dns-stack';

describe('DnsStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    const env = { account: '123456789012', region: 'us-east-1' };

    const depsStack = new cdk.Stack(app, 'DnsDepsStack', { env });
    const vpc = new ec2.Vpc(depsStack, 'Vpc', { maxAzs: 2 });
    const alb = new elbv2.ApplicationLoadBalancer(depsStack, 'Alb', {
      vpc,
      internetFacing: true,
    });

    const bucket = new s3.Bucket(depsStack, 'Bucket');
    const distribution = new cloudfront.Distribution(depsStack, 'Cdn', {
      defaultBehavior: {
        origin: origins.S3BucketOrigin.withOriginAccessControl(bucket),
      },
    });

    const stack = new DnsStack(app, 'TestDns', {
      env,
      alb,
      distribution,
      domainName: 'reportcrime.app',
    });

    template = Template.fromStack(stack);
  });

  test('creates Route 53 hosted zone for reportcrime.app', () => {
    template.hasResourceProperties('AWS::Route53::HostedZone', {
      Name: 'reportcrime.app.',
    });
  });

  test('creates API alias record for api.reportcrime.app', () => {
    template.hasResourceProperties('AWS::Route53::RecordSet', {
      Name: 'api.reportcrime.app.',
      Type: 'A',
      AliasTarget: Match.objectLike({
        DNSName: Match.anyValue(),
        HostedZoneId: Match.anyValue(),
      }),
    });
  });

  test('creates CDN alias record for cdn.reportcrime.app', () => {
    template.hasResourceProperties('AWS::Route53::RecordSet', {
      Name: 'cdn.reportcrime.app.',
      Type: 'A',
      AliasTarget: Match.objectLike({
        DNSName: Match.anyValue(),
        HostedZoneId: Match.anyValue(),
      }),
    });
  });

  test('creates exactly 2 alias records', () => {
    template.resourceCountIs('AWS::Route53::RecordSet', 2);
  });

  test('hosted zone has comment', () => {
    template.hasResourceProperties('AWS::Route53::HostedZone', {
      HostedZoneConfig: Match.objectLike({
        Comment: Match.stringLikeRegexp('crimereport'),
      }),
    });
  });

  test('outputs hosted zone ID', () => {
    const outputs = template.findOutputs('HostedZoneId');
    expect(Object.keys(outputs).length).toBe(1);
  });

  test('outputs API domain name', () => {
    const outputs = template.findOutputs('ApiDomainName');
    expect(Object.keys(outputs).length).toBe(1);
  });

  test('outputs CDN domain name', () => {
    const outputs = template.findOutputs('CdnDomainName');
    expect(Object.keys(outputs).length).toBe(1);
  });
});
