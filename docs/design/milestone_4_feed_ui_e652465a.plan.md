---
name: Milestone 4 Feed UI
overview: Add TikTok-style overlay UI including side action buttons, info bar, double-tap heart animation, video progress bar, and long-press fast-forward gesture.
todos:
  - id: m4-gesture-controls
    content: Create VideoGestureControls widget for long-press 2x fast-forward
    status: pending
  - id: m4-progress-bar
    content: Create VideoProgressBar widget with seek functionality
    status: pending
  - id: m4-action-buttons
    content: Create FeedActionButtons widget (upvote, comment, flag)
    status: pending
  - id: m4-info-bar
    content: Create FeedInfoBar widget with crime badge and description
    status: pending
  - id: m4-heart-animation
    content: Create DoubleTapLikeOverlay with heart animation
    status: pending
  - id: m4-integrate
    content: Update FeedVideoItem to integrate all overlay components
    status: pending
---

# Milestone 4: TikTok Feed - Overlay UI (Enhanced)

## Goal

Transform the basic video feed into a polished TikTok-like experience with interactive overlays, video controls, and satisfying animations.

## Dependencies

Requires **Milestone 3** complete (video feed with autoplay working).

---

## Complete Gesture Map

| Gesture | Action |
|---------|--------|
| **Tap** | Pause/play (existing) |
| **Double-tap** | Upvote + heart animation |
| **Long-press anywhere** | 2x speed fast-forward |
| **Drag progress bar** | Seek to position |

---

## UI Layout

```
┌─────────────────────────────┐
│                             │
│      [LONG-PRESS: ⏩ 2x]    │  ← Hold anywhere to fast-forward
│                             │
│         VIDEO               │
│      (full screen)          │
│                             │
│                        ┌───┐│
│                        │ ▲ ││  ← Upvote (123)
│                        ├───┤│
│                        │ 💬││  ← Comments (45)
│                        ├───┤│
│                        │ ⚑ ││  ← Flag
│                        └───┘│
│  ┌──────────────────────┐   │
│  │ 🔴 THEFT             │   │  ← Crime badge (color-coded)
│  │ Someone broke into..  │   │  ← Description (2 lines max)
│  │ 📍 0.3 mi • 2h ago   │   │  ← Distance & time
│  └──────────────────────┘   │
│  ════════════════════════   │  ← Progress bar (3px, seekable)
│                             │
│  ╭───────────────────────╮  │
│  │  🏠   🗺️   ➕   ⚙️   │  │  ← Floating nav bar (blurred bg)
│  ╰───────────────────────╯  │
│          safe area          │
└─────────────────────────────┘
```

**Layer order (bottom to top):**
1. Full-screen video (extends behind everything)
2. Info bar (positioned above nav bar, ~100px from bottom)
3. Progress bar (just above nav bar, ~80px from bottom)
4. Floating nav bar (bottom with safe area padding)
5. Action buttons (right side, clears nav bar)

---

## Files to Create/Modify (6 total)

| File | Action | Description |
|------|--------|-------------|
| `feed_video_item.dart` | Modify | Add Stack layout, integrate all overlays |
| `feed_action_buttons.dart` | Create | Upvote, comment, flag column |
| `feed_info_bar.dart` | Create | Crime badge, description, time/distance |
| `double_tap_like_overlay.dart` | Create | Heart animation on double-tap |
| `video_progress_bar.dart` | Create | Thin seekable progress indicator |
| `video_gesture_controls.dart` | Create | Long-press for 2x fast-forward |

---

## Implementation Details

### 1. Video Gesture Controls (NEW)

Long-press anywhere triggers 2x playback speed:

```dart
// lib/features/feed/presentation/widgets/video_gesture_controls.dart
class VideoGestureControls extends StatefulWidget {
  final VideoPlayerController controller;
  final Widget child;
}
```

- **Long-press:** Sets 2x playback speed, shows "⏩ 2x" indicator centered on screen
- **Release:** Returns to 1x speed, indicator fades out
- Coexists with tap (pause) and double-tap (like) gestures

### 2. Video Progress Bar (NEW)

Thin progress indicator positioned above the floating nav bar:

```dart
// lib/features/feed/presentation/widgets/video_progress_bar.dart
class VideoProgressBar extends StatelessWidget {
  final VideoPlayerController controller;
  final bool showOnPause; // Auto-show when paused
}
```

- **Height:** 3px normally, 6px when dragging
- **Color:** White progress on semi-transparent track
- **Seek:** Drag to position, shows timestamp preview
- **Position:** Bottom of video area, above floating nav bar (~80px from screen bottom)

### 3. Feed Item with Overlay Stack

```dart
// lib/features/feed/presentation/widgets/feed_video_item.dart (updated)
@override
Widget build(BuildContext context) {
  // Get nav bar height to position overlays correctly
  final bottomPadding = 80.0; // Nav bar height + safe area
  
  return Stack(
    fit: StackFit.expand,
    children: [
      // Video layer (full screen)
      _buildVideoPlayer(),
      
      // Long-press gesture for 2x speed
      VideoGestureControls(
        controller: _controller,
        child: DoubleTapLikeOverlay(
          onDoubleTap: _handleUpvote,
          child: GestureDetector(
            onTap: _togglePlayPause,
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
      
      // Side action buttons (right side, above nav bar)
      Positioned(
        right: 12,
        bottom: bottomPadding + 100, // Clear nav bar
        child: FeedActionButtons(
          report: widget.report,
          onUpvote: _handleUpvote,
          onComment: widget.onCommentTap,
          onFlag: _handleFlag,
        ),
      ),
      
      // Bottom info bar (above progress bar)
      Positioned(
        left: 16,
        right: 80,
        bottom: bottomPadding + 20, // Above progress bar
        child: FeedInfoBar(report: widget.report),
      ),
      
      // Progress bar (just above nav bar)
      Positioned(
        left: 0,
        right: 0,
        bottom: bottomPadding,
        child: VideoProgressBar(controller: _controller),
      ),
    ],
  );
}
```

