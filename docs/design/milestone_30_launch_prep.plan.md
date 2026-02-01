# Milestone 30: Launch Prep

## Goal
Prepare the app for production launch - app store assets, privacy policy, final polish, and production infrastructure.

## Dependencies
Requires **Milestone 29** complete (testing passed).

## Implementation

### 1. App Store Assets

**iOS App Store:**
```
assets/app_store/ios/
├── icon_1024x1024.png          # App icon
├── screenshots/
│   ├── 6.5_inch/               # iPhone 14 Pro Max
│   │   ├── 01_feed.png
│   │   ├── 02_map.png
│   │   ├── 03_submit.png
│   │   └── 04_notification.png
│   ├── 5.5_inch/               # iPhone 8 Plus
│   └── 12.9_inch/              # iPad Pro
├── app_preview_video.mov       # Optional
└── promotional_text.txt
```

**Google Play Store:**
```
assets/app_store/android/
├── icon_512x512.png            # Hi-res icon
├── feature_graphic_1024x500.png
├── screenshots/
│   ├── phone/
│   │   ├── 01_feed.png
│   │   ├── 02_map.png
│   │   ├── 03_submit.png
│   │   └── 04_notification.png
│   └── tablet/
└── short_description.txt       # 80 chars max
└── full_description.txt        # 4000 chars max
```

### 2. App Store Metadata

**iOS App Store Connect:**
```yaml
App Name: ReportCrime
Subtitle: Anonymous Crime Reporting
Category: News / Social Networking
Age Rating: 17+ (Mature/Suggestive Themes)
Privacy URL: https://reportcrime.app/privacy
Support URL: https://reportcrime.app/support
Marketing URL: https://reportcrime.app

Keywords: crime, report, anonymous, safety, neighborhood, alert, community

Description: |
  Report crime anonymously and stay informed about safety in your neighborhood.
  
  REPORT ANONYMOUSLY
  • No account required - completely anonymous
  • Capture video or photo evidence
  • Tag location automatically
  • Your identity is never stored
  
  STAY INFORMED
  • TikTok-style feed of nearby reports
  • Interactive map with crime locations
  • Real-time push notifications
  • Filter by crime type and distance
  
  COMMUNITY SAFETY
  • Upvote and comment on reports
  • Flag false reports
  • Help keep your community safe
  
  Your privacy is our priority. We never store personal information 
  or track your identity.
```

**Google Play Console:**
```yaml
App Name: ReportCrime - Anonymous Safety
Short Description: Report crime anonymously. Stay safe. Protect your community.
Content Rating: Mature 17+
Category: News & Magazines / Social
Privacy Policy: https://reportcrime.app/privacy
```

### 3. Privacy Policy & Terms
```markdown
<!-- docs/privacy-policy.md -->

# Privacy Policy

Last updated: [DATE]

## Information We Collect

ReportCrime is designed with privacy as a core principle. We collect 
minimal information necessary to provide our service:

### Device Identifier
- A random, anonymous identifier generated on your device
- Not linked to your Apple ID, Google Account, or any personal information
- Used only to prevent spam and enable features like upvoting

### Location Data
- Used to show nearby crime reports
- Used to tag report locations
- Never stored with personally identifiable information
- You control location sharing through device settings

### Report Content
- Photos and videos you choose to submit
- Crime type and description you provide
- Approximate location of the incident

## Information We Don't Collect
- Name, email, or phone number
- Precise device location history
- Browsing or app usage patterns
- Contact lists or personal files

## Data Retention
- Reports are retained indefinitely for community safety
- You can delete your comments at any time
- Device identifiers can be reset by reinstalling the app

## Third-Party Services
- AWS for hosting and storage
- Firebase for push notifications
- Mapbox for map display

## Contact
privacy@reportcrime.app
```

### 4. Production Configuration

**Environment Variables:**
```bash
# .env.production
NODE_ENV=production
API_BASE_URL=https://api.reportcrime.app
WS_BASE_URL=wss://api.reportcrime.app

# AWS
AWS_REGION=us-east-1
S3_UPLOADS_BUCKET=reportcrime-uploads-prod
S3_MEDIA_BUCKET=reportcrime-media-prod
CDN_DOMAIN=cdn.reportcrime.app

# Database
DATABASE_URL=postgresql://...
REDIS_URL=redis://...

# Firebase
FIREBASE_PROJECT_ID=reportcrime-prod

# Monitoring
SENTRY_DSN=https://...
```

