# Scaling Considerations

Future upgrades to consider if the app grows significantly in users and traffic. These are not needed at MVP/startup scale but are documented here so they aren't lost.

---

## 1. Push Notification Fan-Out

**Current approach:** When a report becomes active, the Fargate task queries `push_subscriptions` (PostGIS spatial query) and calls `SNS.Publish()` individually for each nearby device using `Promise.allSettled`.

**When it breaks:** In a dense area (e.g., downtown Manhattan) with 5,000+ nearby subscribers, the Fargate task makes thousands of concurrent HTTP calls to the SNS API. This ties up CPU, memory, and network connections even though it's fire-and-forget.

**Upgrade path:** Offload to SQS + Lambda.

```
Current:  Fargate → query Aurora → loop SNS.Publish(each device)
Future:   Fargate → SQS (one message with report data)
                      → Lambda picks up message
                      → queries Aurora
                      → batched SNS.Publish with concurrency control
```

Benefits:
- Fargate task stays fast and lightweight
- Lambda scales independently (can run multiple workers concurrently)
- Failed notifications stay in the queue for retry (dead letter queue for permanent failures)
- Can add batching (SNS supports batch publish of up to 10 messages per call)

No changes needed to the database schema, SNS client, or Flutter app -- only where the fan-out code runs.

---

## 2. WebSocket Geo-Grid Scaling

**Current approach:** 0.1-degree grid cells (~11km) with 3x3 overlap for broadcasts. Redis adapter synchronizes across ECS tasks.

**When it breaks:** Extremely high connection counts (100K+ concurrent WebSocket connections) could strain Redis pub/sub throughput and individual task memory.

**Upgrade path:**
- Increase ECS task count (horizontal scaling -- already supported via auto-scaling)
- Consider Redis Cluster mode instead of single-node replication group
- Evaluate adaptive grid sizing (smaller cells in dense urban areas, larger in rural)
- Add connection pooling or a dedicated WebSocket tier separate from the REST API

---

## 3. Database Read Scaling

**Current approach:** Aurora Serverless v2 PostgreSQL handles all reads and writes. PostGIS spatial queries use GIST indexes.

**When it breaks:** High read traffic (millions of `findNearby` queries/day) could saturate the writer instance.

**Upgrade path:**
- Add Aurora read replicas and route read queries (findNearby, comments, media status) to them
- Add Redis caching for hot data (trending reports, frequently accessed report details)
- Consider materialized views for the feed (pre-computed nearby reports per grid cell)

---

## 4. Media Pipeline Throughput

**Current approach:** Step Functions orchestrates Rekognition + MediaConvert per upload. Each upload triggers its own state machine execution.

**When it breaks:** MediaConvert has per-account concurrency limits. Thousands of simultaneous uploads could queue up.

**Upgrade path:**
- Request MediaConvert reserved queue (guaranteed throughput)
- Add an SQS buffer before Step Functions to throttle concurrent executions
- Pre-process thumbnails at the edge (Lambda@Edge on CloudFront) to reduce MediaConvert load

---

## 5. Rate Limiting Sophistication

**Current approach:** Three layers -- AWS WAF (2000 req/5min per IP), `express-rate-limit` (100 req/min global, 20 req/min writes per IP), device-based daily limits in Aurora.

**When it breaks:** Sophisticated attackers can rotate IPs. In-memory rate limiting (`express-rate-limit`) doesn't share state across ECS tasks.

**Upgrade path:**
- Move rate limiting state to Redis (shared across all tasks) using `rate-limit-redis` store
- Add device fingerprinting beyond simple device ID
- Implement sliding window rate limiting instead of fixed windows
- Add CAPTCHA challenges for suspicious patterns (reCAPTCHA v3 is already in the architecture diagram)

---

## 6. Search and Discovery

**Current approach:** PostGIS `ST_DWithin` for nearby reports. No full-text search.

**When it breaks:** Users may want to search by description, type, or date range across a large dataset.

**Upgrade path:**
- Add Amazon OpenSearch (Elasticsearch) for full-text search and complex filtering
- Sync reports to OpenSearch via DynamoDB Streams or a Change Data Capture pattern
- Use OpenSearch for the feed query (faster aggregations, better relevance ranking)

---

## 7. Multi-Region Deployment

**Current approach:** Single region (us-east-1).

**When it breaks:** Users in other geographic regions experience high latency. Single region is a single point of failure.

**Upgrade path:**
- Deploy to additional regions (us-west-2, eu-west-1)
- Use Aurora Global Database for cross-region replication
- Route users to nearest region via Route 53 latency-based routing
- CloudFront already serves media globally (no change needed)

---

## 8. Analytics and Metrics

**Current approach:** CloudWatch alarms for infrastructure metrics (CPU, memory, DB connections). Application logs via Pino → CloudWatch Logs.

**When it breaks:** Lack of business-level metrics (reports per hour, notification delivery rate, user engagement).

**Upgrade path:**
- Emit custom CloudWatch metrics using Embedded Metric Format (EMF) -- already noted in Milestone 30
- Add a data pipeline (Kinesis Firehose → S3 → Athena) for analytics queries
- Consider a lightweight dashboard (CloudWatch Dashboard or Grafana)

---

## Priority Order

If the app starts growing, tackle these roughly in this order:

1. **Push notification fan-out** (SQS + Lambda) -- most likely first bottleneck
2. **Rate limiting to Redis** -- critical for multi-task consistency
3. **Database read replicas** -- relieves the most common query pressure
4. **Analytics/metrics** -- need visibility before optimizing further
5. **WebSocket scaling** -- usually fine until very high concurrency
6. **Media pipeline throughput** -- only if upload volume is high
7. **Search** -- feature request driven, not a scaling concern
8. **Multi-region** -- only needed for geographic expansion or HA requirements
