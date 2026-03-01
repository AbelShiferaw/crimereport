# Milestone 4: TikTok Feed - Overlay UI

## Status
Completed

## Goal
Transform the basic video feed into a polished TikTok-like experience with interactive overlays, gesture controls, and satisfying animations — all layered on top of the full-screen video via a `Stack` in `FeedVideoItem`.

## Dependencies
Requires **Milestone 3** complete (video feed with autoplay working).

## What Was Built
Five overlay widgets integrated into `FeedVideoItem`'s 7-layer `Stack`:
1. **`VideoGestureControls`** — Long-press for 2x playback speed with a badge indicator
2. **`DoubleTapLikeOverlay`** — Double-tap spawns multiple floating hearts with random drift/rotation
3. **`FeedActionButtons`** — Upvote (toggle), comment (opens sheet), flag column with haptic feedback
4. **`FeedInfoBar`** — Crime type badge, description, distance/time row
5. **`VideoProgressBar`** — Seekable thin bar with drag handle and timestamp preview
6. **`CommentsSheet`** — Modal bottom sheet for viewing/interacting with comments

Plus a pause icon overlay and buffering indicator built directly into `FeedVideoItem`.

## Key Files

| File | Description |
|------|-------------|
| `apps/mobile/lib/features/feed/presentation/widgets/feed_video_item.dart` | 7-layer Stack integrating all overlays |
| `apps/mobile/lib/features/feed/presentation/widgets/video_gesture_controls.dart` | Long-press 2x speed handler |
| `apps/mobile/lib/features/feed/presentation/widgets/double_tap_like_overlay.dart` | Multi-heart floating animation |
| `apps/mobile/lib/features/feed/presentation/widgets/feed_action_buttons.dart` | Side action buttons column |
| `apps/mobile/lib/features/feed/presentation/widgets/feed_info_bar.dart` | Bottom info bar with crime badge |
| `apps/mobile/lib/features/feed/presentation/widgets/video_progress_bar.dart` | Seekable progress bar with gesture zone |
| `apps/mobile/lib/features/feed/presentation/widgets/comments_sheet.dart` | Comment viewing bottom sheet |
| `apps/mobile/lib/core/constants/app_constants.dart` | All animation/sizing constants |
| `apps/mobile/lib/core/utils/formatters.dart` | Count and distance formatting |

## Implementation Details

### FeedVideoItem Stack Layout

The `build` method in `FeedVideoItem` arranges 7 layers. All overlay positions are calculated relative to `navBarClearance` (nav bar height + safe area + margin) so they sit above the floating nav bar:

```dart
// apps/mobile/lib/features/feed/presentation/widgets/feed_video_item.dart
@override
Widget build(BuildContext context) {
  final isUpvoted = ref.watch(upvotedReportsProvider).contains(widget.report.id);
  final navBarClearance = _getNavBarClearance(context);

  ref.listen<bool>(isFeedTabActiveProvider, (previous, current) {
    _handleTabVisibilityChange(current);
  });

  return Container(
    color: AppColors.background,
    child: Stack(
      fit: StackFit.expand,
      children: [
        // Layer 1: Video or placeholder
        if (_hasError) VideoErrorPlaceholder(message: _errorMessage, onRetry: _retryLoad)
        else if (controllerReady) _buildVideoPlayer()
        else const VideoLoadingPlaceholder(),

        // Layer 2: Gesture handlers (long-press → double-tap → tap)
        if (controllerReady)
          VideoGestureControls(
            controller: _controller,
            child: DoubleTapLikeOverlay(
              onDoubleTap: _handleDoubleTapLike,
              child: GestureDetector(
                onTap: _togglePlayPause,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),
          ),

        // Layer 3: Buffering indicator
        if (_isBuffering && controllerReady)
          const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),

        // Layer 4: Pause icon
        if (controllerReady && _isPaused)
          IgnorePointer(
            child: Center(
              child: Container(
                padding: EdgeInsets.all(AppSpacing.lg - AppSpacing.xs),
                decoration: BoxDecoration(color: AppColors.overlayMedium, shape: BoxShape.circle),
                child: Icon(Icons.play_arrow_rounded, color: AppColors.textPrimary, size: AppSpacing.iconXl),
              ),
            ),
          ),

        // Layer 5: Progress bar (behind buttons/info so they receive taps)
        if (controllerReady)
          Positioned(left: 0, right: 0, bottom: navBarClearance,
            child: VideoProgressBar(controller: _controller)),

        // Layer 6: Side action buttons
        Positioned(right: 12, bottom: navBarClearance + 100,
          child: FeedActionButtons(
            report: widget.report,
            isUpvoted: isUpvoted,
            onUpvote: _handleUpvoteButtonTap,
            onComment: _showComments,
            onFlag: _handleFlag,
          )),

        // Layer 7: Bottom info bar
        Positioned(
          left: 16, right: AppConstants.feedInfoBarRightMargin,
          bottom: navBarClearance + 20,
          child: FeedInfoBar(report: widget.report)),
      ],
    ),
  );
}
```

