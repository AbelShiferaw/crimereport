# Milestone 31: App Store Submission Prep

## Current State

The app builds for both platforms and the submission guide is written, but a comprehensive audit revealed **11 frontend-backend contract mismatches** that cause crashes, 400 errors, or silent data corruption. These must be fixed before the app can function correctly in production, let alone pass store review.

---

## Phase 1: Frontend-Backend Contract Fixes

### 1. Report.fromJson `lat`/`lng` naming (THE upload bug)

**Problem:** `Report.fromJson` reads `json['latitude']` / `json['longitude']` but the backend returns `lat` / `lng`. Every report parse throws a TypeError, which is why uploads show "Upload failed" -- the report is created (201) but the response can't be parsed.

**Files:**
- `apps/mobile/lib/features/feed/data/models/report.dart` lines 93-94: change `'latitude'` to `'lat'`, `'longitude'` to `'lng'`
- Same file line 110-111 in `toJson`: change `'latitude'` to `'lat'`, `'longitude'` to `'lng'`

### 2. Crime types alignment (6 mismatches)

**Problem:** Flutter `ReportType` enum has 7 types, backend has 11. Names don't match for `drug_activity`. The `disturbance` type doesn't exist on the backend (confirmed 400 error).

**Files:**
- `apps/mobile/lib/core/constants/enums.dart`: Replace enum with all 11 backend types. Add a `apiName` getter for serialization (since `drug_activity` has an underscore but Dart enum name would be `drugActivity`). Add a `fromApiName` static method for parsing.
- `apps/mobile/lib/features/feed/data/models/report.dart` line 91: use `ReportType.fromApiName(json['type'])` instead of `byName`
- `apps/mobile/lib/shared/data/websocket/ws_events.dart` line 40: same change
- `apps/mobile/lib/features/submit/presentation/report_details_screen.dart` line 105: send `_selectedType!.apiName` instead of `.name`
- `apps/mobile/lib/core/theme/colors.dart`: add colors for the 5 new crime types

### 3. Report.description should be nullable

**Problem:** `json['description'] as String` crashes if backend returns `null` (description is optional in the Zod schema).

**File:** `apps/mobile/lib/features/feed/data/models/report.dart` -- change field to `String?`, update `fromJson` to `as String?`.

### 4. Media.width/height should be nullable

**Problem:** `json['width'] as int` crashes if backend returns `null` (width/height are nullable in the DB).

**File:** `apps/mobile/lib/features/feed/data/models/media.dart` -- change to `int?`, update `fromJson` and `aspectRatio` getter to handle nulls.

### 5. Push notification contract (3 sub-fixes)

**5a. Registration (`_registerToken` in `apps/mobile/lib/shared/providers/notification_providers.dart`):**

Flutter sends: `{ 'fcm_token': token, 'platform': _platformName, 'lat': null, 'lng': null, 'radius_km': radius }`

Backend `registerDeviceSchema` expects: `{ device_id: string, fcm_token: string, platform: 'ios'|'android', lat: number(-90..90), lng: number(-180..180) }`

Mismatches: (1) missing `device_id`, (2) `lat`/`lng` are null but schema requires non-nullable numbers, (3) `radius_km` is not in the schema.

**Fix:** Add `device_id` from `anonymousIdProvider`, get real lat/lng from geolocator (or a location provider), remove `radius_km`.

**5b. Unregister (`setPushNotificationsEnabled` in `apps/mobile/lib/features/settings/providers/settings_providers.dart`):**

Flutter sends: `DELETE /api/v1/notifications/unregister` with no body.
Backend `unregisterDeviceSchema` requires: `{ device_id: string }`.

**Fix:** Update `ApiClient.delete` in `apps/mobile/lib/shared/data/api/api_client.dart` to accept an optional `data` parameter. Include `device_id` in the DELETE request body.

**5c. Radius update (`setNotificationRadius` in `apps/mobile/lib/features/settings/providers/settings_providers.dart`):**

