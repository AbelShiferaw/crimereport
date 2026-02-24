import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as elasticache from 'aws-cdk-lib/aws-elasticache';
import { Construct } from 'constructs';
import { PROJECT_PREFIX, REDIS_PORT, REDIS_NODE_TYPE } from '../config/constants';

interface CacheStackProps extends cdk.StackProps {
  vpc: ec2.IVpc;
  securityGroup: ec2.ISecurityGroup;
}

export class CacheStack extends cdk.Stack {
  public readonly redisEndpoint: string;
  public readonly redisPort: string;

  constructor(scope: Construct, id: string, props: CacheStackProps) {
    super(scope, id, props);

    const { vpc, securityGroup } = props;

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

    redis.addDependency(subnetGroup);

    this.redisEndpoint = redis.attrPrimaryEndPointAddress;
    this.redisPort = redis.attrPrimaryEndPointPort;

    new cdk.CfnOutput(this, 'RedisEndpoint', {
      value: redis.attrPrimaryEndPointAddress,
      description: 'Redis primary endpoint address',
    });

    new cdk.CfnOutput(this, 'RedisPort', {
      value: redis.attrPrimaryEndPointPort,
      description: 'Redis port',
    });
  }
}
