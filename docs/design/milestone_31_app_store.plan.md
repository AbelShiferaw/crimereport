# Milestone 31: App Store Submission

## Goal

Submit the app to Apple App Store and Google Play Store, manage review process, and launch.

## Dependencies

Requires **Milestone 30** complete (launch prep done).

## Implementation

### 1. iOS App Store Submission

**Build for Release:**

```bash
# Clean and build
flutter clean
flutter pub get

# Build iOS release
flutter build ios --release --dart-define=ENV=prod

# Open Xcode
open ios/Runner.xcworkspace
```

**Xcode Archive:**

1. Select "Any iOS Device" as target
2. Product → Archive
3. Distribute App → App Store Connect
4. Upload

**App Store Connect:**

```yaml
Build Settings:
  - Select uploaded build
  - Add build notes for reviewers

App Review Information:
  Contact: your-name
  Email: review@reportcrime.app
  Phone: +1-xxx-xxx-xxxx
  
  Demo Account: Not required (anonymous app)
  
  Notes for Reviewer: |
    This app allows anonymous crime reporting. No account is required.
    
    To test:
    1. Allow location permission when prompted
    2. Browse the feed to see sample reports
    3. Tap the map tab to see crime locations
    4. Use the + tab to simulate submitting a report
    
    The app is designed to be fully functional without an account.
    All content is user-generated and moderated.

Version Release:
  - Manual release (recommended for first launch)
  OR
  - Automatic after approval
```

**Common Rejection Reasons & Fixes:**

| Rejection | Fix |

|-----------|-----|

| Missing privacy manifest | Add PrivacyInfo.xcprivacy |

| Location always permission | Only request "when in use" |

| No login option | Clarify anonymous design in notes |

| User-generated content | Add reporting/moderation features |

| Crash on launch | Test on real devices |

### 2. Google Play Store Submission

**Build for Release:**

```bash
# Build Android App Bundle
flutter build appbundle --release --dart-define=ENV=prod

# Output: build/app/outputs/bundle/release/app-release.aab
```

**Create Signed Bundle:**

```bash
# If not already done, create upload key
keytool -genkey -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload

# Configure in android/key.properties
storePassword=xxx
keyPassword=xxx
keyAlias=upload
storeFile=../upload-keystore.jks
```

**Google Play Console:**

```yaml
Production Track:
  - Upload AAB file
  - Add release notes
  
Content Rating:
  - Complete questionnaire
  - Crime/violence themes → Mature 17+
  
Data Safety:
  - Location: Collected, required for core functionality
  - Device identifiers: Collected, for spam prevention
  - Photos/videos: Collected, user-submitted content
  
Target Audience:
  - Adults only (18+)
  
App Category:
  - News & Magazines
  - OR Social

Store Listing:
  - All assets from Milestone 30
  - Feature graphic required
  
Pricing:
  - Free
  - No in-app purchases
```

### 3. Post-Submission Monitoring

**Track Review Status:**

```dart
// Set up webhook for status updates (App Store Connect API)
// Or check manually in both consoles
```

**Respond to Review:**

```markdown
## If Rejected

1. Read rejection reason carefully
2. Fix the specific issue
3. Re-submit with detailed notes explaining the fix
4. Don't argue - just fix and explain

## Common iOS Review Times
- Initial: 24-48 hours
- Resubmission: 24 hours

## Common Play Store Review Times
- Initial: 1-7 days
- Updates: Usually faster
```

### 4. Launch Day

**Pre-Launch (T-24h):**

- [ ] Backend scaled up
- [ ] Monitoring dashboards open
- [ ] Support email ready
- [ ] Social media posts scheduled

**Launch:**

```bash
# If manual release:
# iOS: App Store Connect → Release this version
# Android: Play Console → Release to Production

# Monitor:
# - Error rates in Sentry
# - Server metrics in CloudWatch
# - User reviews in stores
```

**Post-Launch Monitoring:**

```javascript
// backend/src/utils/metrics.js

const cloudwatch = new CloudWatchClient({});

async function recordMetric(name, value, unit = 'Count') {
  await cloudwatch.send(new PutMetricDataCommand({
    Namespace: 'ReportCrime',
    MetricData: [{
      MetricName: name,
      Value: value,
      Unit: unit,
      Timestamp: new Date(),
    }],
  }));
}

// Track key metrics
recordMetric('ReportsCreated', 1);
recordMetric('ActiveUsers', activeCount);
recordMetric('APILatency', latencyMs, 'Milliseconds');
```

### 5. Version Update Process

**For Future Updates:**

```bash
# 1. Update version numbers
# pubspec.yaml: version: 1.0.1+2

# 2. Build both platforms
flutter build ios --release --dart-define=ENV=prod
flutter build appbundle --release --dart-define=ENV=prod

# 3. Upload and submit
# - Include "What's New" notes
# - Highlight new features
```

**Semantic Versioning:**

```
1.0.0 → Initial release
1.0.1 → Bug fixes
1.1.0 → New features
2.0.0 → Major changes / breaking changes
```

### 6. User Feedback Loop

**Review Monitoring:**

```dart
// Check reviews daily for first 2 weeks

// Respond to negative reviews:
// - Acknowledge the issue
// - Explain fix timeline
// - Follow up when fixed

// Feature requests:
// - Log in feedback tracker
// - Prioritize for future releases
```

**Crash Reporting:**

```dart
// Sentry dashboard
// - Check daily for new issues
// - Prioritize by user impact
// - Fix critical crashes within 24h
```

## Launch Checklist

```markdown
## Final Launch Checklist

### App Store (iOS)
- [ ] Build uploaded to App Store Connect
- [ ] All metadata complete
- [ ] Screenshots approved
- [ ] App review submitted
- [ ] Review approved
- [ ] Ready for manual release

### Play Store (Android)
- [ ] AAB uploaded to Play Console
- [ ] All metadata complete
- [ ] Content rating complete
- [ ] Data safety complete
- [ ] Review submitted
- [ ] Review approved
- [ ] Ready for rollout

### Backend
- [ ] Production database ready
- [ ] ECS scaled to handle launch traffic
- [ ] CloudFront cache warmed
- [ ] Monitoring alerts configured
- [ ] On-call schedule set

### Marketing
- [ ] Launch announcement ready
- [ ] Social media scheduled
- [ ] Press release sent (optional)

### Support
- [ ] Support email monitored
- [ ] FAQ published
- [ ] Known issues documented
```

## Deliverable Checklist

- [ ] iOS build uploaded and submitted
- [ ] Android AAB uploaded and submitted
- [ ] Both apps pass review
- [ ] Manual release executed
- [ ] App live in both stores
- [ ] First downloads received
- [ ] No critical crashes
- [ ] Monitoring dashboards green
- [ ] First user reviews positive
- [ ] Post-launch metrics tracked

## Files (3 total)

1. `ios/Runner.xcworkspace` - Archive and upload
2. `android/app/build.gradle` - Release config
3. `docs/launch-runbook.md` - Launch procedures

---

# 🎉 Congratulations!

You've completed all 31 milestones and launched ReportCrime!

## What's Next?

1. Monitor user feedback and reviews
2. Fix any reported bugs quickly
3. Plan v1.1 features based on feedback
4. Scale infrastructure as needed
5. Consider monetization (premium features, ads)