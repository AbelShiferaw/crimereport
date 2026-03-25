# AGENTS.md

## Cursor Cloud specific instructions

### Overview

CrImEreport is an anonymous crime reporting platform with three Node.js packages and a Flutter mobile app. For cloud agent development, the **backend API** and **infrastructure CDK** are the primary targets (Flutter requires a physical device/emulator and is not runnable in this environment).

### Services

| Component | Path | Purpose |
|-----------|------|---------|
| Backend API | `backend/api` | Express + Socket.io REST API (port 3000) |
| Infrastructure | `infrastructure/aws` | AWS CDK stacks |
| Integration Tests | `integration-tests` | Supertest tests against a deployed API |
| Mobile App | `apps/mobile` | Flutter app (not runnable in cloud VM) |

### Running the backend API

The backend requires PostgreSQL with PostGIS. After PostgreSQL is running:

```bash
cd backend/api
DATABASE_URL="postgresql://crimereport:crimereport@localhost:5432/crimereport" npm run dev
```

Start PostgreSQL if not already running: `sudo pg_ctlcluster 16 main start`

Run migrations: `DATABASE_URL="postgresql://crimereport:crimereport@localhost:5432/crimereport" npm run migrate:up` (from `backend/api`).

Redis is optional — the Socket.io adapter falls back to in-memory mode in development. AWS services (S3, SNS, CloudFront) are optional for local dev; empty-string defaults are used.

### Tests

- **Backend API unit tests** (`backend/api`): `npm test` — 15 suites, 136 tests. Tests mock DB/S3/Redis, no external services needed.
- **Infrastructure tests** (`infrastructure/aws`): `npm test` — 10 suites, 93 tests. Pure CDK snapshot/assertion tests.
- **Integration tests** (`integration-tests`): Require a running API; set `API_URL` env var.

### Lint

The `backend/api/package.json` has a `lint` script (`eslint src --ext .ts`) but the repo has no `.eslintrc` config file. This is a pre-existing gap.

### Build

- `backend/api`: `npm run build` (TypeScript → `dist/`)
- `infrastructure/aws`: `npm run build` (TypeScript → `dist/`)

### Gotchas

- The backend `npm run dev` uses `ts-node-dev` with `--respawn` for hot reload. New npm dependency installs are not picked up automatically — you must restart the dev server.
- All environment variables in `backend/api/src/config/index.ts` have development defaults except `DATABASE_URL`, which defaults to empty string (causing DB calls to fail). Always export `DATABASE_URL` when running the server.
- Reports are created with status `pending` and only become `active` after the media processing pipeline runs (AWS Step Functions in production). The `GET /api/v1/reports` nearby query filters for `active` reports by default, so newly created reports won't appear in list queries unless status is updated manually in the DB.
