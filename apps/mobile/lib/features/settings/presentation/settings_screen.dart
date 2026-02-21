import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/responsive.dart';
import '../providers/settings_providers.dart';
import 'legal_text_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pushEnabled = ref.watch(pushNotificationsEnabledProvider);
    final radius = ref.watch(notificationRadiusProvider);
    final activeFilters = ref.watch(crimeTypeFiltersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: Responsive.maxContentWidth,
            ),
            child: ListView(
              padding: EdgeInsets.all(
                Responsive.value(
                  context,
                  mobile: AppSpacing.md,
                  tablet: AppSpacing.lg,
                ),
              ),
              children: [
                _buildNotificationsSection(context, ref, pushEnabled, radius),
                const SizedBox(height: AppSpacing.lg),
                _buildCrimeTypeSection(context, ref, activeFilters),
                const SizedBox(height: AppSpacing.lg),
                _buildPrivacySection(context),
                const SizedBox(height: AppSpacing.lg),
                _buildAboutSection(context),
                const SizedBox(height: AppSpacing.xl),
                _buildAnonymousIdCard(),
                SizedBox(height: AppSpacing.floatingNavBarSpace),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --------------- Notifications ---------------

  Widget _buildNotificationsSection(
    BuildContext context,
    WidgetRef ref,
    bool pushEnabled,
    double radius,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Notifications'),
        _SettingsTile(
          icon: Icons.notifications_outlined,
          title: 'Push Notifications',
          subtitle: pushEnabled ? 'Enabled' : 'Disabled',
          trailing: Switch(
            value: pushEnabled,
            onChanged: (v) =>
                ref.read(pushNotificationsEnabledProvider.notifier).state = v,
            activeColor: AppColors.primary,
          ),
        ),
        if (pushEnabled) ...[
          const SizedBox(height: AppSpacing.xs),
          _buildRadiusSlider(context, ref, radius),
        ],
      ],
    );
  }

  Widget _buildRadiusSlider(BuildContext context, WidgetRef ref, double radius) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: const Icon(
                  Icons.radar_rounded,
                  color: AppColors.textPrimary,
                  size: AppSpacing.iconMd,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Notification Radius', style: AppTypography.titleSmall),
                    Text(
                      'Alert me for crimes within this range',
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Text(
                  '${radius.round()} km',
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.card,
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withAlpha(30),
              trackHeight: 4,
            ),
            child: Slider(
              value: radius,
              min: 1,
              max: 50,
              divisions: 49,
              onChanged: (v) =>
                  ref.read(notificationRadiusProvider.notifier).state = v,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('1 km', style: AppTypography.caption),
              Text('50 km', style: AppTypography.caption),
            ],
          ),
        ],
      ),
    );
  }

  // --------------- Crime Type Filters ---------------

  Widget _buildCrimeTypeSection(
    BuildContext context,
    WidgetRef ref,
    Set<ReportType> activeFilters,
  ) {
    final allSelected = activeFilters.length == ReportType.values.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _SectionHeader(title: 'Crime Type Filters'),
            GestureDetector(
              onTap: () {
                final notifier = ref.read(crimeTypeFiltersProvider.notifier);
                notifier.state = allSelected
                    ? <ReportType>{}
                    : Set.from(ReportType.values);
              },
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  allSelected ? 'Deselect All' : 'Select All',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        ...ReportType.values.map(
          (type) => _buildCrimeTypeToggle(ref, type, activeFilters),
        ),
      ],
    );
  }

  Widget _buildCrimeTypeToggle(
    WidgetRef ref,
    ReportType type,
    Set<ReportType> activeFilters,
  ) {
    final isActive = activeFilters.contains(type);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Center(
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: type.color,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        title: Text(type.displayName, style: AppTypography.titleSmall),
        trailing: Switch(
          value: isActive,
          onChanged: (v) {
            final notifier = ref.read(crimeTypeFiltersProvider.notifier);
            final current = Set<ReportType>.from(notifier.state);
            if (v) {
              current.add(type);
            } else {
              current.remove(type);
            }
            notifier.state = current;
          },
          activeColor: AppColors.primary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
      ),
    );
  }

  // --------------- Privacy ---------------

  Widget _buildPrivacySection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Privacy'),
        _SettingsTile(
          icon: Icons.shield_outlined,
          title: 'Anonymous Mode',
          subtitle: 'Your identity is never stored',
          trailing: const Icon(
            Icons.check_circle,
            color: AppColors.success,
          ),
        ),
      ],
    );
  }

  // --------------- About ---------------

  Widget _buildAboutSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'About'),
        _SettingsTile(
          icon: Icons.info_outline,
          title: 'App Version',
          subtitle: '1.0.0 (Build 1)',
        ),
        _SettingsTile(
          icon: Icons.description_outlined,
          title: 'Privacy Policy',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const LegalTextScreen(
              title: 'Privacy Policy',
              body: LegalContent.privacyPolicy,
            ),
          )),
        ),
        _SettingsTile(
          icon: Icons.gavel_outlined,
          title: 'Terms of Service',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const LegalTextScreen(
              title: 'Terms of Service',
              body: LegalContent.termsOfService,
            ),
          )),
        ),
        _SettingsTile(
          icon: Icons.help_outline,
          title: 'Help & Support',
          onTap: () {},
        ),
      ],
    );
  }

  // --------------- Anonymous ID ---------------

  Widget _buildAnonymousIdCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.fingerprint, color: AppColors.textTertiary),
              const SizedBox(width: AppSpacing.sm),
              Text('Your Anonymous ID', style: AppTypography.caption),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('a1b2c3d4e5f6...', style: AppTypography.monospace),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'This ID is not linked to your identity',
            style: AppTypography.caption,
          ),
        ],
      ),
    );
  }
}

// --------------- Reusable Components ---------------

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        title,
        style: AppTypography.titleMedium.copyWith(color: AppColors.primary),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Icon(
            icon,
            color: AppColors.textPrimary,
            size: AppSpacing.iconMd,
          ),
        ),
        title: Text(title, style: AppTypography.titleSmall),
        subtitle: subtitle != null
            ? Text(subtitle!, style: AppTypography.caption)
            : null,
        trailing: trailing ??
            (onTap != null
                ? const Icon(Icons.chevron_right, color: AppColors.textTertiary)
                : null),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
      ),
    );
  }
}
