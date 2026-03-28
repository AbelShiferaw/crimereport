# Privacy Policy

**Effective Date:** 2026-03-28

CrImEreport ("the App") is an anonymous crime reporting platform. This Privacy Policy explains what information the App collects, how it is used, and your rights regarding that information.

## 1. Information We Collect

### 1.1 Anonymous Device Identifier

When you first open the App, a random device identifier is generated and stored locally on your device. This identifier is **hashed** (one-way cryptographic transformation) before being sent to our servers. We cannot reverse this hash to identify your physical device.

### 1.2 Location Data

The App requests location access **only while in use** to:

- Show crime reports near your current location.
- Attach approximate location to reports you submit.

Location coordinates are **rounded to approximately 100 meters** before storage to protect precise user locations.

### 1.3 User-Submitted Content

When you create a report or comment, we store:

- Text content you provide.
- Photos and videos you attach (media).
- The approximate location of the report.
- A timestamp.

### 1.4 Push Notification Tokens

If you enable push notifications, we store a device token to send alerts about nearby crime reports. This token is tied to your anonymous device identifier, not to any personal identity.

## 2. Information We Do NOT Collect

- **Name, email address, or phone number** — the App has no account system.
- **Social media accounts** — no third-party login integrations.
- **Contacts, call logs, or browsing history.**
- **Precise GPS coordinates** — all locations are rounded before storage.

## 3. How We Use Your Information

- **Display crime reports** in your area on a map and in a feed.
- **Send push notifications** for new reports near your location (if enabled).
- **Content moderation** — automated analysis of uploaded media to detect inappropriate content.
- **Abuse prevention** — device-based rate limiting and flagging to prevent spam and false reports.
- **Service improvement** — aggregated, non-identifying analytics to improve App performance.

## 4. Third-Party Services

We use the following third-party services to operate the App:

| Service | Provider | Purpose |
|---------|----------|---------|
| Cloud Hosting & Storage | Amazon Web Services (AWS) | API servers, database, file storage, CDN |
| Content Moderation | AWS Rekognition | Automated detection of inappropriate imagery |
| Maps | Mapbox | Interactive crime map display |

These providers process data on our behalf under their respective privacy policies and data processing agreements. No user data is sold to third parties.

## 5. Data Retention

- **Crime reports** are retained indefinitely to maintain a historical record of reported incidents.
- **Comments** are retained indefinitely unless removed by content moderation.
- **Device identifiers** can be effectively reset by reinstalling the App, which generates a new random identifier.
- **Media files** are stored for the lifetime of the associated report.
- **Push notification tokens** are retained until the App is uninstalled or notifications are disabled.

## 6. Data Security

We implement industry-standard security measures including:

- Encryption in transit (TLS/HTTPS).
- Database credentials managed via AWS Secrets Manager.
- Private network subnets for backend services.
- Web Application Firewall (WAF) with rate limiting.
- No secrets stored in source code.

## 7. Content Moderation

- **Automated moderation:** Uploaded media is analyzed by AWS Rekognition to detect violent, explicit, or otherwise inappropriate content. Content exceeding moderation thresholds is automatically rejected.
- **Community moderation:** Users can flag inappropriate reports and comments. Content that receives flags above a threshold is automatically hidden pending review.

## 8. Children's Privacy

The App is not directed at children under the age of 13. We do not knowingly collect information from children under 13. If you believe a child under 13 has submitted content through the App, please contact us so we can remove it.

## 9. Your Rights

Since the App collects no personally identifiable information, traditional data subject rights (access, correction, deletion of personal data) have limited applicability. However:

- You can **reset your device identifier** at any time by reinstalling the App.
- You can **disable location access** in your device settings.
- You can **disable push notifications** in your device settings.

## 10. Changes to This Policy

We may update this Privacy Policy from time to time. Changes will be posted within the App and on our website. Continued use of the App after changes constitutes acceptance of the updated policy.

## 11. Contact Us

If you have questions or concerns about this Privacy Policy, please contact us at:

**Email:** privacy@reportcrime.app

**Website:** https://reportcrime.app