**Flutter Build Configuration:**
```dart
// lib/core/config/environment.dart

enum Environment { dev, staging, prod }

class AppConfig {
  static Environment get environment {
    const env = String.fromEnvironment('ENV', defaultValue: 'dev');
    switch (env) {
      case 'prod': return Environment.prod;
      case 'staging': return Environment.staging;
      default: return Environment.dev;
    }
  }
  
  static String get apiBaseUrl {
    switch (environment) {
      case Environment.prod:
        return 'https://api.reportcrime.app';
      case Environment.staging:
        return 'https://staging-api.reportcrime.app';
      default:
        return 'http://localhost:3000';
    }
  }
}
```

### 5. Monitoring & Analytics

**Error Tracking (Sentry):**
```dart
// lib/main.dart

import 'package:sentry_flutter/sentry_flutter.dart';

Future<void> main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://...@sentry.io/...';
      options.environment = AppConfig.environment.name;
      options.tracesSampleRate = 0.2;
    },
    appRunner: () => runApp(
      ProviderScope(child: ReportCrimeApp()),
    ),
  );
}
```

**Backend Monitoring:**
```javascript
// backend/src/middleware/monitoring.js

const Sentry = require('@sentry/node');

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV,
  tracesSampleRate: 0.1,
});

// Add to Express
app.use(Sentry.Handlers.requestHandler());
app.use(Sentry.Handlers.errorHandler());
```

### 6. Final UI Polish

**Splash Screen:**
```dart
// lib/features/splash/presentation/splash_screen.dart

class SplashScreen extends StatefulWidget {
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    )..forward();
    
    // Navigate after animation
    Future.delayed(Duration(seconds: 2), () {
      Navigator.pushReplacement(
        context,
        FadePageRoute(page: AppShell()),
      );
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF121212),
      body: Center(
        child: FadeTransition(
          opacity: _controller,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield, size: 80, color: Colors.red),
              SizedBox(height: 16),
              Text(
                'ReportCrime',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

**Onboarding (First Launch):**
```dart
// lib/features/onboarding/presentation/onboarding_screen.dart

class OnboardingScreen extends StatefulWidget {
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

// Show permission requests with explanations
// - Location: "To show nearby reports"
// - Camera: "To capture evidence"
// - Notifications: "To alert you of nearby crimes"
```

### 7. Release Checklist

```markdown
## Pre-Release Checklist

### Code
- [ ] All tests passing
- [ ] No compiler warnings
- [ ] Debug logging removed
- [ ] API pointing to production

### iOS
- [ ] Bundle ID correct (com.reportcrime.app)
- [ ] Version number incremented
- [ ] Build number incremented
- [ ] Signing certificate valid
- [ ] Push notification entitlement
- [ ] Location usage descriptions

### Android
- [ ] Package name correct
- [ ] Version code incremented
- [ ] Signing key secured
- [ ] ProGuard/R8 configured
- [ ] Permissions declared

### Backend
- [ ] Production database migrated
- [ ] Environment variables set
- [ ] SSL certificates valid
- [ ] Rate limits configured
- [ ] Monitoring active

### Store
- [ ] Screenshots uploaded
- [ ] Descriptions written
- [ ] Privacy policy URL valid
- [ ] Age rating set
- [ ] Categories selected
```

## Deliverable Checklist
- [ ] App icons in all required sizes
- [ ] Screenshots for all device sizes
- [ ] App Store descriptions written
- [ ] Privacy policy published
- [ ] Terms of service published
- [ ] Production environment configured
- [ ] Sentry error tracking active
- [ ] Splash screen animated
- [ ] Onboarding flow complete
- [ ] All debug code removed
- [ ] Release checklist completed

## Files (10 total)
1. `assets/app_store/ios/*` - iOS store assets
2. `assets/app_store/android/*` - Android store assets
3. `docs/privacy-policy.md` - Privacy policy
4. `docs/terms-of-service.md` - Terms of service
5. `lib/core/config/environment.dart` - Environment config
6. `lib/features/splash/presentation/splash_screen.dart` - Splash
7. `lib/features/onboarding/presentation/onboarding_screen.dart` - Onboarding
8. `.env.production` - Production env vars
9. `backend/.env.production` - Backend prod env
10. `docs/release-checklist.md` - Release checklist
