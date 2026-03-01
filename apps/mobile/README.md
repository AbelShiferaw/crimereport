# CrImEreport Mobile App

Flutter mobile application for anonymous crime reporting.

## Setup

```bash
cp .env.example .env        # Add your Mapbox access token
flutter pub get
flutter run
```

### Environment Variables

Create a `.env` file in the project root:

```
MAPBOX_ACCESS_TOKEN=pk.your_token_here
```

## Architecture

Feature-based folder structure with Riverpod state management:

```
lib/
├── main.dart                              # Entry point
├── app.dart                               # MaterialApp with dark theme
├── core/
│   ├── constants/                         # Enums, app constants
│   ├── theme/                             # Colors, typography, spacing
│   └── utils/                             # Geo utils, formatters, responsive
├── features/
│   ├── feed/                              # TikTok-style video feed
│   │   ├── data/models/                   # Report, Media, Comment models
│   │   ├── presentation/                  # FeedScreen, widgets, managers
│   │   └── providers/                     # Feed Riverpod providers
│   ├── map/                               # Snap Maps-style crime map
│   │   ├── presentation/                  # MapScreen, LocationFeedScreen
│   │   ├── providers/                     # Map Riverpod providers
│   │   └── services/                      # MarkerImageService
│   ├── submit/                            # Report submission flow
│   │   └── presentation/                  # Camera, preview, details form
│   └── settings/                          # App settings
│       ├── presentation/                  # SettingsScreen, legal text
│       └── providers/                     # Settings Riverpod providers
└── shared/
    ├── data/                              # MockDataService, SampleData
    └── widgets/                           # AppShell, FloatingNavBar, etc.
```

## Key Dependencies

- **State management:** flutter_riverpod
- **Maps:** mapbox_maps_flutter
- **Video:** video_player
- **Camera:** camera, image_picker
- **HTTP:** dio
- **WebSocket:** socket_io_client
- **Location:** geolocator, permission_handler
- **Storage:** shared_preferences, flutter_secure_storage

## Current Status

The app is fully built with mock data (Milestones 1-13 complete). Backend integration (replacing MockDataService with real API calls) is planned for Milestones 25-28.
