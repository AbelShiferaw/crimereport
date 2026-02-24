import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { DatabaseStack } from '../../lib/data/database-stack';
import { DB_NAME, DB_MIN_ACU, DB_MAX_ACU, DB_PORT } from '../../lib/config/constants';

describe('DatabaseStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    const env = { account: '123456789012', region: 'us-east-1' };

    const vpcStack = new cdk.Stack(app, 'VpcStack', { env });
    const vpc = new ec2.Vpc(vpcStack, 'Vpc', { maxAzs: 2 });
    const sg = new ec2.SecurityGroup(vpcStack, 'DbSg', { vpc });

    const stack = new DatabaseStack(app, 'TestDatabase', {
      env,
      vpc,
      securityGroup: sg,
    });

    template = Template.fromStack(stack);
  });

  test('creates Aurora PostgreSQL cluster', () => {
    template.hasResourceProperties('AWS::RDS::DBCluster', {
      Engine: 'aurora-postgresql',
      DatabaseName: DB_NAME,
      Port: DB_PORT,
      StorageEncrypted: true,
    });
  });

  test('configures Serverless v2 scaling', () => {
    template.hasResourceProperties('AWS::RDS::DBCluster', {
      ServerlessV2ScalingConfiguration: {
        MinCapacity: DB_MIN_ACU,
        MaxCapacity: DB_MAX_ACU,
      },
    });
  });

  test('creates exactly one writer instance with serverless class', () => {
    template.resourceCountIs('AWS::RDS::DBInstance', 1);
    template.hasResourceProperties('AWS::RDS::DBInstance', {
      DBInstanceClass: 'db.serverless',
      PubliclyAccessible: false,
    });
  });

  test('creates Secrets Manager secret for credentials', () => {
    template.resourceCountIs('AWS::SecretsManager::Secret', 1);
    template.hasResourceProperties('AWS::SecretsManager::Secret', {
      Name: Match.stringLikeRegexp('crimereport/db-credentials'),
    });
  });

  test('configures backup retention', () => {
    template.hasResourceProperties('AWS::RDS::DBCluster', {
      BackupRetentionPeriod: 7,
    });
  });

  test('enforces SSL via parameter group', () => {
    template.hasResourceProperties('AWS::RDS::DBClusterParameterGroup', {
      Family: Match.stringLikeRegexp('aurora-postgresql'),
      Parameters: Match.objectLike({
        'rds.force_ssl': '1',
      }),
    });
  });

  test('disables deletion protection for MVP', () => {
    template.hasResourceProperties('AWS::RDS::DBCluster', {
      DeletionProtection: false,
    });
  });
});
