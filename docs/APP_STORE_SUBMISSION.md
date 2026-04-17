# CrimeReport — App Store Submission Guide

Step-by-step instructions for submitting CrimeReport to the Apple App Store and Google Play Store.

---

## Current Project State

| Item | Status | Details |
|------|--------|---------|
| Flutter app | Ready | Splash, onboarding, feed, map, camera, comments, settings |
| Backend API | Deployed | ECS Fargate behind ALB with WAF protection |
| Database | Live | Aurora Serverless v2 PostgreSQL + PostGIS |
| Media pipeline | Live | S3 + CloudFront + Step Functions (Rekognition + MediaConvert) |
| Push notifications | Configured | AWS SNS + Firebase Cloud Messaging |
| CI/CD | Active | GitHub Actions — PR checks + deploy on merge to main |
| Integration tests | Passing | 18 tests against live production API |
| Unit tests | Passing | 421 backend + 213 Flutter |
| iOS bundle ID | `com.report.reportcrime` | Set in Xcode project |
| Android applicationId | `com.report.reportcrime` | Set in build.gradle.kts |
| App icons | Generated | Both platforms, shield + exclamation mark design |
| Privacy manifest | Created | `PrivacyInfo.xcprivacy` with required API declarations |
| ATS exception | Configured | HTTP allowed for ALB hostname |
| Release build (iOS) | Verified | 68.4 MB, builds without errors |
| Release build (Android) | Verified | 75.8 MB AAB, builds without errors |
| HTTPS | Not configured | Using HTTP via ALB — see Known Limitations |

---

## Prerequisites

Before you begin, make sure you have:

