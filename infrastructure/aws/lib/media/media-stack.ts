import * as path from 'path';
import * as cdk from 'aws-cdk-lib';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
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
import { PROJECT_PREFIX, MODERATION_CONFIDENCE_THRESHOLD, MAX_UPLOAD_SIZE_BYTES } from '../config/constants';

const REKOGNITION_RETRY: sfn.RetryProps = {
  errors: ['Rekognition.ThrottlingException', 'Rekognition.InternalServerError', 'States.TaskFailed'],
  interval: cdk.Duration.seconds(5),
  maxAttempts: 3,
  backoffRate: 2,
};

const S3_RETRY: sfn.RetryProps = {
  errors: ['States.TaskFailed'],
  interval: cdk.Duration.seconds(3),
  maxAttempts: 2,
  backoffRate: 2,
};

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

    this.uploadsBucket.addToResourcePolicy(new iam.PolicyStatement({
      sid: 'DenyOversizedUploads',
      effect: iam.Effect.DENY,
      principals: [new iam.AnyPrincipal()],
      actions: ['s3:PutObject'],
      resources: [this.uploadsBucket.arnForObjects('*')],
      conditions: {
        NumericGreaterThan: { 's3:content-length-range': MAX_UPLOAD_SIZE_BYTES },
      },
    }));

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

    new cloudwatch.Alarm(this, 'DlqAlarm', {
      alarmName: `${PROJECT_PREFIX}-media-dlq-alarm`,
      alarmDescription: 'Alert when media pipeline failures land in the DLQ',
      metric: this.deadLetterQueue.metricApproximateNumberOfMessagesVisible({
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
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

    const definition = this.buildPipelineDefinition();

    this.stateMachine = new sfn.StateMachine(this, 'MediaPipeline', {
      stateMachineName: `${PROJECT_PREFIX}-media-pipeline`,
      definitionBody: sfn.DefinitionBody.fromChainable(definition),
      timeout: cdk.Duration.minutes(30),
      tracingEnabled: true,
    });

    this.uploadsBucket.grantRead(this.stateMachine);
    this.mediaBucket.grantWrite(this.stateMachine);

    // ── EventBridge Rule: S3 Upload → Step Functions ────────

    const uploadRule = new events.Rule(this, 'UploadTriggerRule', {
      ruleName: `${PROJECT_PREFIX}-upload-trigger`,
      description: 'Triggers media pipeline when media is uploaded to S3',
      eventPattern: {
        source: ['aws.s3'],
        detailType: ['Object Created'],
        detail: {
          bucket: { name: [this.uploadsBucket.bucketName] },
          object: { key: [{ prefix: 'videos/' }, { prefix: 'images/' }] },
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
    });

    new cdk.CfnOutput(this, 'MediaBucketName', {
      value: this.mediaBucket.bucketName,
    });

    new cdk.CfnOutput(this, 'CdnDomainName', {
      value: this.distribution.distributionDomainName,
    });

    new cdk.CfnOutput(this, 'StateMachineArn', {
      value: this.stateMachine.stateMachineArn,
    });

    new cdk.CfnOutput(this, 'TranscodeLambdaArn', {
      value: this.transcodeLambda.functionArn,
    });

    new cdk.CfnOutput(this, 'MediaConvertRoleArn', {
      value: this.mediaConvertRole.roleArn,
    });

    new cdk.CfnOutput(this, 'DlqUrl', {
      value: this.deadLetterQueue.queueUrl,
    });
  }

  private buildPipelineDefinition(): sfn.IChainable {
    // ── Shared: delete flagged content ────────────────────
    const deleteFlagged = new tasks.CallAwsService(this, 'DeleteFlaggedContent', {
      service: 's3',
      action: 'deleteObject',
      parameters: {
        Bucket: sfn.JsonPath.stringAt('$.bucket'),
        Key: sfn.JsonPath.stringAt('$.key'),
      },
      iamResources: [this.uploadsBucket.arnForObjects('*')],
      resultPath: sfn.JsonPath.DISCARD,
    }).addRetry(S3_RETRY);

    const flaggedEnd = new sfn.Pass(this, 'ContentFlagged', {
      result: sfn.Result.fromObject({ status: 'FLAGGED' }),
    });
    deleteFlagged.next(flaggedEnd);

    // ── Image path: sync moderation ──────────────────────
    const detectImageLabels = new tasks.CallAwsService(this, 'DetectImageModeration', {
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
    }).addRetry(REKOGNITION_RETRY);

    const copyToMedia = new tasks.CallAwsService(this, 'CopyImageToMedia', {
      service: 's3',
      action: 'copyObject',
      parameters: {
        Bucket: this.mediaBucket.bucketName,
        CopySource: sfn.JsonPath.format('{}/{}',
          sfn.JsonPath.stringAt('$.bucket'),
          sfn.JsonPath.stringAt('$.key'),
        ),
        Key: sfn.JsonPath.stringAt('$.key'),
      },
      iamResources: [this.mediaBucket.arnForObjects('*')],
      resultPath: sfn.JsonPath.DISCARD,
    }).addRetry(S3_RETRY);

    const imageComplete = new sfn.Pass(this, 'ImageProcessed', {
      result: sfn.Result.fromObject({ status: 'IMAGE_READY' }),
    });
    copyToMedia.next(imageComplete);

    const isImageFlagged = new sfn.Choice(this, 'IsImageFlagged')
      .when(sfn.Condition.and(
        sfn.Condition.isPresent('$.moderation.ModerationLabels[0]'),
        sfn.Condition.numberGreaterThanEquals('$.moderation.ModerationLabels[0].Confidence', MODERATION_CONFIDENCE_THRESHOLD),
      ), deleteFlagged)
      .otherwise(copyToMedia);

    const imagePath = detectImageLabels.next(isImageFlagged);

    // ── Video path: async moderation with polling ────────
    const startVideoModeration = new tasks.CallAwsService(this, 'StartVideoModeration', {
      service: 'rekognition',
      action: 'startContentModeration',
      parameters: {
        Video: {
          S3Object: {
            Bucket: sfn.JsonPath.stringAt('$.bucket'),
            Name: sfn.JsonPath.stringAt('$.key'),
          },
        },
      },
      iamResources: ['*'],
      resultPath: '$.videoJob',
    }).addRetry(REKOGNITION_RETRY);

    const waitForModeration = new sfn.Wait(this, 'WaitForModeration', {
      time: sfn.WaitTime.duration(cdk.Duration.seconds(20)),
    });

    const getVideoResults = new tasks.CallAwsService(this, 'GetVideoModerationResults', {
      service: 'rekognition',
      action: 'getContentModeration',
      parameters: {
        JobId: sfn.JsonPath.stringAt('$.videoJob.JobId'),
      },
      iamResources: ['*'],
      resultPath: '$.videoResults',
    }).addRetry(REKOGNITION_RETRY);

    const submitTranscode = new tasks.LambdaInvoke(this, 'SubmitTranscodeJob', {
      lambdaFunction: this.transcodeLambda,
      payload: sfn.TaskInput.fromObject({
        bucket: sfn.JsonPath.stringAt('$.bucket'),
        key: sfn.JsonPath.stringAt('$.key'),
      }),
      resultPath: '$.transcode',
    });

    const videoComplete = new sfn.Pass(this, 'VideoProcessed', {
      result: sfn.Result.fromObject({ status: 'VIDEO_TRANSCODING' }),
    });
    submitTranscode.next(videoComplete);

    const isVideoFlagged = new sfn.Choice(this, 'IsVideoFlagged')
      .when(sfn.Condition.and(
        sfn.Condition.isPresent('$.videoResults.ModerationLabels[0]'),
        sfn.Condition.numberGreaterThanEquals('$.videoResults.ModerationLabels[0].Confidence', MODERATION_CONFIDENCE_THRESHOLD),
      ), deleteFlagged)
      .otherwise(submitTranscode);

    const checkJobStatus = new sfn.Choice(this, 'CheckVideoJobStatus')
      .when(sfn.Condition.stringEquals('$.videoResults.JobStatus', 'IN_PROGRESS'), waitForModeration)
      .when(sfn.Condition.stringEquals('$.videoResults.JobStatus', 'SUCCEEDED'), isVideoFlagged)
      .otherwise(deleteFlagged);

    const videoPath = startVideoModeration
      .next(waitForModeration)
      .next(getVideoResults)
      .next(checkJobStatus);

    // ── Entry: route by file type ────────────────────────
    return new sfn.Choice(this, 'DetermineFileType')
      .when(sfn.Condition.stringMatches('$.key', 'images/*'), imagePath)
      .otherwise(videoPath);
  }
}
