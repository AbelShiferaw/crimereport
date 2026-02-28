import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as rds from 'aws-cdk-lib/aws-rds';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { MonitoringStack } from '../../lib/monitoring/monitoring-stack';

describe('MonitoringStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    const env = { account: '123456789012', region: 'us-east-1' };

    const depsStack = new cdk.Stack(app, 'DepsStack', { env });
    const vpc = new ec2.Vpc(depsStack, 'Vpc', { maxAzs: 2 });

    const dbCluster = new rds.DatabaseCluster(depsStack, 'Db', {
      engine: rds.DatabaseClusterEngine.auroraPostgres({
        version: rds.AuroraPostgresEngineVersion.VER_16_4,
      }),
      writer: rds.ClusterInstance.serverlessV2('Writer'),
      vpc,
    });

    const cluster = new ecs.Cluster(depsStack, 'Cluster', { vpc });
    const taskDef = new ecs.FargateTaskDefinition(depsStack, 'TaskDef');
    taskDef.addContainer('api', {
      image: ecs.ContainerImage.fromRegistry('node:20-alpine'),
      memoryLimitMiB: 512,
    });
    const service = new ecs.FargateService(depsStack, 'Service', {
      cluster,
      taskDefinition: taskDef,
    });

    const alb = new elbv2.ApplicationLoadBalancer(depsStack, 'Alb', {
      vpc,
      internetFacing: true,
    });

    const stack = new MonitoringStack(app, 'TestMonitoring', {
      env,
      dbCluster,
      redisReplicationGroupId: 'test-redis',
      ecsCluster: cluster,
      ecsService: service,
      alb,
    });

    template = Template.fromStack(stack);
  });

  // ── Alarms ─────────────────────────────────────────────

  test('creates database CPU alarm', () => {
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmName: 'crimereport-db-cpu-high',
      Threshold: 80,
      EvaluationPeriods: 3,
    });
  });

  test('creates database connections alarm', () => {
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmName: 'crimereport-db-connections-high',
      Threshold: 50,
    });
  });

  test('creates database memory alarm', () => {
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmName: 'crimereport-db-memory-low',
    });
  });

  test('creates Redis CPU alarm', () => {
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmName: 'crimereport-redis-cpu-high',
      Threshold: 80,
    });
  });

  test('creates Redis memory alarm', () => {
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmName: 'crimereport-redis-memory-high',
      Threshold: 80,
    });
  });

  test('creates Redis evictions alarm', () => {
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmName: 'crimereport-redis-evictions',
      Threshold: 100,
    });
  });

  test('creates ECS CPU alarm', () => {
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmName: 'crimereport-ecs-cpu-high',
      Threshold: 85,
    });
  });

  test('creates ECS memory alarm', () => {
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmName: 'crimereport-ecs-memory-high',
      Threshold: 85,
    });
  });

  test('creates ALB 5xx alarm', () => {
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmName: 'crimereport-alb-5xx-high',
      Threshold: 10,
    });
  });

  test('creates ALB latency alarm', () => {
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmName: 'crimereport-alb-latency-high',
      Threshold: 2,
    });
  });

  test('creates 10 alarms total', () => {
    template.resourceCountIs('AWS::CloudWatch::Alarm', 10);
  });

  // ── Dashboard ──────────────────────────────────────────

  test('creates operations dashboard', () => {
    template.hasResourceProperties('AWS::CloudWatch::Dashboard', {
      DashboardName: 'crimereport-operations',
    });
  });

  test('creates exactly one dashboard', () => {
    template.resourceCountIs('AWS::CloudWatch::Dashboard', 1);
  });
});
