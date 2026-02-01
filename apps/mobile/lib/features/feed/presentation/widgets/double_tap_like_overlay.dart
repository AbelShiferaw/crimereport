import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/theme.dart';

/// Overlay that shows floating hearts animation on double-tap.
///
/// Multiple hearts can stack and float upward like TikTok.
/// Each heart has random drift and rotation for visual variety.
class DoubleTapLikeOverlay extends StatefulWidget {
  /// The child widget to wrap with double-tap detection.
  final Widget child;

  /// Callback when double-tap is detected.
  final VoidCallback onDoubleTap;

  const DoubleTapLikeOverlay({
    super.key,
    required this.child,
    required this.onDoubleTap,
  });

  @override
  State<DoubleTapLikeOverlay> createState() => _DoubleTapLikeOverlayState();
}

class _DoubleTapLikeOverlayState extends State<DoubleTapLikeOverlay>
    with TickerProviderStateMixin {
  final List<_FloatingHeart> _hearts = [];
  final Random _random = Random();

  void _handleDoubleTap(TapDownDetails details) {
    HapticFeedback.mediumImpact();

    // Create new floating heart
    final controller = AnimationController(
      duration: AppConstants.floatingHeartDuration,
      vsync: this,
    );

    final heart = _FloatingHeart(
      id: DateTime.now().microsecondsSinceEpoch,
      position: details.localPosition,
      controller: controller,
      horizontalDrift: (_random.nextDouble() - 0.5) * AppConstants.heartMaxDrift,
      rotation: (_random.nextDouble() - 0.5) * AppConstants.heartMaxRotation,
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

  @override
  void dispose() {
    for (final heart in _hearts) {
      heart.controller.dispose();
    }
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

          // Render all active floating hearts
          for (final heart in _hearts)
            AnimatedBuilder(
              animation: heart.controller,
              builder: (context, child) {
                final progress = heart.controller.value;

                // Scale animation: 0 -> peak -> 1.0 (pop in with bounce)
                const scalePeak = AppConstants.heartScalePeak;
                final double scale;
                if (progress < 0.3) {
                  scale = Curves.easeOut.transform(progress / 0.3) * scalePeak;
                } else {
                  scale = scalePeak -
                      ((scalePeak - 1.0) *
                          Curves.easeInOut.transform((progress - 0.3) / 0.7));
                }

                // Opacity: 1.0 for first 60%, then fade out
                final double opacity;
                if (progress < 0.6) {
                  opacity = 1.0;
                } else {
                  opacity =
                      1.0 - Curves.easeIn.transform((progress - 0.6) / 0.4);
                }

                // Float upward
                final verticalOffset =
                    -AppConstants.heartFloatDistance * Curves.easeOut.transform(progress);

                // Horizontal drift with easing
                final horizontalOffset =
                    heart.horizontalDrift * Curves.easeOut.transform(progress);

                return Positioned(
                  left: heart.position.dx - 40 + horizontalOffset,
                  top: heart.position.dy - 40 + verticalOffset,
                  child: Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: scale,
                      child: Transform.rotate(
                        angle: heart.rotation,
                        child: const Icon(
                          Icons.favorite,
                          color: AppColors.primary,
                          size: 80,
                          shadows: [
                            Shadow(
                              blurRadius: 10,
                              color: Color(0x73000000), // black45
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Data class for a single floating heart animation.
/// 
/// Holds the animation state for one heart, including its position,
/// controller, and random visual variations.
class _FloatingHeart {
  /// Unique identifier for this heart.
  final int id;

  /// Starting position where the tap occurred.
  final Offset position;

  /// Animation controller for this heart.
  final AnimationController controller;

  /// Random horizontal drift in pixels (-30 to +30).
  final double horizontalDrift;

  /// Random rotation in radians.
  final double rotation;

  _FloatingHeart({
    required this.id,
    required this.position,
    required this.controller,
    required this.horizontalDrift,
    required this.rotation,
  });
}
