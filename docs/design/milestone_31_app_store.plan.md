# Milestone 31: App Store Submission

## Status
Not Started

## Goal
Build release artifacts for iOS and Android, submit to App Store Connect and Google Play Console, manage the review process, execute launch, and establish post-launch monitoring and feedback loops.

## Dependencies
Requires **Milestone 30** complete (launch prep — production infra, assets, privacy policy, splash/onboarding).

## Plan

### 1. iOS Release Build

**Pre-build checklist:**

- [ ] `apps/mobile/pubspec.yaml` version is set (e.g., `version: 1.0.0+1`)
- [ ] `apps/mobile/ios/Runner.xcodeproj` — Bundle ID: `com.reportcrime.app`
- [ ] Signing certificate and provisioning profile are valid (Apple Developer account)
- [ ] Push notification capability enabled in Xcode Signing & Capabilities
- [ ] `NSLocationWhenInUseUsageDescription` set in `Info.plist`
- [ ] `NSCameraUsageDescription` set in `Info.plist`
- [ ] `NSMicrophoneUsageDescription` set in `Info.plist`
- [ ] `NSPhotoLibraryUsageDescription` set in `Info.plist`
- [ ] Privacy manifest (`PrivacyInfo.xcprivacy`) added with required API declarations
- [ ] Mapbox access token configured for production

**Build commands:**

```bash
cd apps/mobile

flutter clean
flutter pub get

# Build iOS release with production environment
flutter build ios --release --dart-define=ENV=prod

# Open Xcode for archive
open ios/Runner.xcworkspace
```

**Xcode archive and upload:**

1. Select "Any iOS Device (arm64)" as the build destination
2. Product → Archive
3. Window → Organizer → select archive → Distribute App
4. Select "App Store Connect" → Upload
5. Validate app before uploading (checks signing, entitlements, icons)

### 2. App Store Connect Configuration

```yaml
App Information:
  Name: CrimeReport
  Subtitle: Anonymous Crime Reporting
  Bundle ID: com.reportcrime.app
  SKU: crimereport-001
  Primary Language: English (U.S.)

Category:
  Primary: News
  Secondary: Social Networking

Pricing: Free (no in-app purchases)

Age Rating: 17+ (Mature/Suggestive Themes, Violence)

App Review Information:
  Contact: review@reportcrime.app
  Notes for Reviewer: |
    This app allows anonymous crime reporting. No account or login is required.

    To test the app:
    1. Allow location permission when prompted
    2. Browse the vertical video feed to see reports
    3. Tap the Map tab to view crime locations on a Mapbox map
    4. Tap the Report tab to open the camera for submitting a report
    5. Tap the Settings tab to view preferences and legal information

    The app is fully functional without authentication.
    All user-generated content is moderated via automated content analysis.

Version Release: Manual (recommended for first launch)

Privacy:
  Privacy Policy URL: https://reportcrime.app/privacy
  Data Collection:
    - Device identifier (anonymous UUID, not linked to identity)
    - Precise location (only when in use, for nearby reports)
    - Photos and videos (user-submitted crime evidence)
    - Other user content (report descriptions, comments)
  Data NOT Collected:
    - Name, email, phone number
    - Payment information
    - Browsing or search history
    - Contacts

App Store Screenshots: (from assets/app_store/ios/)
  6.7-inch (iPhone 15 Pro Max): 4 screenshots
  6.1-inch (iPhone 15 Pro): 4 screenshots

Keywords: crime, report, anonymous, safety, neighborhood, alert, community, map
```

**Common iOS rejection reasons and mitigations:**

| Risk | Mitigation |
|------|------------|
| Missing privacy manifest | Add `PrivacyInfo.xcprivacy` with API reason declarations |
| Location "always" permission requested | Only request "when in use" via `geolocator` with `permission_handler` |
| No login / authentication | Explain anonymous-by-design in review notes; no personal data stored |
| User-generated content without moderation | Rekognition content analysis in media pipeline + comment flagging |
| Camera/photo permission without clear use | Include descriptive `NSCameraUsageDescription`: "To capture photo or video evidence for your crime report" |

### 3. Android Release Build

**Pre-build checklist:**