### Gesture Map

| Gesture | Action | Handler |
|---------|--------|---------|
| **Tap** | Toggle play/pause + show pause icon | `GestureDetector.onTap` → `_togglePlayPause()` |
| **Double-tap** | Upvote (add only) + floating heart animation | `DoubleTapLikeOverlay.onDoubleTapDown` → `_handleDoubleTapLike()` |
| **Long-press** | 2x speed + badge indicator | `VideoGestureControls.onLongPressStart/End` |
| **Horizontal drag on progress bar** | Seek to position | `VideoProgressBar` gesture detector |

Double-tap only adds upvotes, never removes. The upvote button toggles on/off via `toggleUpvote()`.

### Video Gesture Controls (Long-press 2x Speed)

Wraps child in a `GestureDetector` with `onLongPressStart`/`onLongPressEnd`. Sets playback speed to 2.0 on hold, 1.0 on release. Shows a badge in the top-right corner. Includes haptic feedback (`HapticFeedback.mediumImpact`). If the video is paused, long-press also starts playback:

```dart
// apps/mobile/lib/features/feed/presentation/widgets/video_gesture_controls.dart
void _startFastForward() {
  if (widget.controller == null) return;
  if (!widget.controller!.value.isInitialized) return;

  HapticFeedback.mediumImpact();

  if (!widget.controller!.value.isPlaying) {
    widget.controller!.play();
  }

  widget.controller!.setPlaybackSpeed(2.0);
  setState(() => _isFastForwarding = true);
}

// Badge indicator:
Positioned(
  top: MediaQuery.of(context).padding.top + 12,
  right: 12,
  child: Container(
    decoration: BoxDecoration(
      color: AppColors.overlayDark,
      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.fast_forward_rounded, color: AppColors.textPrimary, size: AppSpacing.iconSm),
        SizedBox(width: AppSpacing.xs),
        Text('2x', style: AppTypography.labelSmall.copyWith(
          color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
      ],
    ),
  ),
),
```

### Double-Tap Floating Hearts

Uses `TickerProviderStateMixin` to support multiple simultaneous hearts. Each heart gets its own `AnimationController` and random `horizontalDrift` / `rotation`. Hearts float upward by `AppConstants.heartFloatDistance` (150px), scale with a bounce (peak 1.2x), and fade out over the last 40% of the animation:

```dart
// apps/mobile/lib/features/feed/presentation/widgets/double_tap_like_overlay.dart
void _handleDoubleTap(TapDownDetails details) {
  HapticFeedback.mediumImpact();

  final controller = AnimationController(
    duration: AppConstants.floatingHeartDuration, // 1000ms
    vsync: this,
  );

  final heart = _FloatingHeart(
    id: DateTime.now().microsecondsSinceEpoch,
    position: details.localPosition,
    controller: controller,
    horizontalDrift: (_random.nextDouble() - 0.5) * AppConstants.heartMaxDrift, // ±60px
    rotation: (_random.nextDouble() - 0.5) * AppConstants.heartMaxRotation,    // ±0.5rad
  );

  setState(() => _hearts.add(heart));
  controller.forward().then((_) {
    if (mounted) {
      setState(() => _hearts.removeWhere((h) => h.id == heart.id));
      controller.dispose();
    }
  });
  widget.onDoubleTap();
}
```

