# Push Notification Setup Guide

## Context

CrimeReport sends push notifications to nearby users when a new crime report becomes active (i.e., after media has been uploaded and processed). This is a core feature — users who aren't actively looking at the app still need to be alerted about incidents near them.

Mobile push notifications require platform-specific infrastructure on both Apple and Google's side. You can't just "send a notification" — each platform (iOS and Android) has its own proprietary push service that acts as a gatekeeper to deliver messages to devices. Your backend never talks to the device directly; it talks to these intermediary services, which then relay the notification to the user's phone.

- **Android** uses **Firebase Cloud Messaging (FCM)**, which requires a Firebase project and service account credentials.
- **iOS** uses **Apple Push Notification service (APNs)**, which requires enrollment in the Apple Developer Program ($99/year) and a cryptographic key from Apple.

Rather than our backend integrating with FCM and APNs separately, we use **AWS SNS (Simple Notification Service)** as a unified dispatch layer. SNS abstracts both platforms behind a single API — you register a device token, SNS creates an endpoint, and you publish to that endpoint regardless of whether it's iOS or Android. SNS handles translating the message into the right format and forwarding it to FCM or APNs.

This guide covers the full setup process for both platforms, from creating accounts and credentials to registering them with AWS SNS.

## Architecture Overview

```
Flutter App → FCM/APNs Token → Backend API → AWS SNS → FCM / APNs → Device
```

- **Android**: Firebase Cloud Messaging (FCM) V1 API
- **iOS**: Apple Push Notification service (APNs) with token-based auth (.p8 key)
- **Backend Dispatcher**: AWS SNS Platform Applications

---

## Android / Firebase Setup

### 1. Create Firebase Project