- [ ] **Apple Developer account** ($99/year) — [developer.apple.com](https://developer.apple.com)
- [ ] **Google Play Developer account** ($25 one-time) — [play.google.com/console](https://play.google.com/console)
- [ ] **Mapbox access token** in `apps/mobile/.env` (you already have this if the map works)
- [ ] **Firebase project** — `crimereport-29782` (already configured)
- [ ] **Physical iOS device** for final testing (simulator is not sufficient for App Store review)
- [ ] **Physical Android device** for final testing
- [ ] **Xcode** installed and updated (latest stable)
- [ ] **macOS** (required for iOS builds)

---

## Part 1: iOS App Store Submission

### Step 1: Pre-Build Checklist

Run through these before building:

```bash
cd apps/mobile
```

- [ ] `.env` has your real `MAPBOX_ACCESS_TOKEN`, `API_BASE_URL`, and `WS_BASE_URL`
- [ ] `pubspec.yaml` version is `1.0.0+1` (or your desired version)
- [ ] Your Apple Developer team is set in Xcode (Runner → Signing & Capabilities)
- [ ] Push Notifications capability is enabled in Xcode Signing & Capabilities
- [ ] `Info.plist` has all required usage descriptions (location, camera, mic, photos) — already done

### Step 2: Build the iOS Release

```bash
cd apps/mobile

# Clean previous builds
flutter clean
flutter pub get

# Build iOS release
flutter build ios --release

# Open Xcode workspace
open ios/Runner.xcworkspace
```

### Step 3: Archive in Xcode

1. In Xcode, select **"Any iOS Device (arm64)"** as the build destination (not a simulator)
2. Menu: **Product → Archive**
3. Wait for the archive to complete (2-5 minutes)
4. The **Organizer** window opens automatically. If not: **Window → Organizer**

### Step 4: Upload to App Store Connect

1. In Organizer, select your archive and click **"Distribute App"**
2. Choose **"App Store Connect"** → **"Upload"**
3. Click **"Validate App"** first to catch any issues (signing, icons, entitlements)
4. Fix any validation errors, then click **"Upload"**
5. Wait for the upload to complete and processing notification from Apple (usually 5-30 minutes)

### Step 5: Configure App Store Connect

Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com) and create a new app:

**App Information:**

| Field | Value |
|-------|-------|
| Name | CrimeReport |
| Subtitle | Anonymous Crime Reporting |
| Bundle ID | `com.report.reportcrime` |
| SKU | `crimereport-001` |
| Primary Language | English (U.S.) |
| Category | News |
| Secondary Category | Social Networking |
| Content Rights | Does not contain third-party content |

**Pricing:** Free (no in-app purchases)

**Age Rating:** Complete the questionnaire. Select:
- Mature/Suggestive Themes: Frequent/Intense
- Realistic Violence: Infrequent/Mild (crime reports may reference violence)
- Result will likely be **17+**

**Privacy Policy URL:**
You need a hosted privacy policy. Options:
- Host the existing `docs/privacy-policy.md` as a webpage (GitHub Pages, or any static host)
- Or use a free privacy policy hosting service

**App Review Information:**

```
Notes for Reviewer:

This app allows anonymous crime reporting. No account or login is required.

To test the app:
1. Allow location permission when prompted
2. Browse the vertical video feed to see recent crime reports
3. Tap the Map tab to view crime locations on an interactive map
4. Tap the Report tab to open the camera and submit a report
5. Tap any report to view comments and details

The app is fully functional without authentication.
All user-generated content is moderated via AWS Rekognition automated content analysis.
Community moderation is provided through upvoting and comment flagging.
```

### Step 6: Add Screenshots

You need screenshots for at least one device size. Recommended: **6.7-inch (iPhone 15 Pro Max)**.

**Capture screenshots from the simulator:**

```bash
# Run the app on iPhone 15 Pro Max simulator
flutter run -d "iPhone 15 Pro Max"
```

Then press **Cmd+S** in the simulator to save a screenshot. Capture 4-6 screens:
1. Video feed (main screen with a report playing)
2. Map view with crime markers
3. Report detail with comments
4. Camera/submit screen
5. Settings screen
6. Onboarding screen (optional)

Upload these in App Store Connect under **App Store → Screenshots**.

### Step 7: Submit for Review

1. Select the build you uploaded in the "Build" section
2. Fill in "What's New in This Version" (for v1.0: leave blank or write "Initial release")
3. Click **"Submit for Review"**
4. Typical first-app review: **24-48 hours**

### Common iOS Rejection Reasons

| Risk | How We've Mitigated |
|------|---------------------|
| Missing privacy manifest | `PrivacyInfo.xcprivacy` created with UserDefaults + FileTimestamp declarations |
| No login / authentication | App is anonymous by design — explained in review notes |
| User content without moderation | AWS Rekognition content analysis + comment flagging |
| HTTP instead of HTTPS | ATS exception added for ALB hostname — note to reviewer recommended |
| Location permission without clear purpose | Descriptive `NSLocationWhenInUseUsageDescription` in Info.plist |

---

## Part 2: Google Play Store Submission

### Step 1: Create the Upload Signing Key

This is a one-time step. **Back up the keystore securely — if lost, you cannot update the app.**

```bash
cd apps/mobile

# Generate the upload keystore
keytool -genkey -v \
  -keystore android/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

You'll be prompted for:
- Keystore password (choose a strong one, save it securely)
- Key password (can be the same)
- Your name, organization, city, state, country code

### Step 2: Create `key.properties`

Create `apps/mobile/android/key.properties` (this file is gitignored):

```properties
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=../upload-keystore.jks
```

### Step 3: Build the Release AAB

```bash
cd apps/mobile

# Clean previous builds
flutter clean
flutter pub get

# Build the Android App Bundle
flutter build appbundle --release

# Output location:
# build/app/outputs/bundle/release/app-release.aab
```

### Step 4: Update Firebase (One-Time)

The Android app's `applicationId` was changed from `com.example.reportcrime` to `com.report.reportcrime`. You need to register this new package name in Firebase:

1. Go to [Firebase Console](https://console.firebase.google.com/) → project `crimereport-29782`
2. Project Settings → General → Your apps
3. Add an Android app with package name `com.report.reportcrime`
4. Download the new `google-services.json` and replace `apps/mobile/android/app/google-services.json`

### Step 5: Configure Google Play Console

Go to [play.google.com/console](https://play.google.com/console) and create a new app:

**App Details:**

| Field | Value |
|-------|-------|
| App name | CrimeReport |
| Default language | English (United States) |
| App or game | App |
| Free or paid | Free |

**Store Listing:**

| Field | Value |
|-------|-------|
| Short description | Report crime anonymously. Stay safe. Protect your community. |
| Full description | See below |
| App icon | 512x512 PNG (use `assets/app_icon.png` or export from generated icons) |
| Feature graphic | 1024x500 PNG (create a simple banner with the app icon + tagline) |
| Screenshots | At least 2 phone screenshots (capture from Android emulator) |

**Full description suggestion:**

```
CrimeReport lets you anonymously report crimes in your neighborhood. No account needed — just open the app and start reporting.

Features:
• Browse a TikTok-style video feed of nearby crime reports
• View an interactive map with crime locations and clustering
• Submit reports with photos and videos — fully anonymous
• Comment on reports and discuss with your community
• Upvote important reports to increase visibility
• Get push notifications for crimes reported near you
• Content moderation keeps the community safe

Your privacy matters. CrimeReport never collects your name, email, or any personal information. Device identification uses anonymous, non-reversible IDs.
```

**Content Rating:**

Complete the questionnaire in Play Console → Policy → Content rating:
- Violence: References to violence in crime reports → likely **Mature 17+**
- Target audience: 18+

**Data Safety:**

Fill in the Data Safety questionnaire:

| Question | Answer |
|----------|--------|
| Does your app collect or share user data? | Yes |
| **Device or other IDs** | Collected — anonymous device UUID, not linked to identity, for spam prevention |
| **Approximate location** | Collected — to show nearby reports, required for core functionality, not shared |
| **Precise location** | Collected — to tag report locations, user-initiated, not shared |
| **Photos and videos** | Collected — user-submitted evidence, required for core feature |
| **Other user content** | Collected — report descriptions and comments |
| Is data encrypted in transit? | Yes |
| Can users request data deletion? | Data is anonymous — no personal data to delete |

**Privacy Policy URL:** Same hosted URL as iOS.

### Step 6: Upload and Submit

1. Play Console → **Release** → **Production** (or start with **Internal testing** for a dry run)
2. Click **"Create new release"**
3. Upload `app-release.aab` from `build/app/outputs/bundle/release/`
4. Add release notes: "Initial release"
5. Click **"Review release"** → **"Start rollout"**

**Recommended rollout strategy:**
- Start with **Internal testing** (just you and testers) to verify
- Then **Closed testing** (invite a small group)
- Then **Production** at 20% → 50% → 100%

Typical review time: **1-7 days** for new apps.

---

## Part 3: Pre-Launch Validation

Run these checks before submitting to either store.

### Backend Health

```bash
# Verify the production API is responding
curl -H "User-Agent: CrimeReport/1.0" \
  http://crimereport-alb-822016960.us-east-1.elb.amazonaws.com/health
# Expected: {"status":"ok","uptime":...,"timestamp":"..."}

curl -H "User-Agent: CrimeReport/1.0" \
  http://crimereport-alb-822016960.us-east-1.elb.amazonaws.com/health/ready
# Expected: {"status":"ok","checks":{"db":"connected","redis":"connected"}}
```

### Infrastructure Checklist

- [ ] CloudWatch dashboard shows all alarms in OK state
- [ ] ECS service has at least 2 running tasks
- [ ] ALB health checks passing on `/health`
- [ ] WAF WebACL is associated with the ALB
- [ ] CloudFront distribution is deployed and serving media

### Device Testing Checklist

Install the release build on a physical device and test:

- [ ] Splash screen appears with shield animation
- [ ] Onboarding flow works (first launch only)
- [ ] Location permission prompt appears
- [ ] Feed loads reports from the API (may be empty if no reports exist)
- [ ] Map displays with Mapbox tiles and any existing markers
- [ ] Camera opens and can capture photo/video
- [ ] Report submission completes end-to-end
- [ ] Comments can be posted on a report
- [ ] Upvoting works
- [ ] Settings screen displays correctly
- [ ] Push notifications are received (if enabled)
- [ ] WebSocket real-time updates work (new report appears in feed after creation)
- [ ] App doesn't crash on any screen transition

### Seed Some Test Data

If the feed is empty, create a few test reports from the device so reviewers see content:

1. Open the app → Report tab → capture a photo/video
2. Fill in details (type, description, address)
3. Submit 3-5 reports with different crime types
4. Go back to Feed — your reports should appear
5. Add some comments to the reports

---

## Part 4: Launch Day Runbook

### T-24 Hours

- [ ] Verify ECS auto-scaling: `minCapacity: 2`, `maxCapacity: 10`
- [ ] Verify Aurora ACU range is sufficient for expected load
- [ ] Open CloudWatch operations dashboard in a browser tab
- [ ] Confirm alarm SNS notifications are active and delivering
- [ ] Prepare rollback plan: pull app from stores + scale down if critical issues

### T-0 (Release)

```
iOS:     App Store Connect → select version → "Release This Version"
Android: Play Console → Production → "Start rollout to Production"
```

### T+1 Hour

- [ ] Check CloudWatch dashboard for error spikes
- [ ] Check ALB 5xx alarm — should be in OK state
- [ ] Check ECS task count — auto-scaling should respond to load
- [ ] Monitor Pino logs via CloudWatch Logs for unexpected errors
- [ ] Verify first user-created reports appear in the database

### T+24 Hours

- [ ] Check app store reviews in both consoles
- [ ] Check custom metrics: `ReportsCreated`, `MediaUploadsCompleted`, `WebSocketConnections`
- [ ] Check `MediaFailureRate` alarm is not triggered
- [ ] Respond to any negative reviews with acknowledgment and timeline

---

## Part 5: Post-Launch Monitoring

### CloudWatch Metrics (already configured in monitoring-stack.ts)

| Metric | Alert Threshold |
|--------|----------------|
| DB CPU utilization | Sustained >80% |
| Redis memory usage | >80% |
| ECS CPU utilization | >70% (triggers auto-scaling) |
| ALB 5xx error count | >10 in 5 minutes |
| ALB response time | Average >2 seconds |

### Application Metrics (added in Milestone 30)

| Metric | What to Watch |
|--------|---------------|
| `ReportsCreated` | Baseline after launch — spikes = viral, zero = problem |
| `MediaUploadsCompleted` | Should correlate with reports created |
| `MediaFailureRate` | Should stay near zero |
| `MediaProcessingLatency` | Typical: 5-30 seconds |
| `WebSocketConnections` | Active users — compare with store install counts |
| `RateLimitHits` | Spikes = potential abuse |

### Searching Logs

In CloudWatch Logs Insights, query the ECS task logs:

```
fields @timestamp, @message
| filter @message like /error/
| sort @timestamp desc
| limit 50
```

---

## Part 6: Version Updates (Post-Launch)

For subsequent releases:

```bash
# 1. Bump version in pubspec.yaml
#    version: 1.0.1+2  (patch bump + build number increment)

# 2. Build both platforms
cd apps/mobile
flutter clean && flutter pub get
flutter build ios --release
flutter build appbundle --release

# 3. Upload and submit
#    iOS: Archive in Xcode → Upload → Submit with "What's New" notes
#    Android: Upload AAB to Play Console → Add release notes → Roll out
```

**Versioning convention:**

```
1.0.0  → Initial release
1.0.x  → Bug fixes
1.x.0  → New features
2.0.0  → Major redesign
```

---

## Known Limitations

These are acceptable for initial launch but should be addressed post-launch:

| Limitation | Impact | Fix |
|------------|--------|-----|
| **HTTP only (no HTTPS)** | ATS exception needed on iOS; Apple may flag during review | Register a domain, provision ACM certificate, enable HTTPS listener on ALB |
| **No custom domain** | Users see raw ALB URL in network traffic | Register `reportcrime.app` (or similar), configure Route 53 + DNS stack |
| **No crash reporting** | Can't see crash logs from user devices | Add Sentry or Firebase Crashlytics |
| **No analytics** | Can't measure user engagement or retention | Add Firebase Analytics or Mixpanel |
| **Manual builds** | iOS/Android builds are manual | Add `flutter build` jobs to GitHub Actions CI/CD |
| **No staged environments** | Tests run against production | Add a staging stack with separate database |

---

## Quick Reference

| Resource | URL |
|----------|-----|
| App Store Connect | [appstoreconnect.apple.com](https://appstoreconnect.apple.com) |
| Google Play Console | [play.google.com/console](https://play.google.com/console) |
| Firebase Console | [console.firebase.google.com](https://console.firebase.google.com) |
| AWS CloudWatch | [console.aws.amazon.com/cloudwatch](https://console.aws.amazon.com/cloudwatch) |
| GitHub Actions | [github.com/AbelShiferaw/crimereport/actions](https://github.com/AbelShiferaw/crimereport/actions) |
| Production API Health | `curl -H "User-Agent: CrimeReport/1.0" http://crimereport-alb-822016960.us-east-1.elb.amazonaws.com/health` |
