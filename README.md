# CrImEreport

Anonymous crime reporting mobile application. Users can report, view, and discuss crimes in their area -- fully anonymously, no accounts required.

## Architecture

![CrimeReport Full System Architecture](docs/design/diagrams/full_architecture.png)

## Project Structure

```
crimereport/
├── apps/
│   └── mobile/              # Flutter mobile app (Riverpod, Mapbox, video_player)
├── backend/
│   ├── api/                 # Node.js REST API (TypeScript, Express, Socket.io)
│   └── functions/           # AWS Lambda functions (transcode trigger)
├── infrastructure/
│   └── aws/                 # AWS CDK stacks (VPC, Aurora, S3, ECS, etc.)
├── docs/
│   └── design/              # Milestone plans and architecture docs
└── .github/
    └── workflows/           # CI/CD pipelines
```

## Getting Started

### Prerequisites

- [Flutter](https://flutter.dev/docs/get-started/install) 3.10+
- [Node.js](https://nodejs.org/) 20+
- [AWS CLI](https://aws.amazon.com/cli/) + [AWS CDK](https://docs.aws.amazon.com/cdk/v2/guide/getting-started.html)

### Mobile App

```bash
cd apps/mobile
cp .env.example .env        # Add your Mapbox token
flutter pub get
flutter run
```

### Backend API

```bash
cd backend/api
npm install
npm run dev                  # Starts on http://localhost:3000
```

See [backend/api/README.md](backend/api/README.md) for full API documentation including all endpoints, request/response schemas, error codes, rate limits, and the media upload flow.

### Infrastructure

```bash
cd infrastructure/aws
npm install
npx cdk synth                # Validate templates
npx cdk deploy --all         # Deploy all stacks
```

## Tech Stack

| Layer | Technology |
|-------|------------|
| **Mobile** | Flutter, Riverpod, Mapbox GL, video_player, camera |
| **Backend** | TypeScript, Express, Socket.io, Zod, Pino |
| **Database** | Aurora Serverless v2 PostgreSQL + PostGIS, ElastiCache Redis |
| **Infrastructure** | AWS CDK (ECS Fargate, ALB, WAF, S3, CloudFront, Step Functions) |
| **Media Pipeline** | Step Functions, Rekognition (moderation), MediaConvert (transcoding) |
| **Real-time** | Socket.io with Redis adapter |
| **Push** | AWS SNS + Firebase Cloud Messaging |

## API Overview

The REST API runs on ECS Fargate behind an Application Load Balancer with WAF protection.

| Endpoint Group | Base Path | Description |
|---------------|-----------|-------------|
| Health | `/health` | Liveness and readiness probes |
| Reports | `/api/v1/reports` | CRUD, nearby search (PostGIS), upvoting |
| Comments | `/api/v1/reports/:id/comments` | List and create anonymous comments |
| Comment Flags | `/api/v1/comments/:id/flag` | Flag inappropriate comments |
| Media Upload | `/api/v1/reports/:id/upload` | Two-phase presigned URL upload to S3 |

Full endpoint documentation: [backend/api/README.md](backend/api/README.md)

## Features

- Fully anonymous -- no accounts, no PII, device ID is hashed
- TikTok-style vertical video feed with autoplay
- Interactive crime map (Snap Maps style) with clustering
- Two-phase media upload with automatic content moderation
- Real-time updates via WebSocket
- Push notifications for nearby crimes
- Community moderation via upvoting and flagging
- Device-based rate limiting and abuse prevention

## Development Progress

| Phase | Milestones | Status |
|-------|-----------|--------|
| A: Flutter App | 1-13 | Completed |
| B: AWS Infrastructure | 14-17 | Completed |
| C: Backend API | 18-22 | Completed |
| C: Backend API (cont.) | 23 | Completed |
| C: Backend API (cont.) | 24 | Not started |
| C.5: CI/CD | 24.5 | Not started |
| D: Integration | 25-28 | Not started |
| E: Testing & Launch | 29-31 | Not started |

See [docs/design/](docs/design/) for detailed milestone plans.

## License

This project is private and proprietary.
