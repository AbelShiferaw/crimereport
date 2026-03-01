# Milestone 16: Media Infrastructure

## Status
Completed

## Goal
Set up S3 for media storage, CloudFront CDN for delivery, and a Step Functions pipeline orchestrating Rekognition content moderation and MediaConvert video transcoding — with separate paths for images and videos.

## Dependencies
- **Milestone 14** complete (IAM roles, VPC)
- AWS CDK CLI, Node.js 20+

## What Was Built

A single **MediaStack** CDK stack containing:

1. **S3 Buckets** — Uploads bucket (CORS, EventBridge notifications, 1-day lifecycle) and a private media bucket for processed content
2. **CloudFront Distribution** — OAC-based CDN serving the media bucket with HTTP/2+3, HTTPS redirect, and `PriceClass_100`
3. **Step Functions State Machine** — Full media processing pipeline:
   - Routes by file type (`images/*` vs `videos/*`)
   - **Image path**: Sync Rekognition `DetectModerationLabels` → S3 copy to media bucket
   - **Video path**: Async Rekognition `StartContentModeration` → polling loop → Lambda for MediaConvert transcoding
   - Flagged content is deleted immediately from the uploads bucket
   - Retry policies with exponential backoff on all Rekognition and S3 calls
4. **EventBridge Rule** — Triggers the state machine on `Object Created` events for `videos/` and `images/` prefixes
5. **Lambda** — MediaConvert job builder (Node.js 20, ARM64) invoked by Step Functions for video transcoding
6. **SQS Dead Letter Queue** — 14-day retention with a CloudWatch alarm on message visibility
7. **MediaConvert IAM Role** — Read from uploads, write to media bucket

## Key Files

| File | Description |
|------|-------------|
| `infrastructure/aws/lib/media/media-stack.ts` | All media infrastructure (S3, CloudFront, Step Functions, EventBridge, Lambda, SQS DLQ, MediaConvert role) |
| `infrastructure/aws/lib/config/constants.ts` | `MODERATION_CONFIDENCE_THRESHOLD` (80), `PROJECT_PREFIX` |
| `backend/functions/transcode-trigger/index.ts` | Lambda: discovers MediaConvert endpoint, builds and submits transcoding job |
| `infrastructure/aws/test/media/media-stack.test.ts` | CDK assertion tests (23 tests) |
| `infrastructure/aws/bin/crimereport-stack.ts` | Stack wiring — MediaStack exports bucket names and CDN domain to ComputeStack |

## Implementation Details

### 1. S3 Buckets

```typescript
// infrastructure/aws/lib/media/media-stack.ts

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
```

Both buckets use S3-managed encryption, block all public access, and enforce SSL. Bucket names include the AWS account ID for global uniqueness.

### 2. CloudFront Distribution

Uses Origin Access Control (OAC) via CDK's `S3BucketOrigin.withOriginAccessControl()`:

```typescript
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
```

### 3. Dead Letter Queue & Alarm

```typescript
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
```

### 4. Step Functions State Machine

The pipeline is built in `buildPipelineDefinition()` with shared retry policies:

```typescript
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
```

**Entry point** — routes by key prefix:

```typescript
return new sfn.Choice(this, 'DetermineFileType')
  .when(sfn.Condition.stringMatches('$.key', 'images/*'), imagePath)
  .otherwise(videoPath);
```

**Image path** (synchronous):

```typescript
// 1. Sync moderation check
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

// 2. Check if flagged (confidence >= 80)
const isImageFlagged = new sfn.Choice(this, 'IsImageFlagged')
  .when(sfn.Condition.and(
    sfn.Condition.isPresent('$.moderation.ModerationLabels[0]'),
    sfn.Condition.numberGreaterThanEquals(
      '$.moderation.ModerationLabels[0].Confidence',
      MODERATION_CONFIDENCE_THRESHOLD,
    ),
  ), deleteFlagged)
  .otherwise(copyToMedia);

// 3. Safe images are copied to media bucket
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
```

**Video path** (asynchronous with polling):

```typescript
// 1. Start async moderation
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

// 2. Wait 20s then poll
const waitForModeration = new sfn.Wait(this, 'WaitForModeration', {
  time: sfn.WaitTime.duration(cdk.Duration.seconds(20)),
});

const getVideoResults = new tasks.CallAwsService(this, 'GetVideoModerationResults', {
  service: 'rekognition',
  action: 'getContentModeration',
  parameters: { JobId: sfn.JsonPath.stringAt('$.videoJob.JobId') },
  iamResources: ['*'],
  resultPath: '$.videoResults',
}).addRetry(REKOGNITION_RETRY);

// 3. Check job status — loop if IN_PROGRESS, check moderation if SUCCEEDED
const checkJobStatus = new sfn.Choice(this, 'CheckVideoJobStatus')
  .when(sfn.Condition.stringEquals('$.videoResults.JobStatus', 'IN_PROGRESS'), waitForModeration)
  .when(sfn.Condition.stringEquals('$.videoResults.JobStatus', 'SUCCEEDED'), isVideoFlagged)
  .otherwise(deleteFlagged);

// 4. Safe videos → Lambda for MediaConvert transcoding
const submitTranscode = new tasks.LambdaInvoke(this, 'SubmitTranscodeJob', {
  lambdaFunction: this.transcodeLambda,
  payload: sfn.TaskInput.fromObject({
    bucket: sfn.JsonPath.stringAt('$.bucket'),
    key: sfn.JsonPath.stringAt('$.key'),
  }),
  resultPath: '$.transcode',
});
```

