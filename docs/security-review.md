# Security Review Checklist

Last reviewed: 2026-03-28

## Backend API Security

- [x] Helmet middleware active (`backend/api/src/app.ts`)
- [x] CORS origin configurable (`config.corsOrigin`)
- [x] Rate limiting: 10 reports/day per device, 50 comments/day
- [x] Device flagging prevents abuse (checks `device.flagged`)
- [x] Zod validation on all request inputs (validate middleware)
- [x] Parameterized SQL queries (pg pool, no string interpolation)
- [x] S3 presigned URL expiration configured
- [x] DB credentials in Secrets Manager (ECS secret injection)
- [x] No secrets in source code or environment variables

## Infrastructure Security

- [x] ECS tasks in private subnets (AssignPublicIp: DISABLED)
- [x] DB/Redis security groups: ECS-only ingress
- [x] ALB security group: port 80/443 only
- [x] ECR image scanning on push (imageScanOnPush: true)
- [x] WAF rate limiting (2000 req/5min per IP)
- [x] WAF managed rules (AWS common, SQL injection)
- [x] S3 bucket public access blocked
- [ ] HTTPS listener on ALB (requires ACM certificate — pending)
- [ ] CloudWatch logs encryption at rest (default encryption)

## Content Security

- [x] Rekognition content moderation in media pipeline
- [x] Community flagging (auto-hide after threshold)
- [x] Device-based rate limiting

## Data Privacy

- [x] No PII collected (no email, phone, name)
- [x] Device ID hashed before storage
- [x] Media EXIF stripped on device (Flutter side)
- [x] Location rounded to ~100m precision
