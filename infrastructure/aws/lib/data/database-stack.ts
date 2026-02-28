import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import { Construct } from 'constructs';
import {
  PROJECT_PREFIX,
  DB_NAME,
  DB_ADMIN_USER,
  DB_MIN_ACU,
  DB_MAX_ACU,
  DB_PORT,
} from '../config/constants';

interface DatabaseStackProps extends cdk.StackProps {
  vpc: ec2.IVpc;
  securityGroup: ec2.ISecurityGroup;
}

export class DatabaseStack extends cdk.Stack {
  public readonly cluster: rds.DatabaseCluster;

  constructor(scope: Construct, id: string, props: DatabaseStackProps) {
    super(scope, id, props);

    const { vpc, securityGroup } = props;

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

    new cdk.CfnOutput(this, 'DbClusterEndpoint', {
      value: this.cluster.clusterEndpoint.hostname,
      description: 'Aurora cluster writer endpoint',
    });

    new cdk.CfnOutput(this, 'DbClusterReaderEndpoint', {
      value: this.cluster.clusterReadEndpoint.hostname,
      description: 'Aurora cluster reader endpoint',
    });

    new cdk.CfnOutput(this, 'DbSecretArn', {
      value: this.cluster.secret?.secretArn ?? 'N/A',
      description: 'Secrets Manager ARN for DB credentials',
    });

    new cdk.CfnOutput(this, 'DbName', {
      value: DB_NAME,
      description: 'Database name',
    });
  }
}
