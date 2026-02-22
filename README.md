# CrImEreport

Anonymous crime reporting mobile application.

## Architecture

![CrimeReport Full System Architecture](docs/design/diagrams/full_architecture.png)

## 📁 Project Structure

```
crimereport/
├── apps/
│   └── mobile/          # Flutter mobile application
├── backend/
│   └── api/             # Node.js REST API server
├── infrastructure/
│   └── aws/             # AWS CDK infrastructure
├── docs/                # Documentation
└── .github/
    └── workflows/       # CI/CD pipelines
```

## 🚀 Getting Started

### Prerequisites

- [Flutter](https://flutter.dev/docs/get-started/install) 3.10+
- [Node.js](https://nodejs.org/) 20+
- [AWS CLI](https://aws.amazon.com/cli/) (for deployment)

### Mobile App

```bash
cd apps/mobile
flutter pub get
flutter run
```

### Backend API (Coming Soon)

```bash
cd backend/api
npm install
npm run dev
```

### Infrastructure (Coming Soon)

```bash
cd infrastructure/aws
npm install
npx cdk deploy
```

## 🛠 Tech Stack

| Layer | Technology |
|-------|------------|
| **Mobile** | Flutter, Riverpod, Mapbox |
| **Backend** | Node.js, Express, Socket.io |
| **Database** | PostgreSQL + PostGIS, Redis |
| **Infrastructure** | AWS (ECS Fargate, Aurora, S3, CloudFront) |
| **Real-time** | WebSockets |
| **Push Notifications** | FCM via AWS SNS |

## 📱 Features

- Anonymous crime reporting
- TikTok-style video feed
- Interactive crime map (Snap Maps style)
- Real-time updates
- Push notifications for nearby crimes
- Upvoting and anonymous comments

## 📄 License

This project is private and proprietary.
