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
import { PROJECT_PREFIX, MODERATION_CONFIDENCE_THRESHOLD } from '../config/constants';

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

export interface MediaStackProps extends cdk.StackProps {
  /** Custom domain name for the CloudFront distribution (e.g. cdn.reportcrime.app). */
  cdnDomainName?: string;
}

export class MediaStack extends cdk.Stack {
  public readonly uploadsBucket: s3.Bucket;
  public readonly mediaBucket: s3.Bucket;
  public readonly distribution: cloudfront.Distribution;
  public readonly transcodeLambda: lambdaNode.NodejsFunction;
  public readonly deadLetterQueue: sqs.Queue;
  public readonly mediaConvertRole: iam.Role;
  public readonly stateMachine: sfn.StateMachine;

  constructor(scope: Construct, id: string, props?: MediaStackProps) {
    super(scope, id, props);

    // ── S3 Buckets ──────────────────────────────────────────

    this.uploadsBucket = new s3.Bucket(this, 'UploadsBucket', {
      bucketName: `${PROJECT_PREFIX}-uploads-${this.account}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      versioned: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
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
        {
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
    });

    this.mediaBucket = new s3.Bucket(this, 'MediaBucket', {
      bucketName: `${PROJECT_PREFIX}-media-${this.account}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      versioned: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      lifecycleRules: [{
        noncurrentVersionExpiration: cdk.Duration.days(30),
      }],
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
      domainNames: props?.cdnDomainName ? [props.cdnDomainName] : undefined,
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
    this.uploadsBucket.grantDelete(this.stateMachine);
    this.mediaBucket.grantRead(this.stateMachine);
    this.mediaBucket.grantWrite(this.stateMachine);
    this.mediaBucket.grantDelete(this.stateMachine);

    // The state machine polls the MediaConvert job submitted by the Lambda.
    this.stateMachine.addToRolePolicy(
      new iam.PolicyStatement({
        sid: 'MediaConvertJobAccess',
        effect: iam.Effect.ALLOW,
        actions: ['mediaconvert:GetJob', 'mediaconvert:DescribeEndpoints'],
        resources: ['*'],
      }),
    );

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
    // ── Image path: shared flagged-deletion ──────────────
    const deleteFlaggedImage = new tasks.CallAwsService(this, 'DeleteFlaggedContent', {
      service: 's3',
      action: 'deleteObject',
      parameters: {
        Bucket: sfn.JsonPath.stringAt('$.bucket'),
        Key: sfn.JsonPath.stringAt('$.key'),
      },
      iamResources: [this.uploadsBucket.arnForObjects('*')],
      resultPath: sfn.JsonPath.DISCARD,
    }).addRetry(S3_RETRY);

    const imageFlaggedEnd = new sfn.Pass(this, 'ContentFlagged', {
      result: sfn.Result.fromObject({ status: 'FLAGGED' }),
    });
    deleteFlaggedImage.next(imageFlaggedEnd);

    // ── Shared: processing error (system failure) ─────────
    // Distinct terminal branch for AWS-side failures (e.g. Rekognition
    // unsupported codec, transient outages). Does NOT delete the
    // user's upload — the file remains in the uploads bucket so ops
    // can re-process or investigate. Each entry-point Pass state
    // captures a `reason` then funnels into a shared CloudWatch
    // PutMetricData call so the monitoring stack can alarm on it.
    const emitProcessingErrorMetric = new tasks.CallAwsService(this, 'EmitProcessingErrorMetric', {
      service: 'cloudwatch',
      action: 'putMetricData',
      parameters: {
        Namespace: 'CrimeReport',
        MetricData: [
          {
            MetricName: 'MediaPipelineProcessingErrors',
            Value: 1,
            Unit: 'Count',
            Dimensions: [{ Name: 'Service', Value: 'media-pipeline' }],
          },
        ],
      },
      iamResources: ['*'],
      iamAction: 'cloudwatch:PutMetricData',
      resultPath: sfn.JsonPath.DISCARD,
    });

    const processingErrorEnd = new sfn.Pass(this, 'ProcessingErrorEnd', {
      result: sfn.Result.fromObject({ status: 'PROCESSING_ERROR' }),
      resultPath: sfn.JsonPath.DISCARD,
    });
    emitProcessingErrorMetric.next(processingErrorEnd);

    const buildProcessingError = (id: string, reasonPath: string) => {
      const pass = new sfn.Pass(this, id, {
        parameters: {
          status: 'PROCESSING_ERROR',
          'reason.$': reasonPath,
        },
        resultPath: '$.processingError',
      });
      pass.next(emitProcessingErrorMetric);
      return pass;
    };

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

    const imageProcessingError = buildProcessingError(
      'ImageProcessingError',
      '$.errorInfo.Cause',
    );
    detectImageLabels.addCatch(imageProcessingError, {
      errors: ['States.ALL'],
      resultPath: '$.errorInfo',
    });

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
      ), deleteFlaggedImage)
      .otherwise(copyToMedia);

    const imagePath = detectImageLabels.next(isImageFlagged);

    // ── Video path ────────────────────────────────────────
    //
    // iPhones (and many Android devices) record H.265 / HEVC by default, which
    // AWS Rekognition does NOT support. To accept any input codec MediaConvert
    // can read, we transcode to H.264 FIRST, then run moderation against the
    // transcoded media-bucket file.
    //
    // 1. Submit MediaConvert job (H.265/H.264/HEVC → H.264 + thumbnail + preview)
    // 2. Poll MediaConvert until COMPLETE / ERROR
    // 3. Run Rekognition StartContentModeration on the transcoded media-bucket key
    // 4. Poll Rekognition until SUCCEEDED / FAILED
    // 5. If flagged: delete transcoded artifacts from media bucket; mark FLAGGED
    //    If clean:   leave transcoded artifacts in media bucket; mark VIDEO_READY
    // ─────────────────────────────────────────────────────

    const submitTranscode = new tasks.LambdaInvoke(this, 'SubmitTranscodeJob', {
      lambdaFunction: this.transcodeLambda,
      payload: sfn.TaskInput.fromObject({
        bucket: sfn.JsonPath.stringAt('$.bucket'),
        key: sfn.JsonPath.stringAt('$.key'),
      }),
      // Lambda returns { jobId, outputPrefix, transcodedKey, thumbnailKey, previewKey }
      resultSelector: {
        'jobId.$': '$.Payload.jobId',
        'outputPrefix.$': '$.Payload.outputPrefix',
        'transcodedKey.$': '$.Payload.transcodedKey',
        'thumbnailKey.$': '$.Payload.thumbnailKey',
        'previewKey.$': '$.Payload.previewKey',
      },
      resultPath: '$.transcode',
    });

    const waitForTranscode = new sfn.Wait(this, 'WaitForTranscode', {
      time: sfn.WaitTime.duration(cdk.Duration.seconds(15)),
    });

    const getTranscodeJob = new tasks.CallAwsService(this, 'GetTranscodeJob', {
      service: 'mediaconvert',
      action: 'getJob',
      parameters: {
        Id: sfn.JsonPath.stringAt('$.transcode.jobId'),
      },
      iamResources: ['*'],
      resultPath: '$.transcodeStatus',
    }).addRetry({
      errors: ['States.TaskFailed'],
      interval: cdk.Duration.seconds(5),
      maxAttempts: 3,
      backoffRate: 2,
    });

    // ── Video moderation (against transcoded H.264 in media bucket) ────
    const startVideoModeration = new tasks.CallAwsService(this, 'StartVideoModeration', {
      service: 'rekognition',
      action: 'startContentModeration',
      parameters: {
        Video: {
          S3Object: {
            Bucket: this.mediaBucket.bucketName,
            Name: sfn.JsonPath.stringAt('$.transcode.transcodedKey'),
          },
        },
      },
      iamResources: ['*'],
      resultPath: '$.videoJob',
    }).addRetry(REKOGNITION_RETRY);

    const videoStartProcessingError = buildProcessingError(
      'VideoStartProcessingError',
      '$.errorInfo.Cause',
    );
    startVideoModeration.addCatch(videoStartProcessingError, {
      errors: ['States.ALL'],
      resultPath: '$.errorInfo',
    });

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

    const videoPollProcessingError = buildProcessingError(
      'VideoPollProcessingError',
      '$.errorInfo.Cause',
    );
    getVideoResults.addCatch(videoPollProcessingError, {
      errors: ['States.ALL'],
      resultPath: '$.errorInfo',
    });

    // Flagged path for video: delete the transcoded artifacts from media bucket
    // (the raw upload in uploads-bucket auto-expires via lifecycle rule).
    const deleteFlaggedVideo = new tasks.CallAwsService(this, 'DeleteFlaggedVideo', {
      service: 's3',
      action: 'deleteObject',
      parameters: {
        Bucket: this.mediaBucket.bucketName,
        Key: sfn.JsonPath.stringAt('$.transcode.transcodedKey'),
      },
      iamResources: [this.mediaBucket.arnForObjects('*')],
      resultPath: sfn.JsonPath.DISCARD,
    }).addRetry(S3_RETRY);

    const videoFlaggedEnd = new sfn.Pass(this, 'VideoFlagged', {
      result: sfn.Result.fromObject({ status: 'FLAGGED' }),
    });
    deleteFlaggedVideo.next(videoFlaggedEnd);

    const videoComplete = new sfn.Pass(this, 'VideoProcessed', {
      result: sfn.Result.fromObject({ status: 'VIDEO_READY' }),
    });

    const isVideoFlagged = new sfn.Choice(this, 'IsVideoFlagged')
      .when(sfn.Condition.and(
        sfn.Condition.isPresent('$.videoResults.ModerationLabels[0]'),
        sfn.Condition.numberGreaterThanEquals('$.videoResults.ModerationLabels[0].Confidence', MODERATION_CONFIDENCE_THRESHOLD),
      ), deleteFlaggedVideo)
      .otherwise(videoComplete);

    // Rekognition reported a system failure (unsupported codec — though this
    // is much less likely now that we transcode first — internal error,
    // etc.). Surface as PROCESSING_ERROR rather than treating as flagged
    // content, and crucially do NOT delete the transcoded artifact so ops
    // can investigate.
    const videoJobProcessingError = buildProcessingError(
      'VideoJobProcessingError',
      '$.videoResults.StatusMessage',
    );

    const checkVideoJobStatus = new sfn.Choice(this, 'CheckVideoJobStatus')
      .when(sfn.Condition.stringEquals('$.videoResults.JobStatus', 'IN_PROGRESS'), waitForModeration)
      .when(sfn.Condition.stringEquals('$.videoResults.JobStatus', 'SUCCEEDED'), isVideoFlagged)
      .otherwise(videoJobProcessingError);

    const videoModerationPath = startVideoModeration
      .next(waitForModeration)
      .next(getVideoResults)
      .next(checkVideoJobStatus);

    // Transcoding system error (CANCELED, ERROR, or any unexpected status).
    // Do NOT mark as flagged content — surface as a processing error and
    // emit the metric. We don't delete here because the input upload
    // auto-expires via the uploads-bucket lifecycle rule.
    const transcodeProcessingError = buildProcessingError(
      'TranscodeProcessingError',
      '$.transcodeStatus.Job.Status',
    );

    // Catch Lambda / MediaConvert API failures during the submit and poll
    // tasks, so a failed Lambda invocation or a GetJob throttle doesn't
    // bubble up as an execution failure that masquerades as content
    // moderation in downstream alerts.
    const transcodeSubmitProcessingError = buildProcessingError(
      'TranscodeSubmitProcessingError',
      '$.errorInfo.Cause',
    );
    submitTranscode.addCatch(transcodeSubmitProcessingError, {
      errors: ['States.ALL'],
      resultPath: '$.errorInfo',
    });

    const transcodePollProcessingError = buildProcessingError(
      'TranscodePollProcessingError',
      '$.errorInfo.Cause',
    );
    getTranscodeJob.addCatch(transcodePollProcessingError, {
      errors: ['States.ALL'],
      resultPath: '$.errorInfo',
    });

    // MediaConvert job-status terminal values: COMPLETE, CANCELED, ERROR.
    // Anything not COMPLETE before moderation is a processing error.
    const checkTranscodeStatus = new sfn.Choice(this, 'CheckTranscodeStatus')
      .when(sfn.Condition.stringEquals('$.transcodeStatus.Job.Status', 'COMPLETE'), videoModerationPath)
      .when(sfn.Condition.or(
        sfn.Condition.stringEquals('$.transcodeStatus.Job.Status', 'SUBMITTED'),
        sfn.Condition.stringEquals('$.transcodeStatus.Job.Status', 'PROGRESSING'),
      ), waitForTranscode)
      .otherwise(transcodeProcessingError);

    const videoPath = submitTranscode
      .next(waitForTranscode)
      .next(getTranscodeJob)
      .next(checkTranscodeStatus);

    // ── Entry: route by file type ────────────────────────
    return new sfn.Choice(this, 'DetermineFileType')
      .when(sfn.Condition.stringMatches('$.key', 'images/*'), imagePath)
      .otherwise(videoPath);
  }
}
