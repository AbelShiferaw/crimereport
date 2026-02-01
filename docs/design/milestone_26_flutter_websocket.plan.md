# Milestone 26: Flutter ↔ WebSocket

## Goal
Connect Flutter app to WebSocket server for real-time updates (new reports appear live on feed/map).

## Dependencies
Requires **Milestone 23** (WebSocket server) and **Milestone 25** (REST integration).

## Implementation

### 1. WebSocket Service
```dart
// lib/shared/data/websocket/websocket_service.dart

import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WebSocketService {
  IO.Socket? _socket;
  final String _baseUrl;
  final String _deviceId;
  
  final _reportStreamController = StreamController<ReportEvent>.broadcast();
  final _commentStreamController = StreamController<CommentEvent>.broadcast();
  
  Stream<ReportEvent> get reportStream => _reportStreamController.stream;
  Stream<CommentEvent> get commentStream => _commentStreamController.stream;
  
  WebSocketService({required String baseUrl, required String deviceId})
      : _baseUrl = baseUrl,
        _deviceId = deviceId;
  
  void connect() {
    _socket = IO.io(_baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'auth': {'deviceId': _deviceId},
    });
    
    _setupListeners();
    _socket!.connect();
  }
  
  void _setupListeners() {
    _socket!.onConnect((_) {
      print('WebSocket connected');
    });
    
    _socket!.onDisconnect((_) {
      print('WebSocket disconnected');
    });
    
    _socket!.onConnectError((error) {
      print('WebSocket connection error: $error');
    });
    
    // Listen for new reports
    _socket!.on('report:new', (data) {
      final event = ReportEvent.fromJson(data['data']);
      _reportStreamController.add(event);
    });
    
    // Listen for upvote updates
    _socket!.on('report:upvote', (data) {
      final event = UpvoteEvent.fromJson(data['data']);
      _reportStreamController.add(event);
    });
    
    // Listen for new comments
    _socket!.on('comment:new', (data) {
      final event = CommentEvent.fromJson(data['data']);
      _commentStreamController.add(event);
    });
    
    // Listen for media ready
    _socket!.on('media:ready', (data) {
      final event = MediaReadyEvent.fromJson(data['data']);
      _reportStreamController.add(event);
    });
  }
  
  void subscribeToLocation(double lat, double lng, {int radius = 10000}) {
    _socket?.emit('subscribe:location', {
      'lat': lat,
      'lng': lng,
      'radius': radius,
    });
  }
  
  void unsubscribeFromLocation() {
    _socket?.emit('unsubscribe:location');
  }
  
  void subscribeToReport(String reportId) {
    _socket?.emit('subscribe:report', reportId);
  }
  
  void unsubscribeFromReport(String reportId) {
    _socket?.emit('unsubscribe:report', reportId);
  }
  
  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }
  
  void dispose() {
    disconnect();
    _reportStreamController.close();
    _commentStreamController.close();
  }
}

// Provider
final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  final deviceId = ref.watch(deviceIdProvider).value ?? '';
  final service = WebSocketService(
    baseUrl: AppConstants.wsBaseUrl,
    deviceId: deviceId,
  );
  
  ref.onDispose(() => service.dispose());
  
  return service;
});
```

### 2. Event Models
```dart
// lib/shared/data/websocket/events.dart

abstract class ReportEvent {
  factory ReportEvent.fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    switch (type) {
      case 'NEW_REPORT':
        return NewReportEvent.fromJson(json);
      case 'UPVOTE_UPDATE':
        return UpvoteEvent.fromJson(json);
      case 'MEDIA_READY':
        return MediaReadyEvent.fromJson(json);
      default:
        throw Exception('Unknown event type: $type');
    }
  }
}

class NewReportEvent implements ReportEvent {
  final String id;
  final String type;
  final double latitude;
  final double longitude;
  final String? thumbnailUrl;
  final DateTime createdAt;
  
  NewReportEvent({
    required this.id,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.thumbnailUrl,
    required this.createdAt,
  });
  
  factory NewReportEvent.fromJson(Map<String, dynamic> json) {
    return NewReportEvent(
      id: json['id'],
      type: json['type'],
      latitude: json['latitude'].toDouble(),
      longitude: json['longitude'].toDouble(),
      thumbnailUrl: json['thumbnailUrl'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

class UpvoteEvent implements ReportEvent {
  final String reportId;
  final int upvotes;
  
  UpvoteEvent({required this.reportId, required this.upvotes});
  
  factory UpvoteEvent.fromJson(Map<String, dynamic> json) {
    return UpvoteEvent(
      reportId: json['reportId'],
      upvotes: json['upvotes'],
    );
  }
}

class CommentEvent {
  final String id;
  final String reportId;
  final String content;
  final String anonymousId;
  final bool isReporter;
  
  CommentEvent({
    required this.id,
    required this.reportId,
    required this.content,
    required this.anonymousId,
    required this.isReporter,
  });
  
  factory CommentEvent.fromJson(Map<String, dynamic> json) {
    return CommentEvent(
      id: json['id'],
      reportId: json['reportId'],
      content: json['content'],
      anonymousId: json['anonymousId'],
      isReporter: json['isReporter'] ?? false,
    );
  }
}
```

