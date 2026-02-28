import * as path from 'path';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as ecrAssets from 'aws-cdk-lib/aws-ecr-assets';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as wafv2 from 'aws-cdk-lib/aws-wafv2';
import { Construct } from 'constructs';
import {
  PROJECT_PREFIX,
  API_PORT,
  ECS_CPU,
  ECS_MEMORY,
  ECS_DESIRED_COUNT,
  ECS_MIN_TASKS,
  ECS_MAX_TASKS,
  ECS_CPU_TARGET_PERCENT,
  ECR_MAX_IMAGE_COUNT,
  LOG_RETENTION_DAYS,
} from '../config/constants';

export interface ComputeStackProps extends cdk.StackProps {
  vpc: ec2.IVpc;
  albSecurityGroup: ec2.SecurityGroup;
  ecsSecurityGroup: ec2.SecurityGroup;
  taskRole: iam.IRole;
  dbSecret: secretsmanager.ISecret;
  redisEndpoint: string;
  redisPort: string;
  wafAclArn: string;
  dockerDir: string;
}

export class ComputeStack extends cdk.Stack {
  public readonly repository: ecr.Repository;
  public readonly cluster: ecs.Cluster;
  public readonly service: ecs.FargateService;
  public readonly alb: elbv2.ApplicationLoadBalancer;
  public readonly listener: elbv2.ApplicationListener;
  public readonly executionRole: iam.Role;

  constructor(scope: Construct, id: string, props: ComputeStackProps) {
    super(scope, id, props);

    const {
      vpc,
      albSecurityGroup,
      ecsSecurityGroup,
      taskRole,
      dbSecret,
      redisEndpoint,
      redisPort,
      wafAclArn,
      dockerDir,
    } = props;

    // ── ECR Repository ──────────────────────────────────────

    this.repository = new ecr.Repository(this, 'ApiRepo', {
      repositoryName: `${PROJECT_PREFIX}-api`,
      imageScanOnPush: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      emptyOnDelete: true,
      lifecycleRules: [
        {
          maxImageCount: ECR_MAX_IMAGE_COUNT,
          description: `Keep last ${ECR_MAX_IMAGE_COUNT} images`,
        },
      ],
    });

    // ── CloudWatch Log Group ────────────────────────────────

    const logGroup = new logs.LogGroup(this, 'ApiLogGroup', {
      logGroupName: `/ecs/${PROJECT_PREFIX}-api`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // ── ECS Execution Role ───────────────────────────────────
    // Created here (not in IamStack) to avoid cyclic cross-stack
    // references: CDK auto-grants this role log permissions pointing
    // back at the log group in this stack.

    this.executionRole = new iam.Role(this, 'EcsExecutionRole', {
      roleName: `${PROJECT_PREFIX}-ecs-execution`,
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
    });

    this.executionRole.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName(
        'service-role/AmazonECSTaskExecutionRolePolicy',
      ),
    );

    dbSecret.grantRead(this.executionRole);

    // ── ECS Cluster ─────────────────────────────────────────

    this.cluster = new ecs.Cluster(this, 'Cluster', {
      clusterName: `${PROJECT_PREFIX}-cluster`,
      vpc,
      containerInsightsV2: ecs.ContainerInsights.ENABLED,
    });

    // ── Task Definition ─────────────────────────────────────

    const taskDef = new ecs.FargateTaskDefinition(this, 'ApiTaskDef', {
      family: `${PROJECT_PREFIX}-api`,
      cpu: ECS_CPU,
      memoryLimitMiB: ECS_MEMORY,
      executionRole: this.executionRole,
      taskRole,
    });

    const imageAsset = new ecrAssets.DockerImageAsset(this, 'ApiImage', {
      directory: dockerDir,
      platform: ecrAssets.Platform.LINUX_AMD64,
    });

    const container = taskDef.addContainer('api', {
      image: ecs.ContainerImage.fromDockerImageAsset(imageAsset),
      logging: ecs.LogDrivers.awsLogs({
        logGroup,
        streamPrefix: 'api',
      }),
      environment: {
        NODE_ENV: 'production',
        PORT: String(API_PORT),
        REDIS_HOST: redisEndpoint,
        REDIS_PORT: redisPort,
      },
      secrets: {
        DATABASE_URL: ecs.Secret.fromSecretsManager(dbSecret),
      },
      healthCheck: {
        command: ['CMD-SHELL', `curl -f http://localhost:${API_PORT}/health || exit 1`],
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        retries: 3,
        startPeriod: cdk.Duration.seconds(120),
      },
    });

    container.addPortMappings({
      containerPort: API_PORT,
      protocol: ecs.Protocol.TCP,
    });

    // ── Application Load Balancer ───────────────────────────

    this.alb = new elbv2.ApplicationLoadBalancer(this, 'Alb', {
      loadBalancerName: `${PROJECT_PREFIX}-alb`,
      vpc,
      internetFacing: true,
      securityGroup: albSecurityGroup,
      vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC },
    });

    const targetGroup = new elbv2.ApplicationTargetGroup(this, 'ApiTargetGroup', {
      targetGroupName: `${PROJECT_PREFIX}-api-tg`,
      vpc,
      port: API_PORT,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.IP,
      healthCheck: {
        path: '/health',
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
        healthyHttpCodes: '200',
      },
      stickinessCookieDuration: cdk.Duration.days(1),
    });

    this.listener = this.alb.addListener('HttpListener', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultTargetGroups: [targetGroup],
    });

    // ── Fargate Service ─────────────────────────────────────

    this.service = new ecs.FargateService(this, 'ApiService', {
      serviceName: `${PROJECT_PREFIX}-api`,
      cluster: this.cluster,
      taskDefinition: taskDef,
      desiredCount: ECS_DESIRED_COUNT,
      securityGroups: [ecsSecurityGroup],
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      assignPublicIp: false,
      minHealthyPercent: 50,
      maxHealthyPercent: 200,
      circuitBreaker: { enable: true, rollback: true },
    });

    this.service.attachToApplicationTargetGroup(targetGroup);

    // ── Auto-Scaling ────────────────────────────────────────

    const scaling = this.service.autoScaleTaskCount({
      minCapacity: ECS_MIN_TASKS,
      maxCapacity: ECS_MAX_TASKS,
    });

    scaling.scaleOnCpuUtilization('CpuScaling', {
      targetUtilizationPercent: ECS_CPU_TARGET_PERCENT,
      scaleInCooldown: cdk.Duration.seconds(300),
      scaleOutCooldown: cdk.Duration.seconds(60),
    });

    // ── WAF Association ─────────────────────────────────────

    new wafv2.CfnWebACLAssociation(this, 'WafAlbAssociation', {
      resourceArn: this.alb.loadBalancerArn,
      webAclArn: wafAclArn,
    });

    // ── Outputs ─────────────────────────────────────────────

    new cdk.CfnOutput(this, 'EcrRepositoryUri', {
      value: this.repository.repositoryUri,
    });

    new cdk.CfnOutput(this, 'ClusterName', {
      value: this.cluster.clusterName,
    });

    new cdk.CfnOutput(this, 'ServiceName', {
      value: this.service.serviceName,
    });

    new cdk.CfnOutput(this, 'AlbDnsName', {
      value: this.alb.loadBalancerDnsName,
    });

    new cdk.CfnOutput(this, 'AlbArn', {
      value: this.alb.loadBalancerArn,
    });
  }
}
