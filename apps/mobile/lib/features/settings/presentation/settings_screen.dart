import 'package:flutter/material.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/responsive.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                // Privacy section
                _buildSectionHeader(context, 'Privacy'),
                _buildSettingsTile(
                  context,
                  icon: Icons.shield_outlined,
                  title: 'Anonymous Mode',
                  subtitle: 'Your identity is never stored',
                  trailing: const Icon(
                    Icons.check_circle,
                    color: AppColors.success,
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                // Notifications section
                _buildSectionHeader(context, 'Notifications'),
                _buildSettingsTile(
                  context,
                  icon: Icons.notifications_outlined,
                  title: 'Push Notifications',
                  subtitle: 'Coming in Milestone 12',
                  trailing: Switch(
                    value: false,
                    onChanged: null,
                    activeColor: AppColors.primary,
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                // About section
                _buildSectionHeader(context, 'About'),
                _buildSettingsTile(
                  context,
                  icon: Icons.info_outline,
                  title: 'App Version',
                  subtitle: '1.0.0 (Build 1)',
                ),
                _buildSettingsTile(
                  context,
                  icon: Icons.description_outlined,
                  title: 'Privacy Policy',
                  onTap: () {},
                ),
                _buildSettingsTile(
                  context,
                  icon: Icons.help_outline,
                  title: 'Help & Support',
                  onTap: () {},
                ),

                const SizedBox(height: AppSpacing.xl),

                // Anonymous ID Card
                _buildAnonymousIdCard(context),

                // Bottom padding for floating nav bar
                SizedBox(height: AppSpacing.floatingNavBarSpace),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        title,
        style: AppTypography.titleMedium.copyWith(color: AppColors.primary),
      ),
    );
  }

  Widget _buildSettingsTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
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
            ? Text(subtitle, style: AppTypography.caption)
            : null,
        trailing:
            trailing ??
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

  Widget _buildAnonymousIdCard(BuildContext context) {
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
              Icon(Icons.fingerprint, color: AppColors.textTertiary),
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
