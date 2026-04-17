import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crimereport/core/theme/theme.dart';
import 'package:crimereport/shared/data/api/api_client.dart';
import 'package:crimereport/features/onboarding/presentation/onboarding_screen.dart';
import 'package:crimereport/shared/widgets/app_shell.dart';
import 'package:crimereport/shared/widgets/foreground_notification_banner.dart';

/// Animated splash screen shown on app launch.
///
/// Displays the app logo with a fade-in animation, performs an API health
/// check, then navigates to [OnboardingScreen] (first launch) or
/// [AppShell] (returning user).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );

    _animController.forward();

    _initAndNavigate();
  }

  Future<void> _initAndNavigate() async {
    final healthFuture = _checkHealth();
    // Ensure the splash stays visible for at least the animation duration
    final delayFuture = Future<void>.delayed(const Duration(milliseconds: 1800));

    await Future.wait([healthFuture, delayFuture]);

    if (!mounted || _navigating) return;
    _navigating = true;

    final prefs = await SharedPreferences.getInstance();
    final onboardingComplete = prefs.getBool(onboardingCompleteKey) ?? false;

    if (!mounted) return;

    final Widget destination = onboardingComplete
        ? const ForegroundNotificationBanner(child: AppShell())
        : const OnboardingScreen();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => destination,
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  Future<void> _checkHealth() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.get('/health').timeout(const Duration(seconds: 5));
    } catch (_) {
      // Health check failure is non-blocking; the app works offline too.
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: AppColors.primaryGradient,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    size: 48,
                    color: AppColors.textPrimary,
                    semanticLabel: 'CrImEreport shield logo',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'CrImEreport',
                  style: AppTypography.displayMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Anonymous Crime Reporting',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                    semanticsLabel: 'Loading',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
