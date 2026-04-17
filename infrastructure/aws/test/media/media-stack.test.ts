import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { MediaStack } from '../../lib/media/media-stack';

describe('MediaStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    const stack = new MediaStack(app, 'TestMedia', {
      env: { account: '123456789012', region: 'us-east-1' },
    });
    template = Template.fromStack(stack);
  });

  test('creates uploads bucket with CORS and lifecycle', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketName: Match.stringLikeRegexp('crimereport-uploads-'),
      CorsConfiguration: { CorsRules: Match.arrayWith([Match.objectLike({ AllowedMethods: ['PUT', 'POST'] })]) },
      LifecycleConfiguration: { Rules: Match.arrayWith([Match.objectLike({ ExpirationInDays: 1, Status: 'Enabled' })]) },
    });
  });

  test('uploads bucket has EventBridge notifications enabled', () => {
    template.hasResourceProperties('Custom::S3BucketNotifications', {
      NotificationConfiguration: Match.objectLike({ EventBridgeConfiguration: {} }),
    });
  });

  test('creates media bucket with encryption', () => {
    template.hasResourceProperties('AWS::S3::Bucket', { BucketName: Match.stringLikeRegexp('crimereport-media-') });
  });

  test('creates CloudFront distribution with HTTPS and compression', () => {
    template.resourceCountIs('AWS::CloudFront::Distribution', 1);
    template.hasResourceProperties('AWS::CloudFront::Distribution', {
      DistributionConfig: Match.objectLike({
        Enabled: true, HttpVersion: 'http2and3', PriceClass: 'PriceClass_100',
        DefaultCacheBehavior: Match.objectLike({ ViewerProtocolPolicy: 'redirect-to-https', Compress: true }),
      }),
    });
  });

  test('creates dead letter queue with 14-day retention', () => {
    template.hasResourceProperties('AWS::SQS::Queue', { QueueName: 'crimereport-media-dlq', MessageRetentionPeriod: 1209600 });
  });

  test('creates DLQ alarm for pipeline failures', () => {
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmName: 'crimereport-media-dlq-alarm', Threshold: 1, EvaluationPeriods: 1,
      ComparisonOperator: 'GreaterThanOrEqualToThreshold', TreatMissingData: 'notBreaching',
    });
  });

  test('creates MediaConvert IAM role', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      RoleName: 'crimereport-mediaconvert',
      AssumeRolePolicyDocument: Match.objectLike({
        Statement: Match.arrayWith([Match.objectLike({ Principal: { Service: 'mediaconvert.amazonaws.com' } })]),
      }),
    });
  });

  test('creates Lambda function with Node.js 20 ARM64', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      FunctionName: 'crimereport-transcode-trigger', Runtime: 'nodejs20.x', Architectures: ['arm64'], MemorySize: 256, Timeout: 30,
    });
  });

  test('Lambda has MediaConvert permissions', () => {
    template.hasResourceProperties('AWS::IAM::Policy', {
      PolicyDocument: Match.objectLike({
        Statement: Match.arrayWith([Match.objectLike({ Action: ['mediaconvert:CreateJob', 'mediaconvert:DescribeEndpoints'], Effect: 'Allow' })]),
      }),
    });
  });

  test('Lambda has environment variables', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      Environment: { Variables: Match.objectLike({ MEDIACONVERT_ROLE_ARN: Match.anyValue(), OUTPUT_BUCKET: Match.anyValue() }) },
    });
  });

  test('creates Step Functions state machine', () => {
    template.resourceCountIs('AWS::StepFunctions::StateMachine', 1);
    template.hasResourceProperties('AWS::StepFunctions::StateMachine', { StateMachineName: 'crimereport-media-pipeline', TracingConfiguration: { Enabled: true } });
  });

  test('state machine role has image moderation permission', () => {
    template.hasResourceProperties('AWS::IAM::Policy', {
      PolicyDocument: Match.objectLike({ Statement: Match.arrayWith([Match.objectLike({ Action: 'rekognition:detectModerationLabels', Effect: 'Allow' })]) }),
    });
  });

  test('state machine role has video moderation permissions', () => {
    template.hasResourceProperties('AWS::IAM::Policy', {
      PolicyDocument: Match.objectLike({ Statement: Match.arrayWith([Match.objectLike({ Action: 'rekognition:startContentModeration', Effect: 'Allow' })]) }),
    });
    template.hasResourceProperties('AWS::IAM::Policy', {
      PolicyDocument: Match.objectLike({ Statement: Match.arrayWith([Match.objectLike({ Action: 'rekognition:getContentModeration', Effect: 'Allow' })]) }),
    });
  });

  test('state machine role has S3 read access on uploads bucket', () => {
    template.hasResourceProperties('AWS::IAM::Policy', {
      PolicyDocument: Match.objectLike({ Statement: Match.arrayWith([Match.objectLike({ Action: Match.arrayWith(['s3:GetObject*', 's3:GetBucket*', 's3:List*']), Effect: 'Allow' })]) }),
    });
  });

  test('state machine role has S3 delete permissions', () => {
    template.hasResourceProperties('AWS::IAM::Policy', {
      PolicyDocument: Match.objectLike({ Statement: Match.arrayWith([Match.objectLike({ Action: 's3:deleteObject', Effect: 'Allow' })]) }),
    });
  });

  test('state machine role has S3 write access on media bucket', () => {
    template.hasResourceProperties('AWS::IAM::Policy', {
      PolicyDocument: Match.objectLike({ Statement: Match.arrayWith([Match.objectLike({ Action: Match.arrayWith(['s3:PutObject', 's3:Abort*']), Effect: 'Allow' })]) }),
    });
  });

  test('state machine role has S3 copyObject permission', () => {
    template.hasResourceProperties('AWS::IAM::Policy', {
      PolicyDocument: Match.objectLike({ Statement: Match.arrayWith([Match.objectLike({ Action: 's3:copyObject', Effect: 'Allow' })]) }),
    });
  });

  test('creates EventBridge rule for S3 uploads with videos/ and images/ prefixes', () => {
    template.hasResourceProperties('AWS::Events::Rule', {
      Name: 'crimereport-upload-trigger',
      EventPattern: Match.objectLike({ source: ['aws.s3'], 'detail-type': ['Object Created'], detail: Match.objectLike({ object: { key: [{ prefix: 'videos/' }, { prefix: 'images/' }] } }) }),
    });
  });

  test('EventBridge rule targets Step Functions with DLQ', () => {
    template.hasResourceProperties('AWS::Events::Rule', {
      Name: 'crimereport-upload-trigger',
      Targets: Match.arrayWith([Match.objectLike({ Arn: Match.anyValue(), DeadLetterConfig: Match.objectLike({ Arn: Match.anyValue() }) })]),
    });
  });

  test('uploads bucket has blockPublicAccess enabled', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketName: Match.stringLikeRegexp('crimereport-uploads-'),
      PublicAccessBlockConfiguration: { BlockPublicAcls: true, BlockPublicPolicy: true, IgnorePublicAcls: true, RestrictPublicBuckets: true },
    });
  });

  test('media bucket has blockPublicAccess enabled', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketName: Match.stringLikeRegexp('crimereport-media-'),
      PublicAccessBlockConfiguration: { BlockPublicAcls: true, BlockPublicPolicy: true, IgnorePublicAcls: true, RestrictPublicBuckets: true },
    });
  });

  test('uploads bucket lifecycle rule expires after 1 day', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketName: Match.stringLikeRegexp('crimereport-uploads-'),
      LifecycleConfiguration: { Rules: Match.arrayWith([Match.objectLike({ ExpirationInDays: 1, Status: 'Enabled' })]) },
    });
  });

  test('uploads bucket has versioning enabled', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketName: Match.stringLikeRegexp('crimereport-uploads-'),
      VersioningConfiguration: { Status: 'Enabled' },
    });
  });

  test('media bucket has versioning enabled', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketName: Match.stringLikeRegexp('crimereport-media-'),
      VersioningConfiguration: { Status: 'Enabled' },
    });
  });

  test('uploads bucket does NOT have Lambda notification', () => {
    const resources = template.findResources('Custom::S3BucketNotifications');
    for (const [, resource] of Object.entries(resources)) {
      const props = resource.Properties?.NotificationConfiguration;
      if (props?.LambdaFunctionConfigurations) {
        fail('Uploads bucket should not have Lambda notifications - uses EventBridge instead');
      }
    }
  });
});