- Go to [Firebase Console](https://console.firebase.google.com)
- Create a new project (e.g., `crimereport-29782`)
- Enable **Firebase Cloud Messaging API (V1)** under Project Settings > Cloud Messaging
- The Legacy API is deprecated — use V1 only

### 2. Configure Flutter with FlutterFire

```bash
# Install FlutterFire CLI
dart pub global activate flutterfire_cli

# Run from the Flutter project root
flutterfire configure --project=<firebase-project-id>
```

This creates `lib/firebase_options.dart` and registers per-platform apps.

### 3. Initialize Firebase in Flutter

```dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
);
```

### 4. Download FCM V1 Service Account JSON

- Firebase Console > Project Settings > Service accounts
- Click **Generate new private key**
- This downloads a JSON file containing the service account credentials

### 5. Store FCM Credentials in AWS Secrets Manager

```bash
aws secretsmanager create-secret \
  --name /crimereport/fcm-service-account \
  --secret-string file:///path/to/service-account.json
```

### 6. Create Android SNS Platform Application

```bash
# Retrieve the FCM service account JSON
aws secretsmanager get-secret-value \
  --secret-id /crimereport/fcm-service-account \
  --query SecretString --output text > /tmp/fcm-key.json

# Create attributes file (JSON with special chars needs file-based approach)
python3 -c "
import json
with open('/tmp/fcm-key.json') as f:
    cred = f.read().strip()
attrs = json.dumps({'PlatformCredential': cred})
with open('/tmp/sns-android-attrs.json', 'w') as f:
    f.write(attrs)
"

# Create the SNS Platform Application
aws sns create-platform-application \
  --name crimereport-android \
  --platform GCM \
  --attributes file:///tmp/sns-android-attrs.json

# Clean up
rm /tmp/fcm-key.json /tmp/sns-android-attrs.json
```

### 7. Store Android ARN in SSM

```bash
aws ssm put-parameter \
  --name /crimereport/sns-android-platform-arn \
  --value "arn:aws:sns:<region>:<account>:app/GCM/crimereport-android" \
  --type String
```

---

## iOS / APNs Setup

### Prerequisites

- **Apple Developer Program** enrollment ($99/year) at [developer.apple.com/programs/enroll](https://developer.apple.com/programs/enroll)
- Enrollment can take up to 48 hours to process
- A free Apple ID is NOT sufficient — the paid program is required for APNs keys and App Store distribution

### 1. Create an APNs Authentication Key

1. Go to [developer.apple.com/account/resources/authkeys/list](https://developer.apple.com/account/resources/authkeys/list)
2. Click **+** to create a new key
3. Name it (e.g., `CrimeReport Push Key`)
4. Check **Apple Push Notifications service (APNs)**
5. Environment: **Sandbox** for development/TestFlight, **Production** for App Store
6. Key Restriction: **Leave unrestricted** (no restrictions needed)
7. Click Continue > Register
8. **Download the `.p8` file** (one-time download only — store securely)
9. Note the **Key ID** (10-character alphanumeric string)

### 2. Get Your Team ID

- Go to [developer.apple.com/account](https://developer.apple.com/account)
- Find **Membership Details**
- Team ID is a 10-character alphanumeric string

### 3. Ensure Push Notifications Capability is Enabled

1. Go to [developer.apple.com/account/resources/identifiers/list](https://developer.apple.com/account/resources/identifiers/list)
2. Find your app's Bundle ID
3. Ensure **Push Notifications** capability is enabled

### 4. Create iOS SNS Platform Application

```bash
# Create attributes file
python3 -c "
import json
with open('/path/to/AuthKey_XXXXXXXX.p8') as f:
    key = f.read().strip()
attrs = json.dumps({
    'PlatformCredential': key,
    'PlatformPrincipal': '<KEY_ID>',
    'ApplePlatformTeamID': '<TEAM_ID>',
    'ApplePlatformBundleID': '<BUNDLE_ID>'
})
with open('/tmp/sns-ios-attrs.json', 'w') as f:
    f.write(attrs)
"

# Create the SNS Platform Application
# Use APNS_SANDBOX for dev/TestFlight, APNS for production
aws sns create-platform-application \
  --name crimereport-ios \
  --platform APNS_SANDBOX \
  --attributes file:///tmp/sns-ios-attrs.json

# Clean up
rm /tmp/sns-ios-attrs.json
```

### 5. Store iOS ARN in SSM

```bash
aws ssm put-parameter \
  --name /crimereport/sns-ios-platform-arn \
  --value "arn:aws:sns:<region>:<account>:app/APNS_SANDBOX/crimereport-ios" \
  --type String
```

---

## Current Configuration (CrimeReport)

| Item | Value |
|------|-------|
| Firebase Project | `crimereport-29782` |
| FCM Secret | `/crimereport/fcm-service-account` (Secrets Manager) |
| Android SNS ARN | SSM: `/crimereport/sns-android-platform-arn` |
| iOS SNS ARN | SSM: `/crimereport/sns-ios-platform-arn` |
| iOS Environment | Sandbox (APNS_SANDBOX) |
| iOS Bundle ID | `com.report.reportcrime` |
| APNs Key ID | `JG3XHVPA3G` |
| Apple Team ID | `2K5CLJF9KG` |

## Production Checklist

When moving to production:

1. Create a new APNs key with **Production** environment (or if using token-based auth with a key that supports both, just update the SNS platform to `APNS`)
2. Create a new SNS Platform Application with `--platform APNS` (not `APNS_SANDBOX`)
3. Update the SSM parameter `/crimereport/sns-ios-platform-arn` with the production ARN
4. Redeploy (CDK deploy picks up the new SSM value)

## Credential Security

- **FCM service account JSON**: Stored in AWS Secrets Manager, never committed to git
- **APNs .p8 key**: Stored locally, referenced only by file path during SNS setup, never committed to git
- **SNS Platform ARNs**: Stored in SSM Parameter Store (not sensitive, just resource identifiers)
- **Key IDs and Team IDs**: Not sensitive — safe to reference in documentation

## Troubleshooting

- **FCM V1 vs Legacy**: The Legacy FCM API is deprecated. Use V1 with service account JSON credentials.
- **APNs Sandbox vs Production**: Sandbox tokens only work with APNS_SANDBOX endpoints. App Store builds need APNS production endpoints.
- **SNS EndpointDisabledException**: Means the device token is invalid or the user disabled notifications. The backend auto-disables the subscription in the database.
- **CLI attribute parsing errors**: JSON credentials with special characters break `--attributes key=value` syntax. Always use `--attributes file:///path/to/attrs.json` approach.
