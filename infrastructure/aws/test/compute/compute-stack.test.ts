import * as path from 'path';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { ComputeStack } from '../../lib/compute/compute-stack';

describe('ComputeStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    const env = { account: '123456789012', region: 'us-east-1' };

    const depsStack = new cdk.Stack(app, 'DepsStack', { env });

    const vpc = new ec2.Vpc(depsStack, 'Vpc', { maxAzs: 2 });
    const albSg = new ec2.SecurityGroup(depsStack, 'AlbSg', { vpc });
    const ecsSg = new ec2.SecurityGroup(depsStack, 'EcsSg', { vpc });

    const taskRole = new iam.Role(depsStack, 'TaskRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
    });

    const dbSecret = new secretsmanager.Secret(depsStack, 'DbSecret');

    const stack = new ComputeStack(app, 'TestCompute', {
      env,
      vpc,
      albSecurityGroup: albSg,
      ecsSecurityGroup: ecsSg,
      taskRole,
      dbSecret,
      redisEndpoint: 'redis.test.cache.amazonaws.com',
      redisPort: '6379',
      wafAclArn: 'arn:aws:wafv2:us-east-1:123456789012:regional/webacl/test/abc123',
      dockerDir: path.join(__dirname, '..', '..', '..', '..', 'backend', 'api'),
      s3UploadsBucket: 'crimereport-uploads-123456789012',
      s3MediaBucket: 'crimereport-media-123456789012',
      cdnDomain: 'd111111abcdef8.cloudfront.net',
      snsAndroidPlatformArn: 'arn:aws:sns:us-east-1:123456789012:app/GCM/crimereport-android',
      snsIosPlatformArn: 'arn:aws:sns:us-east-1:123456789012:app/APNS/crimereport-ios',
    });

    template = Template.fromStack(stack);
  });

  // ── ECR Repository ──────────────────────────────────────

  test('creates ECR repository with image scanning', () => {
    template.hasResourceProperties('AWS::ECR::Repository', {
      RepositoryName: 'crimereport-api',
      ImageScanningConfiguration: { ScanOnPush: true },
    });
  });

  test('ECR repository has lifecycle policy', () => {
    template.hasResourceProperties('AWS::ECR::Repository', {
      LifecyclePolicy: Match.objectLike({
        LifecyclePolicyText: Match.anyValue(),
      }),
    });
  });

  // ── CloudWatch Logs ─────────────────────────────────────

  test('creates CloudWatch log group with 30-day retention', () => {
    template.hasResourceProperties('AWS::Logs::LogGroup', {
      LogGroupName: '/ecs/crimereport-api',
      RetentionInDays: 30,
    });
  });

  // ── Execution Role ──────────────────────────────────────

  test('creates execution role with ECS task execution policy', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      RoleName: 'crimereport-ecs-execution',
      AssumeRolePolicyDocument: Match.objectLike({
        Statement: Match.arrayWith([
          Match.objectLike({
            Principal: Match.objectLike({
              Service: 'ecs-tasks.amazonaws.com',
            }),
          }),
        ]),
      }),
      ManagedPolicyArns: Match.arrayWith([
        Match.objectLike({
          'Fn::Join': Match.arrayWith([
            Match.arrayWith([
              Match.stringLikeRegexp('.*AmazonECSTaskExecutionRolePolicy'),
            ]),
          ]),
        }),
      ]),
    });
  });

  // ── ECS Cluster ─────────────────────────────────────────

  test('creates ECS cluster with Container Insights', () => {
    template.hasResourceProperties('AWS::ECS::Cluster', {
      ClusterName: 'crimereport-cluster',
      ClusterSettings: Match.arrayWith([
        Match.objectLike({
          Name: 'containerInsights',
          Value: 'enabled',
        }),
      ]),
    });
  });

  // ── Task Definition ─────────────────────────────────────

  test('creates Fargate task definition with correct CPU and memory', () => {
    template.hasResourceProperties('AWS::ECS::TaskDefinition', {
      Family: 'crimereport-api',
      Cpu: '256',
      Memory: '512',
      NetworkMode: 'awsvpc',
      RequiresCompatibilities: ['FARGATE'],
    });
  });

  test('task definition has container with port 3000', () => {
    template.hasResourceProperties('AWS::ECS::TaskDefinition', {
      ContainerDefinitions: Match.arrayWith([
        Match.objectLike({
          Name: 'api',
          PortMappings: Match.arrayWith([
            Match.objectLike({ ContainerPort: 3000 }),
          ]),
        }),
      ]),
    });
  });

  test('container has health check', () => {
    template.hasResourceProperties('AWS::ECS::TaskDefinition', {
      ContainerDefinitions: Match.arrayWith([
        Match.objectLike({
          HealthCheck: Match.objectLike({
            Command: ['CMD-SHELL', 'curl -f http://localhost:3000/health || exit 1'],
          }),
        }),
      ]),
    });
  });

  test('container has environment variables', () => {
    template.hasResourceProperties('AWS::ECS::TaskDefinition', {
      ContainerDefinitions: Match.arrayWith([
        Match.objectLike({
          Environment: Match.arrayWith([
            Match.objectLike({ Name: 'NODE_ENV', Value: 'production' }),
            Match.objectLike({ Name: 'PORT', Value: '3000' }),
            Match.objectLike({ Name: 'REDIS_HOST', Value: 'redis.test.cache.amazonaws.com' }),
          ]),
        }),
      ]),
    });
  });

  test('container has production environment variables', () => {
    template.hasResourceProperties('AWS::ECS::TaskDefinition', {
      ContainerDefinitions: Match.arrayWith([
        Match.objectLike({
          Environment: Match.arrayWith([
            Match.objectLike({ Name: 'LOG_LEVEL', Value: 'info' }),
            Match.objectLike({ Name: 'CORS_ORIGIN', Value: 'https://reportcrime.app' }),
            Match.objectLike({ Name: 'WS_PING_INTERVAL', Value: '25000' }),
            Match.objectLike({ Name: 'WS_PING_TIMEOUT', Value: '5000' }),
          ]),
        }),
      ]),
    });
  });

  test('container has database secret injected', () => {
    template.hasResourceProperties('AWS::ECS::TaskDefinition', {
      ContainerDefinitions: Match.arrayWith([
        Match.objectLike({
          Secrets: Match.arrayWith([
            Match.objectLike({ Name: 'DATABASE_URL' }),
          ]),
        }),
      ]),
    });
  });

  test('container has CloudWatch log configuration', () => {
    template.hasResourceProperties('AWS::ECS::TaskDefinition', {
      ContainerDefinitions: Match.arrayWith([
        Match.objectLike({
          LogConfiguration: Match.objectLike({
            LogDriver: 'awslogs',
            Options: Match.objectLike({
              'awslogs-stream-prefix': 'api',
            }),
          }),
        }),
      ]),
    });
  });

  // ── ALB ─────────────────────────────────────────────────

  test('creates internet-facing ALB', () => {
    template.hasResourceProperties('AWS::ElasticLoadBalancingV2::LoadBalancer', {
      Name: 'crimereport-alb',
      Scheme: 'internet-facing',
      Type: 'application',
    });
  });

  test('ALB has HTTP listener on port 80', () => {
    template.hasResourceProperties('AWS::ElasticLoadBalancingV2::Listener', {
      Port: 80,
      Protocol: 'HTTP',
    });
  });

  test('target group has health check on /health', () => {
    template.hasResourceProperties('AWS::ElasticLoadBalancingV2::TargetGroup', {
      Name: 'crimereport-api-tg',
      Port: 3000,
      Protocol: 'HTTP',
      TargetType: 'ip',
      HealthCheckPath: '/health',
    });
  });

  // ── Fargate Service ─────────────────────────────────────

  test('creates Fargate service with correct config', () => {
    template.hasResourceProperties('AWS::ECS::Service', {
      ServiceName: 'crimereport-api',
      LaunchType: 'FARGATE',
      DesiredCount: 1,
      DeploymentConfiguration: Match.objectLike({
        MinimumHealthyPercent: 50,
        MaximumPercent: 200,
      }),
    });
  });

  test('Fargate service has deployment circuit breaker with rollback', () => {
    template.hasResourceProperties('AWS::ECS::Service', {
      DeploymentConfiguration: Match.objectLike({
        DeploymentCircuitBreaker: {
          Enable: true,
          Rollback: true,
        },
      }),
    });
  });

  test('Fargate service does not assign public IP', () => {
    template.hasResourceProperties('AWS::ECS::Service', {
      NetworkConfiguration: Match.objectLike({
        AwsvpcConfiguration: Match.objectLike({
          AssignPublicIp: 'DISABLED',
        }),
      }),
    });
  });

  // ── Auto-Scaling ────────────────────────────────────────

  test('creates auto-scaling target', () => {
    template.hasResourceProperties('AWS::ApplicationAutoScaling::ScalableTarget', {
      MinCapacity: 1,
      MaxCapacity: 10,
      ScalableDimension: 'ecs:service:DesiredCount',
      ServiceNamespace: 'ecs',
    });
  });

  test('creates CPU target tracking scaling policy', () => {
    template.hasResourceProperties('AWS::ApplicationAutoScaling::ScalingPolicy', {
      PolicyType: 'TargetTrackingScaling',
      TargetTrackingScalingPolicyConfiguration: Match.objectLike({
        TargetValue: 70,
        PredefinedMetricSpecification: Match.objectLike({
          PredefinedMetricType: 'ECSServiceAverageCPUUtilization',
        }),
      }),
    });
  });

  // ── WAF Association ─────────────────────────────────────

  test('associates WAF WebACL with ALB', () => {
    template.hasResourceProperties('AWS::WAFv2::WebACLAssociation', {
      WebACLArn: 'arn:aws:wafv2:us-east-1:123456789012:regional/webacl/test/abc123',
    });
  });
});