- [ ] `apps/mobile/pubspec.yaml` version is set (e.g., `version: 1.0.0+1`)
- [ ] `apps/mobile/android/app/build.gradle` — applicationId: `com.reportcrime.app`
- [ ] Upload signing key created and stored securely
- [ ] `android/key.properties` configured (not committed to git)
- [ ] `android/app/build.gradle` references `key.properties` for release signing
- [ ] Mapbox access token configured in `android/app/src/main/AndroidManifest.xml`
- [ ] ProGuard / R8 rules configured (Flutter defaults are usually sufficient)
- [ ] `minSdkVersion` set appropriately (21+ for camera, geolocator)

**Create signing key (one-time):**

```bash
keytool -genkey -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

**Configure `android/key.properties`:**

```properties
storePassword=<password>
keyPassword=<password>
keyAlias=upload
storeFile=../upload-keystore.jks
```

**Build commands:**

```bash
cd apps/mobile

flutter clean
flutter pub get

# Build Android App Bundle with production environment
flutter build appbundle --release --dart-define=ENV=prod

# Output: build/app/outputs/bundle/release/app-release.aab
```

### 4. Google Play Console Configuration

```yaml
App Details:
  App Name: CrimeReport - Anonymous Safety
  Short Description: Report crime anonymously. Stay safe. Protect your community.
  Full Description: (from assets/app_store/android/full_description.txt)
  Category: News & Magazines
  Tags: safety, crime, community

Content Rating:
  Questionnaire: Violence (references to crime) → Mature 17+
  Target Audience: 18+

Data Safety:
  Data Collected:
    - Device or other IDs: Anonymous device identifier for spam prevention
    - Approximate location: To show nearby crime reports (required, not shared)
    - Precise location: To tag report locations (optional, user-initiated)
    - Photos and videos: User-submitted evidence (required for core feature)
    - Other user content: Report descriptions and comments
  Security: Data encrypted in transit (HTTPS/WSS), stored on AWS

Pricing: Free, no in-app purchases

Store Listing:
  Screenshots: (from assets/app_store/android/)
  Feature Graphic: 1024×500 (from assets/app_store/android/feature_graphic_1024x500.png)
  App Icon: 512×512 (from assets/app_store/android/icon_512x512.png)

Privacy Policy URL: https://reportcrime.app/privacy

Release Track: Production (or Internal Testing first, then staged rollout)
```

### 5. Pre-Launch Validation

Before submitting to either store, run these final checks:

**Backend health:**

```bash
# Verify production API is responding
curl https://api.reportcrime.app/health
# Expected: {"status":"ok","uptime":...}

curl https://api.reportcrime.app/health/ready
# Expected: {"status":"ok","checks":{"db":"connected","redis":"connected"}}
```

**Infrastructure readiness:**

- [ ] CloudWatch operations dashboard (`crimereport-operations`) shows all alarms in OK state
- [ ] ECS service has at least 2 running tasks
- [ ] ALB health checks passing on `/health`
- [ ] CloudFront distribution is deployed and serving from `cdn.reportcrime.app`
- [ ] WAF WebACL is associated with the ALB
- [ ] SNS alarm notifications are delivering to ops email

**App verification:**

- [ ] Production build installed on physical iOS device — test all tabs (Feed, Map, Report, Settings)
- [ ] Production build installed on physical Android device — test all tabs
- [ ] Reports load in feed with video playback working via CloudFront CDN
- [ ] Map shows markers with clustering at `apps/mobile/lib/features/map/presentation/map_screen.dart`
- [ ] Camera capture and upload flow completes end-to-end
- [ ] Push notifications received (if implemented in Milestone 28)
- [ ] WebSocket real-time updates work (new reports appear in feed)
- [ ] Settings screen displays correctly, including legal text screen

### 6. Submit and Monitor Review

**iOS submission timeline:**

1. Upload build via Xcode Organizer
2. Configure in App Store Connect (metadata, screenshots, review notes)
3. Submit for review
4. Typical review: 24–48 hours for initial submission
5. If rejected: read feedback, fix specific issue, resubmit with explanation
6. After approval: manually release when ready

**Android submission timeline:**

1. Upload AAB via Play Console
2. Complete store listing, content rating, data safety
3. Submit for review
4. Typical review: 1–7 days for new apps
5. If rejected: address policy issue, resubmit
6. After approval: choose rollout percentage (recommend 20% → 50% → 100%)

### 7. Launch Day Runbook

**T-24 hours:**

- [ ] Verify ECS auto-scaling is configured (`minCapacity: 2`, `maxCapacity: 10` in `compute-stack.ts`)
- [ ] Verify Aurora Serverless v2 ACU scaling range is sufficient
- [ ] Open CloudWatch operations dashboard in browser
- [ ] Confirm alarm SNS notifications are active
- [ ] Prepare rollback plan: if critical issues, pull app from stores and scale down

**T-0 (Release):**

```bash
# iOS: App Store Connect → select version → "Release This Version"
# Android: Play Console → Production → "Start rollout to Production"
```

**T+1 hour:**

- [ ] Check CloudWatch dashboard for error spikes
- [ ] Check ALB 5xx alarm — should be in OK state
- [ ] Check ECS task count — auto-scaling should respond to load
- [ ] Monitor Pino logs via CloudWatch Logs for unexpected errors
- [ ] Verify first user-created reports appear in the database

**T+24 hours:**

- [ ] Check app store reviews in both consoles
- [ ] Review crash reports (if Sentry/Crashlytics is integrated)
- [ ] Check custom metrics: `ReportsCreated`, `UploadsCompleted`, `WebSocketConnections`
- [ ] Respond to any 1-star reviews with acknowledgment and timeline

### 8. Post-Launch Monitoring

**CloudWatch metrics to watch** (already in `monitoring-stack.ts`):

- DB CPU utilization — alert if sustained >80%
- Redis memory usage — alert if >80%
- ECS CPU utilization — triggers auto-scaling at 70%
- ALB 5xx error count — alert if >10 in 5 minutes
- ALB response time — alert if average >2 seconds

**Application-level metrics** (added in Milestone 30):

- Reports created per hour
- Active WebSocket connections
- Media upload success/failure rate
- API response time p50/p95/p99

**Structured logs** — search in CloudWatch Logs via Pino JSON output:

```
fields @timestamp, @message
| filter @message like /error/
| sort @timestamp desc
| limit 50
```

### 9. Version Update Process

For subsequent releases after launch:

```bash
# 1. Bump version in pubspec.yaml
#    version: 1.0.1+2  (patch bump, build number increment)