Each heart renders with scale, opacity, vertical float, and horizontal drift all driven by `Curves.easeOut` / `Curves.easeIn`:

```dart
// Animation values for each heart:
// Scale: 0 → 1.2 (first 30%) → 1.0 (remaining 70%)
// Opacity: 1.0 (first 60%) → 0.0 (last 40%)
// Vertical: 0 → -150px (easeOut)
// Horizontal: 0 → drift (easeOut)
```

### Feed Action Buttons

Vertical column of three buttons (upvote, comment, flag) with 48px circular backgrounds (`AppColors.overlayLight`), formatted counts via `Formatters.count()`, haptic feedback on every tap, and accessibility labels:

```dart
// apps/mobile/lib/features/feed/presentation/widgets/feed_action_buttons.dart
class FeedActionButtons extends StatelessWidget {
  final Report report;
  final bool isUpvoted;
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
          label: Formatters.count(report.upvotes),
          isActive: isUpvoted,
          activeColor: AppColors.accent,
          onTap: onUpvote,
          semanticLabel: 'Upvote. Current count: ${report.upvotes}',
        ),
        const SizedBox(height: AppConstants.feedActionButtonSpacing), // 20
        _ActionButton(icon: Icons.chat_bubble_outline_rounded,
          label: Formatters.count(report.commentCount), onTap: onComment, ...),
        const SizedBox(height: AppConstants.feedActionButtonSpacing),
        _ActionButton(icon: Icons.flag_outlined, label: 'Report', onTap: onFlag, ...),
      ],
    );
  }
}
```

The upvote button's active state turns `AppColors.accent` (red). Count formatting: 999 → "999", 1500 → "1.5K", 1500000 → "1.5M".

### Feed Info Bar

Shows a color-coded crime type badge, 2-line description, and distance/time metadata. Text uses `AppTypography.videoOverlayShadow` for readability over video:

```dart
// apps/mobile/lib/features/feed/presentation/widgets/feed_info_bar.dart
@override
Widget build(BuildContext context) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      // Crime type badge
      Container(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm + AppSpacing.xxs, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: report.type.color, // e.g. AppColors.crimeTheft (orange)
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Text(report.type.displayName.toUpperCase(),
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.textPrimary, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      ),
      SizedBox(height: AppSpacing.sm),

      // Description (2 lines max)
      Text(report.description, maxLines: 2, overflow: TextOverflow.ellipsis,
        style: AppTypography.bodyMedium.copyWith(
          color: AppColors.textPrimary, height: 1.3,
          shadows: AppTypography.videoOverlayShadow)),

      // Distance and time
      Row(children: [
        Icon(Icons.location_on, size: 14, color: Colors.white70),
        SizedBox(width: 4),
        Text(Formatters.distance(report.distanceKm), ...),  // "0.3 mi"
        SizedBox(width: 12),
        Icon(Icons.access_time, size: 14, color: Colors.white70),
        SizedBox(width: 4),
        Text(report.timeAgo, ...),  // "2h ago"
      ]),
    ],
  );
}
```

### Video Progress Bar

A thin 3px bar that expands to 6px when dragging. The gesture zone is 100px tall (invisible, `HitTestBehavior.translucent` so vertical swipes pass through to PageView). Shows a drag handle (12px circle) and timestamp preview popup while seeking:

```dart
// apps/mobile/lib/features/feed/presentation/widgets/video_progress_bar.dart
class VideoProgressBar extends StatefulWidget {
  final VideoPlayerController? controller;
  final double gestureZoneHeight; // 100px
  final double barHeight;         // 3px
  final double expandedBarHeight; // 6px
}

// Seeking behavior:
void _onHorizontalDragStart(DragStartDetails details, double width) {
  HapticFeedback.selectionClick();
  setState(() { _isDragging = true; _dragProgress = _calculateProgress(widget.controller!.value); });
}

void _onHorizontalDragUpdate(DragUpdateDetails details, double width) {
  final delta = details.delta.dx / width;
  setState(() { _dragProgress = (_dragProgress + delta).clamp(0.0, 1.0); });
}

void _onHorizontalDragEnd(DragEndDetails details) {
  HapticFeedback.lightImpact();
  final newPosition = Duration(
    milliseconds: (_dragProgress * widget.controller!.value.duration.inMilliseconds).round(),
  );
  widget.controller!.seekTo(newPosition);
  setState(() => _isDragging = false);
}
```

