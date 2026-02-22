import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import { Construct } from 'constructs';
import { PROJECT_PREFIX, API_PORT, DB_PORT, REDIS_PORT } from '../config/constants';

interface SecurityStackProps extends cdk.StackProps {
  vpc: ec2.IVpc;
}

export class SecurityStack extends cdk.Stack {
  public readonly albSecurityGroup: ec2.SecurityGroup;
  public readonly ecsSecurityGroup: ec2.SecurityGroup;
  public readonly dbSecurityGroup: ec2.SecurityGroup;
  public readonly redisSecurityGroup: ec2.SecurityGroup;

  constructor(scope: Construct, id: string, props: SecurityStackProps) {
    super(scope, id, props);

    const { vpc } = props;

    this.albSecurityGroup = new ec2.SecurityGroup(this, 'AlbSg', {
      vpc,
      securityGroupName: `${PROJECT_PREFIX}-alb-sg`,
      description: 'API Gateway ALB - accepts HTTP/HTTPS from internet',
      allowAllOutbound: true,
    });
    this.albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'HTTPS from internet (IPv4)',
    );
    this.albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'HTTP from internet (IPv4, redirect to HTTPS)',
    );
    this.albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv6(),
      ec2.Port.tcp(443),
      'HTTPS from internet (IPv6)',
    );
    this.albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv6(),
      ec2.Port.tcp(80),
      'HTTP from internet (IPv6, redirect to HTTPS)',
    );

    this.ecsSecurityGroup = new ec2.SecurityGroup(this, 'EcsSg', {
      vpc,
      securityGroupName: `${PROJECT_PREFIX}-ecs-sg`,
      description: 'Report API Service - accepts traffic from ALB only',
      allowAllOutbound: true,
    });
    this.ecsSecurityGroup.addIngressRule(
      this.albSecurityGroup,
      ec2.Port.tcp(API_PORT),
      'API traffic from ALB',
    );

    this.dbSecurityGroup = new ec2.SecurityGroup(this, 'DbSg', {
      vpc,
      securityGroupName: `${PROJECT_PREFIX}-db-sg`,
      description: 'Crime Reports DB - accepts connections from ECS only',
      allowAllOutbound: false,
    });
    this.dbSecurityGroup.addIngressRule(
      this.ecsSecurityGroup,
      ec2.Port.tcp(DB_PORT),
      'PostgreSQL from ECS tasks',
    );

    this.redisSecurityGroup = new ec2.SecurityGroup(this, 'RedisSg', {
      vpc,
      securityGroupName: `${PROJECT_PREFIX}-redis-sg`,
      description: 'Feed Cache + Socket Adapter - accepts connections from ECS only',
      allowAllOutbound: false,
    });
    this.redisSecurityGroup.addIngressRule(
      this.ecsSecurityGroup,
      ec2.Port.tcp(REDIS_PORT),
      'Redis from ECS tasks',
    );

    new cdk.CfnOutput(this, 'AlbSgId', {
      value: this.albSecurityGroup.securityGroupId,
      description: 'ALB Security Group ID',
    });

    new cdk.CfnOutput(this, 'EcsSgId', {
      value: this.ecsSecurityGroup.securityGroupId,
      description: 'ECS Security Group ID',
    });

    new cdk.CfnOutput(this, 'DbSgId', {
      value: this.dbSecurityGroup.securityGroupId,
      description: 'DB Security Group ID',
    });

    new cdk.CfnOutput(this, 'RedisSgId', {
      value: this.redisSecurityGroup.securityGroupId,
      description: 'Redis Security Group ID',
    });
  }
}
