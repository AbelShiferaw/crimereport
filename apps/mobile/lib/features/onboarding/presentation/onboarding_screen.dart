import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crimereport/core/theme/theme.dart';
import 'package:crimereport/shared/widgets/app_shell.dart';
import 'package:crimereport/shared/widgets/foreground_notification_banner.dart';

const String onboardingCompleteKey = 'onboarding_complete';

// ---------------------------------------------------------------------------
// Data model for each onboarding page
// ---------------------------------------------------------------------------

class _OnboardingPageData {
  final IconData icon;
  final String title;
  final String description;
  final Color iconColor;

  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.description,
    required this.iconColor,
  });
}

const _pages = [
  _OnboardingPageData(
    icon: Icons.security,
    title: 'Report Anonymously',
    description:
        'No account needed. No personal information collected. '
        'Your identity stays completely private — just open the app and report.',
    iconColor: AppColors.primary,
  ),
  _OnboardingPageData(
    icon: Icons.explore,
    title: 'Stay Informed',
    description:
        'Browse a live feed of nearby reports and view them on an '
        'interactive map. Know what\'s happening in your neighborhood in real time.',
    iconColor: AppColors.info,
  ),
  _OnboardingPageData(
    icon: Icons.tune,
    title: 'Enable Permissions',
    description:
        'Allow location access to see reports near you, camera access '
        'to attach photos or videos, and notifications to get alerted about '
        'nearby incidents.',
    iconColor: AppColors.warning,
  ),
];

// ---------------------------------------------------------------------------
// Onboarding screen
// ---------------------------------------------------------------------------

/// Three-page onboarding flow shown on the first launch.
///
/// Page 1 — Anonymous Reporting explanation
/// Page 2 — Feed / Map preview
/// Page 3 — Permissions request (location, camera, notifications)
///
/// On completion the `onboarding_complete` flag is stored in
/// [SharedPreferences] and the user is navigated to [AppShell].
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  bool get _isLastPage => _currentPage == _pages.length - 1;

  void _nextPage() {
    if (_isLastPage) {
      _completeOnboarding();
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  void _skip() {
    _completeOnboarding();
  }

  Future<void> _completeOnboarding() async {
    if (_currentPage == _pages.length - 1) {
      await _requestPermissions();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onboardingCompleteKey, true);

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) =>
            const ForegroundNotificationBanner(child: AppShell()),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.locationWhenInUse,
      Permission.camera,
      Permission.notification,
    ].request();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.sm,
                  right: AppSpacing.md,
                ),
                child: TextButton(
                  onPressed: _skip,
                  child: Text(
                    'Skip',
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ),
            ),

            // Pages
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  return _OnboardingPage(data: _pages[index]);
                },
              ),
            ),

            // Page indicator + button
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.lg,
              ),
              child: Column(
                children: [
                  // Dot indicator
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_pages.length, (index) {
                      final isActive = index == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                        ),
                        width: isActive ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.primary
                              : AppColors.textTertiary.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusRound,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // CTA button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _nextPage,
                      child: Text(
                        _isLastPage ? 'Get Started' : 'Continue',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Single onboarding page widget
// ---------------------------------------------------------------------------

class _OnboardingPage extends StatelessWidget {
  final _OnboardingPageData data;

  const _OnboardingPage({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: data.iconColor.withValues(alpha: 0.15),
            ),
            child: Icon(
              data.icon,
              size: 56,
              color: data.iconColor,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            data.title,
            style: AppTypography.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            data.description,
            style: AppTypography.bodyLarge.copyWith(
              color: AppColors.textSecondary,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