Flutter sends the same broken registration payload to `POST /register`.
It should use `PUT /api/v1/notifications/preferences` with `updatePreferencesSchema`: `{ device_id, radius (int, meters 1000-50000) }`.

**Fix:** Change to `PUT /preferences`, send `device_id`, convert `radiusKm` to meters as `radius`, remove all other fields.

### 6. Deep link handler

**Problem:** In `apps/mobile/lib/shared/services/deep_link_handler.dart`, `navigator.pushNamed('/report/$reportId')` is called but `MaterialApp` in `apps/mobile/lib/app.dart` has no named routes defined. Tapping a push notification throws a route error.

**Fix:** Replace `pushNamed` with imperative `Navigator.push` using a `MaterialPageRoute`.

### 7. Block submission without GPS location

**Problem:** If location fails, the app silently tags reports at San Francisco (37.7749, -122.4194) coordinates. Reports end up in the wrong city's feed.

**File:** `apps/mobile/lib/features/submit/presentation/report_details_screen.dart` -- update `_isFormValid` to require `_location != null`. Remove the San Francisco fallback from `_submit()`. Update the submit button to show "Location required" when disabled due to missing location.

---

## Phase 2: Contract Tests

### 8. Add `contract.test.ts` to integration tests

Create `integration-tests/src/contract.test.ts` that validates every backend response shape matches what the Flutter models expect. This runs in CI after every deploy and catches any future drift.

**What it tests:**
- `POST /reports` response has `lat`, `lng` (not `latitude`/`longitude`), `device_id`, `type` is one of CRIME_TYPES, `description` can be null, `status`, `upvotes`, `comment_count`, `created_at`
- `GET /reports/:id` response includes `media[]` with `type`, `url`, nullable `width`/`height`/`thumbnail_url`/`duration_ms`
- `GET /reports/:id/comments` response has `data[]` with `id`, `report_id`, `device_id`, `content`, `upvotes`, `created_at`
- `POST /reports/:id/upload` response has `upload_url`, `media_key`, `expires_in`
- `POST /notifications/register` accepts the corrected payload
- `PUT /notifications/preferences` accepts `device_id`, `radius`, `types`, `enabled`
- `DELETE /notifications/unregister` accepts `device_id` in body

**File:** `integration-tests/src/contract.test.ts` (new)

**Backend Zod schemas for reference** (`backend/api/src/validators/`):
- `CRIME_TYPES`: `theft, assault, vandalism, robbery, burglary, suspicious, shooting, carjacking, harassment, drug_activity, other`
- `registerDeviceSchema`: `{ device_id, fcm_token, platform: 'ios'|'android', lat: number, lng: number }`
- `unregisterDeviceSchema`: `{ device_id }`
- `updatePreferencesSchema`: `{ device_id, enabled?: boolean, radius?: int(1000-50000), types?: CRIME_TYPES[] }`

---

## Phase 3: iOS Build Fixes (manual -- do in Xcode locally)

### 9. iOS Push entitlements

Create `apps/mobile/ios/Runner/Runner.entitlements` with `aps-environment` and wire it in `project.pbxproj`.

### 10. PrivacyInfo.xcprivacy in build resources

Add to Runner target's "Copy Bundle Resources" in `project.pbxproj`.

### 11. Permission string consistency

Update `Info.plist` usage descriptions from "ReportCrime" to "CrimeReport".

---

## Phase 4: Documentation

### 12. Fix milestone docs

Update `docs/design/milestones/milestone_31_app_store.plan.md` bundle ID references to `com.report.reportcrime`. Update `PARALLEL_TASKS.md` and `README.md` status tables.

---

## What Remains Manual

- Enable Push Notifications capability in Xcode Signing & Capabilities UI
- Create Android upload keystore + `key.properties`
- Capture screenshots on device/simulator
- Host privacy policy at a public URL
- Configure App Store Connect and Google Play Console listings
- Build, archive, upload, and submit