### 5. EventBridge Rule

```typescript
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
```

### 6. Transcode Lambda

The Lambda discovers the MediaConvert endpoint (cached across invocations), builds job settings, and submits:

```typescript
// backend/functions/transcode-trigger/index.ts

export const handler = async (event: TranscodeInput): Promise<TranscodeOutput> => {
  const { bucket, key } = event;
  const inputUri = `s3://${bucket}/${key}`;
  const baseName = key.split('/').pop()?.replace(/\.[^.]+$/, '') ?? 'output';
  const outputPrefix = `videos/${baseName}`;

  const endpoint = await getEndpoint();
  const client = new MediaConvertClient({ endpoint });
  const jobSettings = buildJobSettings(inputUri, outputPrefix);

  const result = await client.send(
    new CreateJobCommand({
      Role: MEDIACONVERT_ROLE,
      Settings: jobSettings,
      StatusUpdateInterval: 'SECONDS_60',
      Tags: { Project: 'CrimeReport', Source: key },
    }),
  );

  return { jobId: result.Job?.Id ?? 'unknown', outputPrefix };
};
```

MediaConvert job outputs:
- **720p MP4** — H.264 QVBR quality 7, AAC 128kbps audio
- **Thumbnail** — 480×480 single frame capture
- **GIF Preview** — 320×320, 3fps, max 9 frames

## Media Flow
```
Mobile App
    │
    ▼ (presigned URL upload to images/ or videos/)
S3 Uploads Bucket
    │
    ▼ (EventBridge: ObjectCreated, prefix: images/ or videos/)
Step Functions State Machine
    │
    ▼ (DetermineFileType)
    ├──────────────────────────────┐
    │                              │
 images/*                      videos/*
    │                              │
    ▼                              ▼
 Rekognition:                  Rekognition:
 DetectModerationLabels        StartContentModeration (async)
 (sync)                            │
    │                              ▼
    ├── Flagged → Delete       Wait 20s → GetContentModeration
    │                              │
    ▼ (safe)                   ┌─ JobStatus? ─┐
 S3 Copy to                    │              │
 Media Bucket            IN_PROGRESS     SUCCEEDED
    │                  (loop back)          │
    ▼                              ├── Flagged → Delete
 IMAGE_READY                       │
                                   ▼ (safe)
                               Lambda: MediaConvert Job Builder
                                   │
                                   ▼
                               MediaConvert (720p + thumb + GIF)
                                   │
                                   ▼
                               S3 Media Bucket → CloudFront → App
```

## Testing

CDK assertion tests in `infrastructure/aws/test/media/media-stack.test.ts` (23 tests):

**S3 Buckets:**
- Uploads bucket with CORS (PUT, POST) and lifecycle (1-day expiration)
- Uploads bucket has EventBridge notifications enabled
- Media bucket created with encryption
- Uploads bucket does NOT have Lambda notifications (uses EventBridge)

**CloudFront:**
- Distribution with HTTPS redirect, compression, HTTP/2+3, `PriceClass_100`

**SQS DLQ:**
- Dead letter queue with 14-day retention
- CloudWatch alarm on DLQ message visibility

**MediaConvert:**
- IAM role with `mediaconvert.amazonaws.com` trust

**Lambda:**
- Node.js 20, ARM64, 256 MB, 30s timeout
- Has MediaConvert permissions (`CreateJob`, `DescribeEndpoints`)
- Has `MEDIACONVERT_ROLE_ARN` and `OUTPUT_BUCKET` environment variables

**Step Functions:**
- State machine created with X-Ray tracing
- State machine role has Rekognition image moderation permission
- State machine role has Rekognition video moderation permissions (start + get)
- State machine role has S3 read on uploads, write on media, delete, and copy permissions

**EventBridge:**
- Rule matches `Object Created` events with `videos/` and `images/` prefixes
- Rule targets Step Functions with DLQ configured

## Notes

- **Deviation from original plan**: The original plan used Terraform. The actual implementation uses a single CDK stack with all media resources.
- **OAC instead of OAI**: CloudFront uses the newer Origin Access Control (`S3BucketOrigin.withOriginAccessControl`) instead of Origin Access Identity.
- **HTTP/2+3**: CloudFront is configured with `HTTP2_AND_3` for better performance on modern clients.
- **Moderation confidence threshold** is 80% (configurable in `constants.ts`).
- **No S3 event notification to Lambda**: The pipeline uses EventBridge → Step Functions → Lambda, not direct S3→Lambda invocation.
- **State machine timeout** is 30 minutes to accommodate long video moderation jobs.
- **X-Ray tracing** is enabled on the state machine for debugging pipeline executions.
- **Account ID in bucket names** ensures global uniqueness without a random suffix.
