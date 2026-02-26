# Milestone 16: Media Infrastructure

## Goal
Set up S3 for media storage, CloudFront CDN for delivery, and MediaConvert for video processing.

## Dependencies
Requires **Milestone 14** complete (IAM roles).

## Implementation

### 1. S3 Buckets
```hcl
# infrastructure/storage.tf

# Raw uploads bucket
resource "aws_s3_bucket" "uploads" {
  bucket = "reportcrime-uploads-${var.environment}"
}

resource "aws_s3_bucket_cors_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST"]
    allowed_origins = ["*"]  # Restrict in production
    max_age_seconds = 3600
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id
  
  rule {
    id     = "delete-old-uploads"
    status = "Enabled"
    
    expiration {
      days = 1  # Delete after processing
    }
  }
}

# Processed media bucket (public via CloudFront)
resource "aws_s3_bucket" "media" {
  bucket = "reportcrime-media-${var.environment}"
}

resource "aws_s3_bucket_public_access_block" "media" {
  bucket = aws_s3_bucket.media.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

### 2. CloudFront Distribution
```hcl
# infrastructure/cdn.tf

resource "aws_cloudfront_origin_access_identity" "media" {
  comment = "ReportCrime media OAI"
}

resource "aws_s3_bucket_policy" "media" {
  bucket = aws_s3_bucket.media.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = {
        AWS = aws_cloudfront_origin_access_identity.media.iam_arn
      }
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.media.arn}/*"
    }]
  })
}

resource "aws_cloudfront_distribution" "media" {
  enabled         = true
  is_ipv6_enabled = true
  price_class     = "PriceClass_100"  # US, Canada, Europe
  
  origin {
    domain_name = aws_s3_bucket.media.bucket_regional_domain_name
    origin_id   = "S3-media"
    
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.media.cloudfront_access_identity_path
    }
  }
  
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-media"
    
    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
    
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400    # 1 day
    max_ttl                = 31536000 # 1 year
    compress               = true
  }
  
  restrictions {
    geo_restriction { restriction_type = "none" }
  }
  
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

output "cdn_domain" {
  value = aws_cloudfront_distribution.media.domain_name
}
```

### 3. MediaConvert Setup
```hcl
# infrastructure/mediaconvert.tf

# MediaConvert IAM Role
resource "aws_iam_role" "mediaconvert" {
  name = "reportcrime-mediaconvert"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "mediaconvert.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "mediaconvert" {
  name = "mediaconvert-s3-access"
  role = aws_iam_role.mediaconvert.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.uploads.arn}/*"
      },
      {
        Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.media.arn}/*"
      }
    ]
  })
}

# MediaConvert Job Template
resource "aws_media_convert_queue" "main" {
  name = "reportcrime-transcode"
}
```

### 4. Step Functions Media Processing Pipeline

The media pipeline uses Step Functions to orchestrate content moderation and transcoding with separate paths for images and videos:

1. **EventBridge Rule** - Catches S3 `ObjectCreated` events from the uploads bucket (prefixes `videos/` and `images/`) and triggers the state machine
2. **File Type Routing** - `Choice` state routes by key prefix: `images/*` or `videos/*`
3. **Image Path (sync)** - Rekognition `DetectModerationLabels` runs synchronously. Safe images are copied directly to the media bucket via S3 `copyObject`. No transcoding needed.
4. **Video Path (async)** - Rekognition `StartContentModeration` starts async analysis. A polling loop (`Wait 20s` → `GetContentModeration` → check `JobStatus`) waits for completion. Safe videos go to Lambda for MediaConvert transcoding.
5. **Flagged Content** - Both paths delete flagged content from S3 immediately.
6. **Retries** - All Rekognition and S3 task states have retry policies with exponential backoff.
7. **Error Handling** - Failed executions route to an SQS dead letter queue.

The CDK code in `infrastructure/aws/lib/media/media-stack.ts` defines the state machine, EventBridge rule, and all IAM permissions. The Lambda code lives in `backend/functions/transcode-trigger/index.ts`.

### 5. Lambda MediaConvert Job Builder

The Lambda is no longer the orchestrator - it's a single step invoked by Step Functions. It receives `{ bucket, key }` as input, discovers the MediaConvert endpoint, builds the job settings (720p MP4, thumbnail, GIF), and submits the job via `CreateJob`.

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

## Deliverable Checklist
- [ ] Uploads bucket created with CORS and EventBridge notifications
- [ ] Media bucket created (private)
- [ ] CloudFront distribution serving media bucket
- [ ] MediaConvert role created
- [ ] Step Functions state machine deployed with image/video routing, Rekognition, retries
- [ ] EventBridge rule triggers state machine on S3 upload (images/ and videos/ prefixes)
- [ ] Lambda for MediaConvert job building deployed (videos only)
- [ ] SQS dead letter queue for failed executions
- [ ] Test: upload image → sync Rekognition check → S3 copy to media bucket
- [ ] Test: upload video → async Rekognition check → MediaConvert transcode
- [ ] Test: flagged content deleted, never reaches media bucket
- [ ] Test: CDN serves processed media

## Files
1. `infrastructure/aws/lib/media/media-stack.ts` - S3 buckets, CloudFront, Step Functions, EventBridge, Lambda, DLQ
2. `infrastructure/aws/test/media/media-stack.test.ts` - Unit tests
3. `backend/functions/transcode-trigger/index.ts` - MediaConvert job builder Lambda code
