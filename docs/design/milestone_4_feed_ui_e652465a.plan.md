---
name: Milestone 4 Feed UI
overview: Add TikTok-style overlay UI on top of videos including side action buttons (upvote, comment, flag), bottom info bar with crime details, and a double-tap heart animation for upvoting.
todos:
  - id: m4-stack
    content: Update FeedVideoItem with Stack layout for overlays
    status: pending
    dependencies:
      - m3-verify
  - id: m4-buttons
    content: Create FeedActionButtons widget (upvote, comment, flag)
    status: pending
    dependencies:
      - m4-stack
  - id: m4-info
    content: Create FeedInfoBar with crime type, description, distance/time
    status: pending
    dependencies:
      - m4-stack
  - id: m4-heart
    content: Implement DoubleTapLikeOverlay with heart animation
    status: pending
    dependencies:
      - m4-stack
  - id: m4-polish
    content: Add text shadows, count formatting, color-coded badges
    status: pending
    dependencies:
      - m4-buttons
      - m4-info
  - id: m4-verify
    content: Test all overlay interactions work correctly
    status: pending
    dependencies:
      - m4-heart
      - m4-polish
---

# Milestone 4: TikTok Feed - Overlay UI

## Goal
Transform the basic video feed into a polished TikTok-like experience with interactive overlays, action buttons, and satisfying animations.

## Dependencies
Requires **Milestone 3** complete (video feed with autoplay working).

## UI Layout

```
┌─────────────────────────────┐
│                             │
│                             │
│         VIDEO               │
│                             │
│                        ┌───┐│
│                        │ ▲ ││  <- Upvote
│                        │123││
│                        ├───┤│
│                        │ 💬││  <- Comments
│                        │ 45││
│                        ├───┤│
│                        │ ⚑ ││  <- Flag
│                        └───┘│
│  ┌──────────────────────┐   │
│  │ 🔴 THEFT             │   │  <- Crime type badge
│  │ Someone broke into..  │   │  <- Description
│  │ 📍 0.3 mi • 2h ago   │   │  <- Distance & time
│  └──────────────────────┘   │
└─────────────────────────────┘
```

## Core Implementation

### 1. Feed Item with Overlay
Wrap video in Stack with overlay widgets:

```dart
// lib/features/feed/presentation/widgets/feed_video_item.dart (updated)
class FeedVideoItem extends StatefulWidget {
  final Report report;
  final bool isActive;
  final VoidCallback? onCommentTap;
  
  // ...
}

@override
Widget build(BuildContext context) {
  return Stack(
    fit: StackFit.expand,
    children: [
      // Video layer
      _buildVideoPlayer(),
      
      // Double-tap detection + heart animation
      DoubleTapLikeOverlay(
        onDoubleTap: _handleUpvote,
        child: Container(color: Colors.transparent),
      ),
      
      // Side action buttons (right side)
      Positioned(
        right: 12,
        bottom: 120,
        child: FeedActionButtons(
          report: widget.report,
          onUpvote: _handleUpvote,
          onComment: widget.onCommentTap,
          onFlag: _handleFlag,
        ),
      ),
      
      // Bottom info bar
      Positioned(
        left: 16,
        right: 80,
        bottom: 24,
        child: FeedInfoBar(report: widget.report),
      ),
    ],
  );
}
```

### 2. Side Action Buttons

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
        // Upvote button
        _ActionButton(
          icon: Icons.arrow_upward_rounded,
          label: _formatCount(report.upvotes),
          isActive: false, // TODO: track user upvotes
          activeColor: Colors.red,
          onTap: onUpvote,
        ),
        const SizedBox(height: 20),
        
        // Comment button
        _ActionButton(
          icon: Icons.chat_bubble_outline_rounded,
          label: _formatCount(report.commentCount),
          onTap: onComment,
        ),
        const SizedBox(height: 20),
        
        // Flag button
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
              color: Colors.black.withOpacity(0.3),
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

### 3. Bottom Info Bar

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
        // Crime type badge
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _getTypeColor(report.type),
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
              _formatTimeAgo(report.createdAt),
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
  
  Color _getTypeColor(ReportType type) {
    switch (type) {
      case ReportType.theft: return Colors.orange;
      case ReportType.assault: return Colors.red;
      case ReportType.vandalism: return Colors.purple;
      case ReportType.suspicious: return Colors.amber;
      case ReportType.drugActivity: return Colors.green;
      case ReportType.disturbance: return Colors.blue;
      default: return Colors.grey;
    }
  }
}
```

### 4. Double-Tap Heart Animation

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
      setState(() => _showHeart = false);
    });
    
    widget.onDoubleTap();
  }
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: _handleDoubleTap,
      onDoubleTap: () {}, // Required for onDoubleTapDown
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

## Visual Polish

| Element | Style |
|---------|-------|
| Text shadows | All text has subtle black shadow for readability |
| Button backgrounds | Semi-transparent black circles |
| Crime badges | Color-coded by type |
| Heart animation | Scale bounce + fade out |
| Counts | Formatted (1.2K, 3.5M) |

## Deliverable Checklist

- [ ] Side action buttons visible (upvote, comment, flag)
- [ ] Upvote count displays and formats large numbers
- [ ] Comment count displays
- [ ] Flag button visible
- [ ] Bottom info bar shows crime type badge
- [ ] Description shows (max 2 lines, ellipsis)
- [ ] Distance and time ago display
- [ ] Crime type badges are color-coded
- [ ] Double-tap anywhere shows heart animation
- [ ] Heart animates (scale up, bounce, fade)
- [ ] All text readable over any video (shadows)
- [ ] Buttons tappable, trigger callbacks

## Files to Create/Modify (5 total)

1. `lib/features/feed/presentation/widgets/feed_video_item.dart` - Modify (add Stack)
2. `lib/features/feed/presentation/widgets/feed_action_buttons.dart` - Create
3. `lib/features/feed/presentation/widgets/feed_info_bar.dart` - Create
4. `lib/features/feed/presentation/widgets/double_tap_like_overlay.dart` - Create
5. `lib/core/constants/enums.dart` - Modify (add displayName extension)

---

**Approve Milestone 4?** Then I'll show you Milestone 5 (Mapbox Map - Basic Setup).