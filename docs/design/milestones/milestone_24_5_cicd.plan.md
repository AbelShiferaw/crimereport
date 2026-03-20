# Milestone 24.5: CI/CD Pipeline

## Status
Completed

## Goal
Automate testing and deployment via GitHub Actions so every PR is validated and every merge to `main` deploys to production automatically. Eliminate manual `cdk deploy` from laptops.

## Dependencies
Requires **Milestones 14-24** complete (all infrastructure and backend features deployed).

## What Was Built

### 1. OIDC CDK Stack (`CrimeReport-Cicd`)
- **File:** `infrastructure/aws/lib/cicd/cicd-stack.ts`
- Creates an IAM OIDC Provider that trusts `token.actions.githubusercontent.com`
- Creates a deploy role (`crimereport-github-deploy`) with `AdministratorAccess`
- The role can only be assumed by the `abelshiferaw/crimereport` GitHub repo
- No long-lived AWS keys stored in GitHub -- credentials are temporary (15 min)
- **Test:** `infrastructure/aws/test/cicd/cicd-stack.test.ts` (4 assertions)

### 2. PR Workflow (`.github/workflows/pr.yml`)
Triggers on every pull request targeting `main`. Runs four jobs:
- **Backend Tests** -- `npm test` in `backend/api/` (136 Jest tests)
- **CDK Tests** -- `npm test` in `infrastructure/aws/` (93 Jest tests)
- **Flutter Checks** -- `flutter analyze` + `flutter test` in `apps/mobile/`
- **CDK Diff** -- Authenticates via OIDC, runs `cdk diff --all`, posts the infrastructure diff as a PR comment

### 3. Deploy Workflow (`.github/workflows/deploy.yml`)
Triggers on push to `main` (i.e., PR merge). Three sequential jobs:
- **Test Gate** -- Runs all three test suites in parallel; must all pass
- **Deploy** -- Authenticates via OIDC, runs `cdk deploy --all --require-approval never`
- **Integration Tests** -- Retrieves ALB DNS from CloudFormation outputs, runs full integration test suite against the live production API

Concurrency group `deploy-production` prevents parallel deploys.

### 4. Integration Test Suite
- **File:** `backend/api/src/__tests__/integration/production.test.ts`
- **Config:** `backend/api/jest.integration.config.ts` (30s timeout, separate from unit tests)
- **Script:** `npm run test:integration` (uses `API_URL` environment variable)
- Tests all 17 API endpoints against the real deployed infrastructure:
  - Health checks (liveness + readiness)
  - Reports CRUD (create, get, list nearby, 404 handling)
  - Input validation (bad body, missing params)
  - Comments (create, list)
  - Upvotes (toggle)
  - Comment flagging
  - Media upload (presigned URL generation, status check)
  - Push notifications (register, preferences, unregister)

## Files Created/Modified

| File | Action |
|------|--------|
| `infrastructure/aws/lib/cicd/cicd-stack.ts` | Created |
| `infrastructure/aws/test/cicd/cicd-stack.test.ts` | Created |
| `infrastructure/aws/bin/crimereport-stack.ts` | Modified (added CicdStack) |
| `infrastructure/aws/lib/config/constants.ts` | Modified (added GITHUB_REPO) |
| `.github/workflows/pr.yml` | Created |
| `.github/workflows/deploy.yml` | Created |
| `backend/api/src/__tests__/integration/production.test.ts` | Created |
| `backend/api/jest.integration.config.ts` | Created |
| `backend/api/package.json` | Modified (added test:integration, excluded integration from default test) |
| `docs/knowledge/cicd-pipeline.md` | Created (knowledge base) |
| `docs/knowledge/diagrams/cicd_pipeline.py` | Created (3 architecture diagrams) |

## Bootstrap Steps (One-Time)
1. Deploy the OIDC stack: `cd infrastructure/aws && npx cdk deploy CrimeReport-Cicd`
2. Set GitHub repo variables (Settings > Secrets and variables > Actions > Variables):
   - `AWS_ACCOUNT_ID` -- your AWS account number
   - `AWS_REGION` -- `us-east-1`

## Key Design Decisions
- **OIDC over stored keys** -- No long-lived AWS credentials; temp creds auto-expire
- **AdministratorAccess** -- Simplest for solo project; scope down for team use
- **Separate Jest config for integration tests** -- `npm test` only runs unit tests; `npm run test:integration` runs against live API
- **CDK diff as PR comment** -- Reviewers see infrastructure changes alongside code changes
- **Concurrency group** -- Prevents conflicting CloudFormation updates from parallel merges

## Notes
- The integration test for push notification registration may fail if the SNS platform application rejects the fake FCM token. This is expected -- SNS validates tokens on endpoint creation. The test verifies the API route works; actual push delivery is tested manually.
- Flutter checks may need the Flutter version updated in workflows if the project upgrades Flutter.
