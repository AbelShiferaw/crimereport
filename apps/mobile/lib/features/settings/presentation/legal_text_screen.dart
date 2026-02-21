import 'package:flutter/material.dart';
import 'package:crimereport/core/theme/theme.dart';
import 'package:crimereport/core/utils/responsive.dart';

class LegalTextScreen extends StatelessWidget {
  final String title;
  final String body;

  const LegalTextScreen({
    super.key,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppColors.surface,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: Responsive.maxContentWidth,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(
                Responsive.value(
                  context,
                  mobile: AppSpacing.md,
                  tablet: AppSpacing.lg,
                ),
              ),
              child: Text(body, style: AppTypography.bodyMedium),
            ),
          ),
        ),
      ),
    );
  }
}

class LegalContent {
  LegalContent._();

  static const String privacyPolicy = '''
Privacy Policy for CrImEreport

Last updated: February 2026

1. INFORMATION WE COLLECT

CrImEreport is designed to be fully anonymous. We do not collect any personally identifiable information (PII). Specifically:

- No email addresses, phone numbers, or names
- No social media accounts or login credentials
- No contact lists or address books

We generate a random device identifier on first launch. This identifier is cryptographically hashed before transmission, meaning even we cannot trace reports back to specific devices.

2. LOCATION DATA

When you submit a report, GPS coordinates are extracted from the media file's metadata. These coordinates are:

- Rounded to 3 decimal places (~100 meter precision)
- Used only to place the report on the map
- Never linked to your device identifier

We do not track your location when you are not actively submitting a report.

3. MEDIA FILES

Photos and videos you submit are processed as follows:

- All EXIF metadata is stripped on your device before upload
- Media is stored securely and served via CDN
- We do not analyze media content for personal identification

4. DEVICE INFORMATION

We collect minimal device information for app functionality:

- Device type and OS version (for compatibility)
- Push notification token (if notifications are enabled)
- Anonymous usage statistics (crash reports, if opted in)

5. DATA SHARING

We do not sell, trade, or share your data with third parties. Report data (location, media, description) is visible to other app users by design.

6. DATA RETENTION

Reports may be removed if flagged by the community. We retain report data as long as it serves the community's safety interests.

7. YOUR RIGHTS

Since we collect no PII, there is no personal data to request, modify, or delete. If you wish to remove a specific report, use the in-app flagging system.

8. CONTACT

For privacy concerns, contact: privacy@crimereport.app
''';

  static const String termsOfService = '''
Terms of Service for CrImEreport

Last updated: February 2026

1. ACCEPTANCE OF TERMS

By using CrImEreport, you agree to these Terms of Service. If you do not agree, do not use the app.

2. DESCRIPTION OF SERVICE

CrImEreport is an anonymous crime reporting platform that allows users to share and view crime reports in their area. The service is provided "as is" without warranties.

3. USER CONDUCT

You agree NOT to:

- Submit false or misleading reports
- Upload content that violates any laws
- Upload content depicting minors
- Harass, threaten, or intimidate others
- Attempt to identify or dox other users
- Spam or flood the platform with reports
- Circumvent rate limits or abuse prevention measures

4. CONTENT GUIDELINES

All submitted content must:

- Relate to actual observed incidents
- Be captured by the submitting user
- Not contain personally identifiable information of others
- Not contain graphic violence beyond what is necessary to document the incident

5. COMMUNITY MODERATION

Reports that receive multiple flags from the community may be automatically hidden or removed. We reserve the right to remove any content that violates these terms.

6. LIMITATION OF LIABILITY

CrImEreport is not a replacement for emergency services. In case of an emergency, call 911 or your local emergency number. We are not liable for:

- The accuracy of user-submitted reports
- Actions taken based on report information
- Any damages arising from use of the service

7. INTELLECTUAL PROPERTY

By submitting content, you grant CrImEreport a non-exclusive, worldwide license to display and distribute the content within the platform.

8. CHANGES TO TERMS

We may update these terms at any time. Continued use of the app constitutes acceptance of updated terms.

9. CONTACT

For questions about these terms, contact: legal@crimereport.app
''';
}