### 3. Real-Time Feed Provider
```dart
// lib/features/feed/providers/realtime_feed_provider.dart

final realtimeFeedProvider = StateNotifierProvider<RealtimeFeedNotifier, List<Report>>((ref) {
  final wsService = ref.watch(webSocketServiceProvider);
  final location = ref.watch(userLocationProvider).value;
  
  final notifier = RealtimeFeedNotifier(wsService);
  
  // Subscribe to location when available
  if (location != null) {
    wsService.connect();
    wsService.subscribeToLocation(location.latitude, location.longitude);
    
    // Listen for new reports
    wsService.reportStream.listen((event) {
      if (event is NewReportEvent) {
        notifier.addNewReport(event);
      } else if (event is UpvoteEvent) {
        notifier.updateUpvotes(event.reportId, event.upvotes);
      }
    });
  }
  
  return notifier;
});

class RealtimeFeedNotifier extends StateNotifier<List<Report>> {
  final WebSocketService _wsService;
  
  RealtimeFeedNotifier(this._wsService) : super([]);
  
  void setReports(List<Report> reports) {
    state = reports;
  }
  
  void addNewReport(NewReportEvent event) {
    // Add to beginning of list
    state = [
      Report(
        id: event.id,
        type: ReportType.values.firstWhere((t) => t.name == event.type),
        latitude: event.latitude,
        longitude: event.longitude,
        media: event.thumbnailUrl != null
            ? [Media(thumbnailUrl: event.thumbnailUrl)]
            : [],
        createdAt: event.createdAt,
        // Partial data - will be filled when scrolled to
      ),
      ...state,
    ];
  }
  
  void updateUpvotes(String reportId, int upvotes) {
    state = state.map((r) {
      if (r.id == reportId) {
        return r.copyWith(upvotes: upvotes);
      }
      return r;
    }).toList();
  }
}
```

### 4. Real-Time Comments Provider
```dart
// lib/features/feed/providers/realtime_comments_provider.dart

final realtimeCommentsProvider = StateNotifierProvider.family<
    RealtimeCommentsNotifier, List<Comment>, String>((ref, reportId) {
  final wsService = ref.watch(webSocketServiceProvider);
  
  // Subscribe to this report's comments
  wsService.subscribeToReport(reportId);
  
  final notifier = RealtimeCommentsNotifier();
  
  // Listen for new comments
  wsService.commentStream
      .where((event) => event.reportId == reportId)
      .listen((event) {
    notifier.addComment(Comment(
      id: event.id,
      reportId: event.reportId,
      content: event.content,
      anonymousId: event.anonymousId,
      isReporter: event.isReporter,
      createdAt: DateTime.now(),
      upvotes: 0,
    ));
  });
  
  ref.onDispose(() {
    wsService.unsubscribeFromReport(reportId);
  });
  
  return notifier;
});

class RealtimeCommentsNotifier extends StateNotifier<List<Comment>> {
  RealtimeCommentsNotifier() : super([]);
  
  void setComments(List<Comment> comments) {
    state = comments;
  }
  
  void addComment(Comment comment) {
    state = [...state, comment];
  }
}
```

### 5. Update Feed Screen for Real-Time
```dart
// lib/features/feed/presentation/feed_screen.dart (updated)

class FeedScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  @override
  void initState() {
    super.initState();
    // Connect WebSocket when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(webSocketServiceProvider).connect();
    });
  }
  
  @override
  Widget build(BuildContext context) {
    final location = ref.watch(userLocationProvider);
    
    return location.when(
      data: (pos) {
        // Initial load from API
        final apiReports = ref.watch(
          nearbyReportsProvider(LatLng(pos.latitude, pos.longitude))
        );
        
        // Real-time updates
        final realtimeNotifier = ref.watch(realtimeFeedProvider.notifier);
        
        return apiReports.when(
          data: (reports) {
            // Merge API data with real-time updates
            realtimeNotifier.setReports(reports);
            final displayReports = ref.watch(realtimeFeedProvider);
            
            return Stack(
              children: [
                FeedVideoList(reports: displayReports),
                
                // New report indicator
                if (displayReports.isNotEmpty && 
                    displayReports.first.createdAt.isAfter(
                      DateTime.now().subtract(Duration(seconds: 30))
                    ))
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 50,
                    left: 0,
                    right: 0,
                    child: NewReportBanner(
                      onTap: () => _scrollToTop(),
                    ),
                  ),
              ],
            );
          },
          loading: () => FeedLoadingSkeleton(),
          error: (e, _) => ErrorView(message: 'Failed to load reports'),
        );
      },
      loading: () => Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: 'Location required'),
    );
  }
}
```

### 6. New Report Banner
```dart
// lib/features/feed/presentation/widgets/new_report_banner.dart

class NewReportBanner extends StatelessWidget {
  final VoidCallback onTap;
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 100),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.arrow_upward, color: Colors.white, size: 16),
            SizedBox(width: 4),
            Text(
              'New Report',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

## WebSocket Flow
```
App Start
    │
    ▼
Connect WebSocket
    │
    ▼
Subscribe to Location
    │
    ├─────────────────────────────────┐
    │                                 │
    ▼                                 ▼
Load Initial Data (REST)     Receive Real-Time Events
    │                                 │
    └──────────┬──────────────────────┘
               │
               ▼
        Merged Feed State
               │
               ▼
          UI Updates
```

## Deliverable Checklist
- [ ] WebSocket connects on app start
- [ ] Location subscription works
- [ ] New reports appear at top of feed
- [ ] "New Report" banner shows for recent
- [ ] Tapping banner scrolls to top
- [ ] Upvote counts update in real-time
- [ ] Map markers update with new reports
- [ ] Comments appear in real-time
- [ ] Reconnection works after disconnect
- [ ] Clean disconnect on app background

## Files (6 total)
1. `lib/shared/data/websocket/websocket_service.dart` - Create
2. `lib/shared/data/websocket/events.dart` - Create
3. `lib/features/feed/providers/realtime_feed_provider.dart` - Create
4. `lib/features/feed/providers/realtime_comments_provider.dart` - Create
5. `lib/features/feed/presentation/feed_screen.dart` - Update
6. `lib/features/feed/presentation/widgets/new_report_banner.dart` - Create
