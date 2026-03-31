# Parallel Task Plan — Remaining Milestones

## Current State Summary

Based on code audit (March 31, 2026):

| Milestone | Status | Evidence |
|-----------|--------|----------|
| 1–23 | **Complete** | All code + tests in repo |
| 24 (Push Backend) | **Complete** | routes/notifications.ts, models, SNS lib, migration, CDK SNS stack |
| 24.5 (CI/CD) | **Complete** | PR #3 merged, `.github/workflows/` present |
| 25 (Flutter REST) | **Complete** | PR #8 merged — ApiClient, repositories, provider rewrites |
| 26 (Flutter WebSocket) | **Complete** | PR #8 merged — WebSocketService, events, lifecycle, realtime providers |
| 27 (Media Upload) | **Complete** | PR #9 merged — UploadService, UploadNotifier, overlay |
| 28 (Push Integration) | **Complete** | PR #9 merged — FCM service, notification providers, deep links |
| 29 (Testing) | **Partial** | Backend test extensions merged (PR #6), k6 load test added; Flutter widget/integration tests and staging tests still needed |
| 30 (Launch Prep) | **Partial** | Privacy policy, ToS, security review, CDK production constants, SNS alarms done (PR #7); Splash, onboarding, HTTPS/Route53, EMF metrics, app store assets still needed |
| 31 (App Store) | **Not Started** | Requires physical devices and store accounts — not automatable by cloud agents |

---

## Parallelizable Tasks

Each task below is **independent** and can be assigned to a separate cloud agent on its own branch. Tasks are grouped by area and ordered by priority within each group.

### Task 1: Backend — Extend Test Coverage (Milestone 29)

**Branch:** `feat/m29-backend-test-coverage`
**Base:** `main`
**Complexity:** Moderate — ~6 files to create/modify, all within `backend/api/src/__tests__/`

**Scope:**
- Extend model tests with edge cases: `findNearby` with zero results, boundary radius, PostGIS parameter ordering, `GREATEST(... - 1, 0)` floor guards
- Extend `push-subscription.test.ts` with additional edge cases (disabled devices, token refresh scenarios)
- Add validator edge-case tests for all Zod schemas (malformed input, boundary values, type coercion)
- Improve `websocket.test.ts` coverage (room subscription/unsubscription, disconnection cleanup, concurrent connections)
- Target: get `npm run test:coverage` above 90% for models, 85% for routes

**Files to touch:**
- `backend/api/src/__tests__/models/report.test.ts` — extend
- `backend/api/src/__tests__/models/push-subscription.test.ts` — extend
- `backend/api/src/__tests__/models/comment.test.ts` — extend
- `backend/api/src/__tests__/routes/notifications.test.ts` — extend
- `backend/api/src/__tests__/routes/websocket.test.ts` — extend
- `backend/api/src/__tests__/validators/` — create if missing, or extend

**Testing:** `cd backend/api && npm test` — all 136+ tests must pass, plus new tests

**No dependencies on other tasks.**

---

### Task 2: CDK Infrastructure — HTTPS, DNS, Production Hardening (Milestone 30)

**Branch:** `feat/m30-https-production-hardening`
**Base:** `main`
**Complexity:** Moderate — touches 3-4 CDK stack files + constants

**Scope:**
- Add HTTPS listener to ALB in `compute-stack.ts` (ACM certificate parameter, 443 listener, HTTP→HTTPS redirect)
- Add Route 53 hosted zone and alias record constructs for `api.reportcrime.app` and `cdn.reportcrime.app`
- Review and update production scaling values in `lib/config/constants.ts` (ECS min=2, max=10, Aurora ACU range)
- Enable S3 bucket versioning on uploads and media buckets in `media-stack.ts`
- Verify `dbSecret` rotation configuration in `database-stack.ts`
- Add CDK tests for the new HTTPS listener and Route 53 resources

**Files to touch:**
- `infrastructure/aws/lib/compute/compute-stack.ts` — HTTPS listener, redirect
- `infrastructure/aws/lib/config/constants.ts` — production scaling values
- `infrastructure/aws/lib/media/media-stack.ts` — S3 versioning
- `infrastructure/aws/lib/network/dns-stack.ts` — new (Route 53)
- `infrastructure/aws/bin/crimereport-stack.ts` — wire DNS stack
- `infrastructure/aws/test/compute/compute-stack.test.ts` — extend
- `infrastructure/aws/test/network/dns-stack.test.ts` — new

**Testing:** `cd infrastructure/aws && npm test` — all 93+ tests must pass, plus new tests

**No dependencies on other tasks.**

---

### Task 3: CDK Infrastructure — Custom Application Metrics (Milestone 30)

**Branch:** `feat/m30-emf-custom-metrics`
**Base:** `main`
**Complexity:** Moderate — backend lib + CDK monitoring stack changes

**Scope:**
- Add `aws-embedded-metrics` npm dependency to `backend/api`
- Create `backend/api/src/lib/metrics.ts` — helper wrapping EMF for custom metrics (ReportsCreated, MediaUploadsCompleted, MediaFailureRate, MediaProcessingLatency, WebSocketConnections, RateLimitHits)
- Instrument key route handlers: `routes/reports.ts` (report creation), `routes/notifications.ts`, `lib/socket.ts` (connection gauge)
- Add custom metrics dashboard row in `monitoring-stack.ts`
- Add CloudWatch alarms on `MediaFailureRate` threshold
- Add unit tests for the metrics helper (mock `aws-embedded-metrics`)

**Files to touch:**
- `backend/api/package.json` — add `aws-embedded-metrics`
- `backend/api/src/lib/metrics.ts` — new
- `backend/api/src/routes/reports.ts` — instrument
- `backend/api/src/lib/socket.ts` — instrument
- `backend/api/src/__tests__/lib/metrics.test.ts` — new
- `infrastructure/aws/lib/monitoring/monitoring-stack.ts` — custom metric dashboard + alarms
- `infrastructure/aws/test/monitoring/monitoring-stack.test.ts` — extend

**Testing:** `cd backend/api && npm test` and `cd infrastructure/aws && npm test`

**No dependencies on other tasks.** (Backend changes are additive instrumentation only.)

---

### Task 4: Flutter — Splash Screen & Onboarding Flow (Milestone 30)

**Branch:** `feat/m30-splash-onboarding`
**Base:** `main`
**Complexity:** Moderate — 3-4 new Dart files + modify `app.dart`

**Scope:**
- Create `apps/mobile/lib/features/splash/presentation/splash_screen.dart` — animated logo fade-in, API health check, navigate to onboarding or AppShell
- Create `apps/mobile/lib/features/onboarding/presentation/onboarding_screen.dart` — 3-page flow (anonymous reporting, feed/map preview, permissions), store completion flag in SharedPreferences
- Create `apps/mobile/lib/core/config/environment.dart` — environment enum (dev/staging/prod) with corresponding API/WS URLs via `String.fromEnvironment`
- Update `apps/mobile/lib/app.dart` to route through splash → onboarding → AppShell
- Add unit tests for onboarding completion state logic

**Files to touch:**
- `apps/mobile/lib/features/splash/presentation/splash_screen.dart` — new
- `apps/mobile/lib/features/onboarding/presentation/onboarding_screen.dart` — new
- `apps/mobile/lib/core/config/environment.dart` — new
- `apps/mobile/lib/app.dart` — modify
- `apps/mobile/test/features/splash/` — new tests
- `apps/mobile/test/features/onboarding/` — new tests

**Testing:** Write tests; Flutter analyze must pass. Cannot run Flutter tests in cloud VM (no emulator), but verify code compiles with `flutter analyze` if Flutter SDK is available.

**No dependencies on other tasks.**

---

### Task 5: Flutter — Widget Tests (Milestone 29)

**Branch:** `feat/m29-flutter-widget-tests`
**Base:** `main`
**Complexity:** Moderate — ~6 new test files

**Scope:**
- Create `test/features/feed/presentation/widgets/feed_video_item_test.dart` — verify report info renders, tap interactions
- Create `test/features/feed/presentation/widgets/comments_sheet_test.dart` — verify comment list, submit flow
- Create `test/features/submit/presentation/submit_screen_test.dart` — verify form validation
- Create `test/shared/widgets/floating_nav_bar_test.dart` — verify tab switching
- Create `test/shared/widgets/api_error_handler_test.dart` — verify error messages
- Create `test/shared/data/api/api_client_test.dart` — verify interceptor, rate limit exception

**Files to touch:**
- All under `apps/mobile/test/` — new test files only

**Testing:** Write tests. Cannot run Flutter test suite in cloud VM unless Flutter SDK available.

**No dependencies on other tasks.**

---

### Task 6: CDK — Extend Infrastructure Test Coverage (Milestone 29)

**Branch:** `feat/m29-cdk-test-coverage`
**Base:** `main`
**Complexity:** Light-moderate — 2-3 test files to create/extend

**Scope:**
- Add `test/notifications/sns-stack.test.ts` — test SNS stack SSM parameter usage
- Extend `test/media/media-stack.test.ts` — Step Functions state machine assertions, S3 lifecycle, CloudFront distribution config
- Add full-synthesis smoke test (`test/synthesis.test.ts`) — instantiate all stacks from `bin/crimereport-stack.ts`, verify `app.synth()` succeeds
- Validate WAF rule priorities and rate-limit thresholds in `test/network/waf-stack.test.ts`

**Files to touch:**
- `infrastructure/aws/test/notifications/sns-stack.test.ts` — new
- `infrastructure/aws/test/media/media-stack.test.ts` — extend
- `infrastructure/aws/test/synthesis.test.ts` — new
- `infrastructure/aws/test/network/waf-stack.test.ts` — extend

**Testing:** `cd infrastructure/aws && npm test` — all tests must pass

**No dependencies on other tasks.**

---

### Task 7: Backend — Staging Integration Test Suite (Milestone 29)

**Branch:** `feat/m29-staging-integration-tests`
**Base:** `main`
**Complexity:** Light — new test file + script additions

**Scope:**
- Create `integration-tests/src/staging.test.ts` — health check, DB/Redis readiness, reports CRUD, nearby query, comments, notifications endpoints, media upload flow (or adapt existing `production.test.ts` patterns)
- Add `test:staging` script to `integration-tests/package.json` with `STAGING_URL` env var
- Ensure the tests can run against any `API_URL` (local or deployed)
- Add CloudWatch Log Insights saved query examples to `docs/knowledge/` for debugging

**Files to touch:**
- `integration-tests/src/staging.test.ts` — new
- `integration-tests/package.json` — add script
- `docs/knowledge/cloudwatch-queries.md` — new (optional)

**Testing:** Tests are designed to run against a deployed API; can validate structure with `npm test -- --listTests`

**No dependencies on other tasks.**

---

### Task 8: Documentation & Milestone Status Updates

**Branch:** `feat/docs-milestone-status-updates`
**Base:** `main`
**Complexity:** Light — markdown file updates only

**Scope:**
- Update `Status` field in all milestone `.plan.md` files (24-28 → "Completed", 29-30 → "In Progress")
- Update `README.md` development progress table to accurately reflect current state
- Update `apps/mobile/README.md` current status section
- Update `backend/api/README.md` if any new endpoints or changes not reflected
- Add a `CONTRIBUTING.md` with branch naming conventions and PR workflow
- Add `.github/PULL_REQUEST_TEMPLATE.md` with checklist for PRs

**Files to touch:**
- `docs/design/milestones/milestone_24_push_notifications.plan.md` — update status
- `docs/design/milestones/milestone_25_flutter_rest.plan.md` — update status
- `docs/design/milestones/milestone_26_flutter_websocket.plan.md` — update status
- `docs/design/milestones/milestone_27_media_integration.plan.md` — update status
- `docs/design/milestones/milestone_28_push_integration.plan.md` — update status
- `docs/design/milestones/milestone_29_testing.plan.md` — update status
- `docs/design/milestones/milestone_30_launch_prep.plan.md` — update status
- `README.md` — update progress table
- `apps/mobile/README.md` — update
- `CONTRIBUTING.md` — new
- `.github/PULL_REQUEST_TEMPLATE.md` — new

**Testing:** N/A (docs only)

**No dependencies on other tasks.**

---

### Task 9: Backend/Flutter — Push Notification Contract Alignment

**Branch:** `feat/push-notification-contract-fix`
**Base:** `main`
**Complexity:** Light — 2-3 files

**Scope:**
The Flutter push registration code (`notification_providers.dart`) sends a payload that may not match the backend's Zod schema exactly (e.g., `radius_km` vs `radius`, nullable lat/lng, device_id in body vs header). Audit and align:
- Compare backend `registerDeviceSchema` (validators/push-subscription.ts) with Flutter's `_registerToken` POST body
- Fix any field name mismatches (the backend expects `lat`/`lng` as required numbers, `platform` as enum)
- Ensure the Flutter unregister call sends `device_id` in the body as the backend expects
- Add/extend tests on both sides to validate the contract

**Files to touch:**
- `apps/mobile/lib/shared/providers/notification_providers.dart` — fix registration payload
- `apps/mobile/lib/features/settings/providers/settings_providers.dart` — fix unregister/preferences payloads
- `backend/api/src/__tests__/routes/notifications.test.ts` — add contract validation tests

**Testing:** `cd backend/api && npm test`

**No dependencies on other tasks.**

---

### Task 10: CI/CD — Enhance PR Workflow (Milestone 24.5 extension)

**Branch:** `feat/cicd-enhance-pr-workflow`
**Base:** `main`
**Complexity:** Light — 1-2 workflow files

**Scope:**
- Add test coverage reporting to PR workflow (Jest `--coverage` with `jest-coverage-report` or similar GitHub Action)
- Add a build-and-test step for `integration-tests/` package in PR workflow
- Ensure the deploy workflow runs integration tests after CDK deploy
- Add branch protection rule documentation

**Files to touch:**
- `.github/workflows/pr.yml` — extend
- `.github/workflows/deploy.yml` — extend
- `docs/knowledge/ci-cd.md` — update if exists

**Testing:** Validate YAML syntax; actual workflow testing happens on PR creation

**No dependencies on other tasks.**

---

## Dependency Graph

```
Tasks with NO dependencies (fully parallel):
  Task 1  (Backend test coverage)
  Task 2  (HTTPS/DNS CDK)
  Task 3  (EMF custom metrics)
  Task 4  (Splash/Onboarding Flutter)
  Task 5  (Flutter widget tests)
  Task 6  (CDK test coverage)
  Task 7  (Staging integration tests)
  Task 8  (Documentation updates)
  Task 9  (Push notification contract fix)
  Task 10 (CI/CD enhancements)

All 10 tasks are independent and can run in parallel.
```

---

## Recommended Parallelization Strategy

**Wave 1 (highest priority — ship first):**
| Task | Agent Branch | Why |
|------|-------------|-----|
| Task 2 | `feat/m30-https-production-hardening` | Blocks production readiness |
| Task 3 | `feat/m30-emf-custom-metrics` | Observability needed for launch |
| Task 9 | `feat/push-notification-contract-fix` | Correctness bug — push won't work until aligned |
| Task 1 | `feat/m29-backend-test-coverage` | Test quality gate for launch |

**Wave 2 (important — ship next):**
| Task | Agent Branch | Why |
|------|-------------|-----|
| Task 4 | `feat/m30-splash-onboarding` | User-facing polish for launch |
| Task 6 | `feat/m29-cdk-test-coverage` | Infra test quality gate |
| Task 7 | `feat/m29-staging-integration-tests` | Validates deployed environment |
| Task 8 | `feat/docs-milestone-status-updates` | Housekeeping, low risk |

**Wave 3 (nice-to-have — can ship last):**
| Task | Agent Branch | Why |
|------|-------------|-----|
| Task 5 | `feat/m29-flutter-widget-tests` | Tests require Flutter SDK |
| Task 10 | `feat/cicd-enhance-pr-workflow` | DX improvement, not blocking |

---

## Cloud Agent Prompt Templates

Below are ready-to-use prompts for spinning up each agent session.

### Task 1 Prompt
> Extend backend API test coverage in `backend/api/src/__tests__/`. Add edge-case tests for all models (report findNearby zero results, boundary radius, PostGIS param ordering, floor guards in decrement functions), push-subscription model (disabled devices, token refresh), all Zod validators (malformed input, boundary values), and WebSocket route tests (room sub/unsub, disconnect cleanup, concurrent connections). Run `npm test` to verify all tests pass. Target 90%+ model coverage and 85%+ route coverage. Work on branch `feat/m29-backend-test-coverage` based on `main`.

### Task 2 Prompt
> Add HTTPS/TLS support and DNS configuration to the CDK infrastructure. In `infrastructure/aws/lib/compute/compute-stack.ts`, add an HTTPS listener on port 443 with ACM certificate (parameterized ARN), and redirect HTTP to HTTPS. Create a new `dns-stack.ts` for Route 53 hosted zone and alias records for `api.reportcrime.app` and `cdn.reportcrime.app`. Update production scaling constants in `lib/config/constants.ts` (ECS min=2). Enable S3 versioning in `media-stack.ts`. Add CDK tests for all changes. Run `npm test` from `infrastructure/aws`. Work on branch `feat/m30-https-production-hardening` based on `main`.

### Task 3 Prompt
> Add custom application-level CloudWatch metrics using AWS Embedded Metric Format (EMF). Install `aws-embedded-metrics` in `backend/api`. Create `backend/api/src/lib/metrics.ts` as a helper. Instrument `routes/reports.ts` (ReportsCreated counter by crime type), `lib/socket.ts` (WebSocketConnections gauge), and rate-limit middleware (RateLimitHits). Add a custom metrics dashboard row and MediaFailureRate alarm in `infrastructure/aws/lib/monitoring/monitoring-stack.ts`. Write unit tests mocking EMF. Run backend and CDK tests. Work on branch `feat/m30-emf-custom-metrics` based on `main`.

### Task 4 Prompt
> Implement splash screen and onboarding flow for the Flutter app. Create `apps/mobile/lib/features/splash/presentation/splash_screen.dart` with animated logo, API health check, and routing to onboarding (first launch) or AppShell (returning user). Create `apps/mobile/lib/features/onboarding/presentation/onboarding_screen.dart` with 3 pages (anonymous reporting, feed/map preview, permissions request). Create `apps/mobile/lib/core/config/environment.dart` for dev/staging/prod environment switching via `String.fromEnvironment`. Update `app.dart` to route through splash. Add tests. Work on branch `feat/m30-splash-onboarding` based on `main`.

### Task 5 Prompt
> Create Flutter widget tests for Milestone 29 testing coverage. Add test files: `test/features/feed/presentation/widgets/feed_video_item_test.dart`, `test/features/feed/presentation/widgets/comments_sheet_test.dart`, `test/features/submit/presentation/submit_screen_test.dart`, `test/shared/widgets/floating_nav_bar_test.dart`, `test/shared/widgets/api_error_handler_test.dart`, `test/shared/data/api/api_client_test.dart`. Follow existing test patterns in the repo. Work on branch `feat/m29-flutter-widget-tests` based on `main`.

### Task 6 Prompt
> Extend CDK infrastructure test coverage. Create `infrastructure/aws/test/notifications/sns-stack.test.ts` for the SNS stack. Extend `test/media/media-stack.test.ts` with Step Functions, S3 lifecycle, CloudFront assertions. Create `test/synthesis.test.ts` that instantiates all stacks and runs `app.synth()`. Extend `test/network/waf-stack.test.ts` with rule priority and rate-limit threshold assertions. Run `npm test` from `infrastructure/aws` to verify all tests pass. Work on branch `feat/m29-cdk-test-coverage` based on `main`.

### Task 7 Prompt
> Create a staging integration test suite. Add `integration-tests/src/staging.test.ts` with comprehensive API smoke tests: health, readiness, reports CRUD, nearby query with PostGIS, comments CRUD, notification register/unregister, media upload presigned URL flow. Add a `test:staging` script to `integration-tests/package.json`. Ensure tests work with any `API_URL` env var. Add `docs/knowledge/cloudwatch-queries.md` with useful Log Insights queries. Work on branch `feat/m29-staging-integration-tests` based on `main`.

### Task 8 Prompt
> Update all project documentation to match current implementation state. Update `Status` in milestone plan files: milestones 24-28 to "Completed", 29-30 to "In Progress". Update `README.md` development progress table. Update `apps/mobile/README.md` current status section. Create `CONTRIBUTING.md` with branch naming conventions and PR workflow. Create `.github/PULL_REQUEST_TEMPLATE.md` with a review checklist. Work on branch `feat/docs-milestone-status-updates` based on `main`.

### Task 9 Prompt
> Fix push notification API contract alignment between Flutter and backend. The backend `registerDeviceSchema` (in `backend/api/src/validators/push-subscription.ts`) requires `device_id`, `fcm_token`, `platform`, `lat` (number), `lng` (number) in the body. The Flutter `_registerToken` in `apps/mobile/lib/shared/providers/notification_providers.dart` sends `radius_km` (not in schema), nullable lat/lng, and may not include `device_id` in body. Audit both sides, fix the Flutter code to match the backend contract exactly. Also fix the settings sync functions in `settings_providers.dart`. Add tests on both sides. Work on branch `feat/push-notification-contract-fix` based on `main`.

### Task 10 Prompt
> Enhance the CI/CD PR workflow. Add Jest coverage reporting to `.github/workflows/pr.yml` using `--coverage` flag and a coverage comment action. Add build and lint steps for `integration-tests/` package. Ensure `deploy.yml` runs integration tests with the ALB DNS as `API_URL` after CDK deploy. Work on branch `feat/cicd-enhance-pr-workflow` based on `main`.

---

## What Cloud Agents CANNOT Do (Milestone 31)

Milestone 31 (App Store Submission) requires:
- Physical iOS/Android devices for testing
- Apple Developer account access
- Google Play Console access
- Xcode for archiving and uploading
- Signing certificates and provisioning profiles
- Firebase Console for `google-services.json` / `GoogleService-Info.plist`

These are human-only tasks and cannot be automated by cloud agents.