### 4. Action Buttons

```dart
// lib/features/feed/presentation/widgets/feed_action_buttons.dart
class FeedActionButtons extends StatelessWidget {
  final Report report;
  final VoidCallback? onUpvote;
  final VoidCallback? onComment;
  final VoidCallback? onFlag;
  
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: Icons.arrow_upward_rounded,
          label: _formatCount(report.upvotes),
          isActive: false, // TODO: track user upvotes
          activeColor: Colors.red,
          onTap: onUpvote,
        ),
        const SizedBox(height: 20),
        _ActionButton(
          icon: Icons.chat_bubble_outline_rounded,
          label: _formatCount(report.commentCount),
          onTap: onComment,
        ),
        const SizedBox(height: 20),
        _ActionButton(
          icon: Icons.flag_outlined,
          label: 'Report',
          onTap: onFlag,
        ),
      ],
    );
  }
  
  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color? activeColor;
  final VoidCallback? onTap;
  
  const _ActionButton({
    required this.icon,
    required this.label,
    this.isActive = false,
    this.activeColor,
    this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(77), // 0.3 opacity
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isActive ? (activeColor ?? Colors.white) : Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
            ),
          ),
        ],
      ),
    );
  }
}
```

### 5. Info Bar

```dart
// lib/features/feed/presentation/widgets/feed_info_bar.dart
class FeedInfoBar extends StatelessWidget {
  final Report report;
  
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Crime type badge (color-coded)
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: report.type.color, // Uses enum color
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            report.type.displayName.toUpperCase(),
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        
        // Description (max 2 lines)
        Text(
          report.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 1.3,
            shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
          ),
        ),
        const SizedBox(height: 6),
        
        // Location and time
        Row(
          children: [
            Icon(Icons.location_on, size: 14, color: Colors.white70),
            const SizedBox(width: 4),
            Text(
              '${report.distanceKm?.toStringAsFixed(1) ?? '?'} mi',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(width: 12),
            Icon(Icons.access_time, size: 14, color: Colors.white70),
            const SizedBox(width: 4),
            Text(
              report.timeAgo,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}
```

### 6. Double-Tap Heart Animation

```dart
// lib/features/feed/presentation/widgets/double_tap_like_overlay.dart
class DoubleTapLikeOverlay extends StatefulWidget {
  final Widget child;
  final VoidCallback onDoubleTap;
  
  @override
  State<DoubleTapLikeOverlay> createState() => _DoubleTapLikeOverlayState();
}

class _DoubleTapLikeOverlayState extends State<DoubleTapLikeOverlay>
    with SingleTickerProviderStateMixin {
  
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  
  Offset? _tapPosition;
  bool _showHeart = false;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );
    
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.4), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 50),
    ]).animate(_controller);
    
    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_controller);
  }
  
  void _handleDoubleTap(TapDownDetails details) {
    setState(() {
      _tapPosition = details.localPosition;
      _showHeart = true;
    });
    
    _controller.forward(from: 0).then((_) {
      if (mounted) setState(() => _showHeart = false);
    });
    
    widget.onDoubleTap();
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: _handleDoubleTap,
      onDoubleTap: () {}, // Required for onDoubleTapDown to work
      child: Stack(
        children: [
          widget.child,
          if (_showHeart && _tapPosition != null)
            Positioned(
              left: _tapPosition!.dx - 40,
              top: _tapPosition!.dy - 40,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Opacity(
                    opacity: _opacityAnimation.value,
                    child: Transform.scale(
                      scale: _scaleAnimation.value,
                      child: Icon(
                        Icons.favorite,
                        color: Colors.red,
                        size: 80,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
```

---

## Visual Specifications

| Element | Style |
|---------|-------|
| Progress bar | 3px height, white on rgba(255,255,255,0.3) |
| Fast-forward indicator | "⏩ 2x" centered, semi-transparent bg |
| Action buttons | 48x48 circles, rgba(0,0,0,0.3) bg |
| Text shadows | Shadow(blurRadius: 4, color: black54) |
| Crime badge | Rounded rect, type.color background |
| Bottom padding | ~80px to clear floating nav bar |

---

## Deliverable Checklist

- [ ] Side action buttons (upvote, comment, flag)
- [ ] Formatted counts (1.2K, 3.5M)
- [ ] Bottom info bar with crime badge
- [ ] Description (2 lines max)
- [ ] Distance and time display
- [ ] Double-tap heart animation
- [ ] Video progress bar (seekable)
- [ ] Long-press anywhere = 2x speed
- [ ] Visual feedback for gestures
- [ ] All text readable over video
- [ ] Overlays positioned above floating nav bar

---

## Estimated Effort

| Component | Time |
|-----------|------|
| Action buttons | 30 min |
| Info bar | 30 min |
| Double-tap heart | 45 min |
| Progress bar | 45 min |
| Gesture controls | 30 min |
| Integration + polish | 30 min |
| **Total** | ~3.5 hours |