Uses `ValueListenableBuilder<VideoPlayerValue>` for efficient rebuilds only when video position changes.

### Comments Integration

Tapping the comment button pauses the video and opens a `CommentsSheet` modal bottom sheet. When the sheet closes, the video resumes:

```dart
void _showComments() {
  if (_isControllerValid() && _controller != null) _controller!.pause();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CommentsSheet(reportId: widget.report.id),
  ).whenComplete(() {
    if (widget.isActive && _isControllerValid() && _controller != null) {
      _controller!.play();
      setState(() => _isPaused = false);
    }
  });
}
```

## Visual Specifications

| Element | Style |
|---------|-------|
| Progress bar track | 3px, `AppColors.progressTrack` (30% white) |
| Progress bar fill | White, rounds to `barHeight / 2` radius |
| Progress bar (dragging) | Expands to 6px, shows 12px white circle handle |
| Fast-forward badge | Top-right, `AppColors.overlayDark` (60% black), rounded pill |
| Action buttons | 48x48 circles, `AppColors.overlayLight` (30% black) |
| Active upvote | `AppColors.accent` (#E53935 red) |
| Text shadows | `AppTypography.videoOverlayShadow` — 4px blur, black54 |
| Crime badge | Rounded rect, `report.type.color` background |
| Heart icon | 80px, `AppColors.accent`, 10px blur shadow |
| Pause icon | `AppSpacing.iconXl` (48px), `AppColors.overlayMedium` circle |
| Timestamp popup | `AppColors.overlayHeavy` (80% black), rounded |

## Testing
No automated tests. Manual verification:
- Upvote button toggles on/off with red highlight
- Double-tap spawns hearts that float and fade
- Multiple rapid double-taps stack multiple hearts
- Long-press shows 2x badge and speeds up video
- Releasing long-press returns to 1x
- Progress bar seek works correctly
- Drag handle and timestamp appear while seeking
- Crime type badge color matches report type
- Description truncates at 2 lines
- Distance shown in miles (converted from km)
- Comment sheet pauses video, closing resumes it
- All overlays clear the floating nav bar

## Notes

- **Deviation: Floating hearts** — The original plan used a single heart with TweenSequence animations (scale up → bounce → fade). The implementation supports multiple simultaneous hearts, each with random horizontal drift (±60px) and rotation (±0.5 radians), creating a more dynamic TikTok-like effect.
- **Deviation: Fast-forward indicator position** — The plan showed it centered on screen. The implementation places it as a compact badge in the top-right corner, which is less intrusive.
- **Deviation: Progress bar gesture zone** — Not in the original plan. The implementation uses a 100px invisible gesture zone above the 3px bar, with `HitTestBehavior.translucent` to let vertical swipes pass through to the PageView while capturing horizontal drags for seeking.
- **Deviation: Haptic feedback** — Added throughout (medium impact on double-tap and long-press, light impact on upvote tap and seek end, selection click on seek start). Not specified in the original plan.
- **Deviation: Accessibility** — `FeedActionButtons` includes `Semantics` labels, and `VideoProgressBar` has a slider semantic. Not in the original plan.
- **Deviation: Upvote behavior** — Double-tap only adds (never removes) upvotes. The button tap toggles. This is intentional — TikTok uses the same pattern to keep the double-tap gesture always positive.
- **Deviation: Comments sheet** — The plan didn't include a comments sheet, but `CommentsSheet` was implemented as part of this milestone with video pause/resume integration.
- **`_handleFlag`** — Currently a no-op stub. Flagging functionality is deferred to a future milestone.