# 2. Build both platforms
cd apps/mobile
flutter build ios --release --dart-define=ENV=prod
flutter build appbundle --release --dart-define=ENV=prod

# 3. Upload and submit
#    - iOS: Archive in Xcode → Upload → Submit with "What's New" notes
#    - Android: Upload AAB → Add release notes → Roll out
```

**Versioning convention:**

```
1.0.0 → Initial release
1.0.x → Bug fixes and minor improvements
1.x.0 → New features (e.g., new crime type filters, improved map clustering)
2.0.0 → Major redesign or breaking changes
```

## Deliverable Checklist
- [ ] iOS build archived, validated, and uploaded to App Store Connect
- [ ] All iOS metadata, screenshots, and privacy declarations completed
- [ ] iOS app submitted for review
- [ ] Android AAB built, signed, and uploaded to Play Console
- [ ] All Android metadata, screenshots, data safety, and content rating completed
- [ ] Android app submitted for review
- [ ] Both apps pass review (handle rejections if needed)
- [ ] Manual release executed on launch day
- [ ] Apps live and downloadable in both stores
- [ ] Post-launch monitoring confirms no critical issues
- [ ] First user reports created successfully in production
- [ ] CloudWatch alarms all in OK state after 24 hours

## Notes
- **No CI/CD for builds yet** — iOS and Android builds are manual via `flutter build` + Xcode / Play Console upload. Milestone 24.5 will add automated build pipelines with GitHub Actions.
- **Staged rollout on Android** is recommended — start at 20% to catch issues before full rollout.
- **iOS Privacy Manifest** is required since Spring 2024 — must declare API usage reasons in `PrivacyInfo.xcprivacy`. Our app uses `NSPrivacyAccessedAPICategoryUserDefaults` (shared_preferences) and `NSPrivacyAccessedAPICategoryDiskSpace` (cache manager).
- **Upload key security** — the Android upload keystore must be backed up securely. If lost, a new app listing is required. Consider Google Play App Signing (let Google manage the signing key).
- **Mapbox token** — the production Mapbox access token should be scoped to the app's bundle ID and have usage-based billing alerts configured.
- **Content rating** — because the app deals with crime content, both stores will likely require a 17+/Mature rating. Prepare for age-gating questions in the rating questionnaires.

## Files (3 new + existing modifications)
1. `apps/mobile/ios/Runner.xcworkspace` — archive and upload to App Store Connect
2. `apps/mobile/android/key.properties` — signing configuration (do NOT commit to git)
3. `docs/launch-runbook.md` — new, detailed launch day procedures
