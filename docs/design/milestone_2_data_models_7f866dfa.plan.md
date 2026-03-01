# Milestone 2: Data Models & Mock Data (Alternate Plan)

## Status
Completed — merged with `milestone_2_models_9c89c29a.plan.md`

## Note
This was a second planning document for the same milestone. Both plans were implemented as a single body of work. See `milestone_2_models_9c89c29a.plan.md` for the complete post-implementation documentation covering all models, enums, sample data, and the mock data service.

## Key Differences from This Plan vs What Was Built

- The architecture diagram in this plan (mermaid flowchart) accurately describes the dependency flow: enums → models → SampleData → MockDataService → FeedScreen.
- This plan specified `ReportType` enums with `displayName` and `color` — both were implemented exactly as planned, pulling colors from `AppColors.crimeX` constants.
- The `MockDataService` singleton was implemented as `MockDataService.instance` (static field) rather than `MockDataService()` (factory constructor), a minor API difference.
- Distance calculation uses `GeoUtils.distanceKm` (Haversine formula) in a dedicated utility class at `lib/core/utils/geo_utils.dart`, rather than being inline in the mock service.
- All 6 files listed in this plan were created at the specified paths.
