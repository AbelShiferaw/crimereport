import * as path from 'path';
import * as cdk from 'aws-cdk-lib';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as lambdaNode from 'aws-cdk-lib/aws-lambda-nodejs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as sfn from 'aws-cdk-lib/aws-stepfunctions';
import * as tasks from 'aws-cdk-lib/aws-stepfunctions-tasks';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import { Construct } from 'constructs';
import { PROJECT_PREFIX } from '../config/constants';

export class MediaStack extends cdk.Stack {
  public readonly uploadsBucket: s3.Bucket;
  public readonly mediaBucket: s3.Bucket;
  public readonly distribution: cloudfront.Distribution;
  public readonly transcodeLambda: lambdaNode.NodejsFunction;
  public readonly deadLetterQueue: sqs.Queue;
  public readonly mediaConvertRole: iam.Role;
  public readonly stateMachine: sfn.StateMachine;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // ── S3 Buckets ──────────────────────────────────────────

    this.uploadsBucket = new s3.Bucket(this, 'UploadsBucket', {
      bucketName: `${PROJECT_PREFIX}-uploads-${this.account}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      versioned: false,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      eventBridgeEnabled: true,
      cors: [
        {
          allowedMethods: [s3.HttpMethods.PUT, s3.HttpMethods.POST],
          allowedOrigins: ['*'],
          allowedHeaders: ['*'],
          maxAge: 3600,
        },
      ],
      lifecycleRules: [
        {
          id: 'delete-after-processing',
          expiration: cdk.Duration.days(1),
          enabled: true,
        },
      ],
    });

    this.mediaBucket = new s3.Bucket(this, 'MediaBucket', {
      bucketName: `${PROJECT_PREFIX}-media-${this.account}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      versioned: false,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // ── CloudFront CDN ──────────────────────────────────────

    this.distribution = new cloudfront.Distribution(this, 'MediaCdn', {
      comment: 'CrimeReport media CDN',
      defaultBehavior: {
        origin: origins.S3BucketOrigin.withOriginAccessControl(this.mediaBucket),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
        cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
        compress: true,
      },
      priceClass: cloudfront.PriceClass.PRICE_CLASS_100,
      enabled: true,
      httpVersion: cloudfront.HttpVersion.HTTP2_AND_3,
    });

    // ── Dead Letter Queue ───────────────────────────────────

    this.deadLetterQueue = new sqs.Queue(this, 'MediaDlq', {
      queueName: `${PROJECT_PREFIX}-media-dlq`,
      retentionPeriod: cdk.Duration.days(14),
      encryption: sqs.QueueEncryption.SQS_MANAGED,
    });

    // ── MediaConvert Role ───────────────────────────────────

    this.mediaConvertRole = new iam.Role(this, 'MediaConvertRole', {
      roleName: `${PROJECT_PREFIX}-mediaconvert`,
      assumedBy: new iam.ServicePrincipal('mediaconvert.amazonaws.com'),
      description: 'MediaConvert role - read raw uploads, write processed media',
    });

    this.uploadsBucket.grantRead(this.mediaConvertRole);
    this.mediaBucket.grantWrite(this.mediaConvertRole);

    // ── Transcode Lambda (invoked by Step Functions) ────────

    this.transcodeLambda = new lambdaNode.NodejsFunction(this, 'TranscodeTrigger', {
      functionName: `${PROJECT_PREFIX}-transcode-trigger`,
      description: 'Builds and submits MediaConvert transcoding job (invoked by Step Functions)',
      entry: path.join(__dirname, '..', '..', '..', '..', 'backend', 'functions', 'transcode-trigger', 'index.ts'),
      handler: 'handler',
      runtime: lambda.Runtime.NODEJS_20_X,
      architecture: lambda.Architecture.ARM_64,
      memorySize: 256,
      timeout: cdk.Duration.seconds(30),
      environment: {
        MEDIACONVERT_ROLE_ARN: this.mediaConvertRole.roleArn,
        OUTPUT_BUCKET: this.mediaBucket.bucketName,
      },
      bundling: {
        externalModules: ['@aws-sdk/*'],
        minify: true,
        sourceMap: true,
      },
    });

    this.transcodeLambda.addToRolePolicy(
      new iam.PolicyStatement({
        sid: 'MediaConvertAccess',
        effect: iam.Effect.ALLOW,
        actions: [
          'mediaconvert:CreateJob',
          'mediaconvert:DescribeEndpoints',
        ],
        resources: ['*'],
      }),
    );

    this.transcodeLambda.addToRolePolicy(
      new iam.PolicyStatement({
        sid: 'PassMediaConvertRole',
        effect: iam.Effect.ALLOW,
        actions: ['iam:PassRole'],
        resources: [this.mediaConvertRole.roleArn],
      }),
    );

    // ── Step Functions State Machine ────────────────────────

    const moderateContent = new tasks.CallAwsService(this, 'RekognitionModerate', {
      service: 'rekognition',
      action: 'detectModerationLabels',
      parameters: {
        Image: {
          S3Object: {
            Bucket: sfn.JsonPath.stringAt('$.bucket'),
            Name: sfn.JsonPath.stringAt('$.key'),
          },
        },
      },
      iamResources: ['*'],
      resultPath: '$.moderation',
    });

    const deleteFlagged = new tasks.CallAwsService(this, 'DeleteFlaggedContent', {
      service: 's3',
      action: 'deleteObject',
      parameters: {
        Bucket: sfn.JsonPath.stringAt('$.bucket'),
        Key: sfn.JsonPath.stringAt('$.key'),
      },
      iamResources: [
        this.uploadsBucket.arnForObjects('*'),
      ],
      resultPath: sfn.JsonPath.DISCARD,
    });

    const flaggedEnd = new sfn.Pass(this, 'ContentFlagged', {
      result: sfn.Result.fromObject({ status: 'FLAGGED' }),
    });

    deleteFlagged.next(flaggedEnd);

    const submitTranscode = new tasks.LambdaInvoke(this, 'SubmitTranscodeJob', {
      lambdaFunction: this.transcodeLambda,
      payload: sfn.TaskInput.fromObject({
        bucket: sfn.JsonPath.stringAt('$.bucket'),
        key: sfn.JsonPath.stringAt('$.key'),
      }),
      resultPath: '$.transcode',
    });

    const isFlagged = new sfn.Choice(this, 'IsFlagged')
      .when(
        sfn.Condition.isPresent('$.moderation.ModerationLabels[0]'),
        deleteFlagged,
      )
      .otherwise(submitTranscode);

    const definition = moderateContent.next(isFlagged);

    this.stateMachine = new sfn.StateMachine(this, 'MediaPipeline', {
      stateMachineName: `${PROJECT_PREFIX}-media-pipeline`,
      definitionBody: sfn.DefinitionBody.fromChainable(definition),
      timeout: cdk.Duration.minutes(15),
      tracingEnabled: true,
    });

    // ── EventBridge Rule: S3 Upload → Step Functions ────────

    const uploadRule = new events.Rule(this, 'UploadTriggerRule', {
      ruleName: `${PROJECT_PREFIX}-upload-trigger`,
      description: 'Triggers media pipeline when video is uploaded to S3',
      eventPattern: {
        source: ['aws.s3'],
        detailType: ['Object Created'],
        detail: {
          bucket: { name: [this.uploadsBucket.bucketName] },
          object: { key: [{ prefix: 'videos/' }] },
        },
      },
    });

    uploadRule.addTarget(new targets.SfnStateMachine(this.stateMachine, {
      input: events.RuleTargetInput.fromObject({
        bucket: events.EventField.fromPath('$.detail.bucket.name'),
        key: events.EventField.fromPath('$.detail.object.key'),
      }),
      deadLetterQueue: this.deadLetterQueue,
    }));

    // ── Outputs ─────────────────────────────────────────────

    new cdk.CfnOutput(this, 'UploadsBucketName', {
      value: this.uploadsBucket.bucketName,
      description: 'Raw uploads S3 bucket name',
    });

    new cdk.CfnOutput(this, 'MediaBucketName', {
      value: this.mediaBucket.bucketName,
      description: 'Processed media S3 bucket name',
    });

    new cdk.CfnOutput(this, 'CdnDomainName', {
      value: this.distribution.distributionDomainName,
      description: 'CloudFront CDN domain for media delivery',
    });

    new cdk.CfnOutput(this, 'StateMachineArn', {
      value: this.stateMachine.stateMachineArn,
      description: 'Media processing pipeline state machine ARN',
    });

    new cdk.CfnOutput(this, 'TranscodeLambdaArn', {
      value: this.transcodeLambda.functionArn,
      description: 'MediaConvert job builder Lambda ARN',
    });

    new cdk.CfnOutput(this, 'MediaConvertRoleArn', {
      value: this.mediaConvertRole.roleArn,
      description: 'MediaConvert IAM role ARN',
    });

    new cdk.CfnOutput(this, 'DlqUrl', {
      value: this.deadLetterQueue.queueUrl,
      description: 'Dead letter queue URL for failed pipeline executions',
    });
  }
}
