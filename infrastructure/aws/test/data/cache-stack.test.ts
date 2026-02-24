import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import { Template } from 'aws-cdk-lib/assertions';
import { CacheStack } from '../../lib/data/cache-stack';
import { REDIS_PORT, REDIS_NODE_TYPE } from '../../lib/config/constants';

describe('CacheStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    const env = { account: '123456789012', region: 'us-east-1' };

    const vpcStack = new cdk.Stack(app, 'VpcStack', { env });
    const vpc = new ec2.Vpc(vpcStack, 'Vpc', { maxAzs: 2 });
    const sg = new ec2.SecurityGroup(vpcStack, 'RedisSg', { vpc });

    const stack = new CacheStack(app, 'TestCache', {
      env,
      vpc,
      securityGroup: sg,
    });

    template = Template.fromStack(stack);
  });

  test('creates Redis replication group', () => {
    template.resourceCountIs('AWS::ElastiCache::ReplicationGroup', 1);
    template.hasResourceProperties('AWS::ElastiCache::ReplicationGroup', {
      Engine: 'redis',
      EngineVersion: '7.1',
      CacheNodeType: REDIS_NODE_TYPE,
      Port: REDIS_PORT,
    });
  });

  test('configures single-node for MVP', () => {
    template.hasResourceProperties('AWS::ElastiCache::ReplicationGroup', {
      NumCacheClusters: 1,
      AutomaticFailoverEnabled: false,
      MultiAZEnabled: false,
    });
  });

  test('enables encryption at rest and in transit', () => {
    template.hasResourceProperties('AWS::ElastiCache::ReplicationGroup', {
      AtRestEncryptionEnabled: true,
      TransitEncryptionEnabled: true,
    });
  });

  test('creates subnet group with private subnets', () => {
    template.resourceCountIs('AWS::ElastiCache::SubnetGroup', 1);
    template.hasResourceProperties('AWS::ElastiCache::SubnetGroup', {
      CacheSubnetGroupName: 'crimereport-redis-subnet',
      Description: 'CrimeReport Redis subnet group (private subnets)',
    });
  });
});
