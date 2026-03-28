import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:crimereport/core/constants/app_constants.dart';
import 'package:crimereport/core/constants/enums.dart';
import 'package:crimereport/core/theme/theme.dart';
import 'package:crimereport/features/feed/providers/feed_providers.dart';
import 'package:crimereport/features/submit/providers/upload_provider.dart';
import 'package:crimereport/features/submit/presentation/widgets/upload_overlay.dart';

class ReportDetailsScreen extends ConsumerStatefulWidget {
  final String filePath;
  final bool isVideo;

  const ReportDetailsScreen({
    super.key,
    required this.filePath,
    required this.isVideo,
  });

  @override
  ConsumerState<ReportDetailsScreen> createState() =>
      _ReportDetailsScreenState();
}

class _ReportDetailsScreenState extends ConsumerState<ReportDetailsScreen> {
  final _descriptionController = TextEditingController();
  final _descriptionFocus = FocusNode();
  static const int _maxDescriptionLength = AppConstants.maxDescriptionLength;

  ReportType? _selectedType;
  Position? _location;
  bool _isLoadingLocation = true;
  String? _locationError;

  @override
  void initState() {
    super.initState();
    _fetchLocation();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _locationError = null;
    });

    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _isLoadingLocation = false;
            _locationError = 'Location permission denied';
          });
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 10));

      if (mounted) {
        setState(() {
          _location = position;
          _isLoadingLocation = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
          _locationError = 'Could not get location';
        });
      }
      debugPrint('Error fetching location: $e');
    }
  }

  bool get _isFormValid =>
      _selectedType != null &&
      _descriptionController.text.trim().isNotEmpty;

  void _submit() {
    if (!_isFormValid) return;

    _descriptionFocus.unfocus();

    ref.read(uploadProvider.notifier).submit(
          filePath: widget.filePath,
          type: _selectedType!.name,
          description: _descriptionController.text.trim(),
          lat: _location?.latitude ?? AppConstants.defaultLatitude,
          lng: _location?.longitude ?? AppConstants.defaultLongitude,
          address: null,
        );
  }

  @override
  Widget build(BuildContext context) {
    final uploadState = ref.watch(uploadProvider);

    ref.listen<UploadState>(uploadProvider, (previous, next) {
      if (next.phase == UploadPhase.done) {
        ref.invalidate(feedReportsProvider);
        Navigator.of(context).popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Report submitted successfully!'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
          ),
        );
      }
    });

    final isUploading = uploadState.phase != UploadPhase.idle;

    return GestureDetector(
      onTap: () => _descriptionFocus.unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text('Report Details', style: AppTypography.titleMedium),
          centerTitle: true,
        ),
        body: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.md,
                      AppSpacing.lg,
                    ),
                    children: [
                      _buildMediaPreview(),
                      const SizedBox(height: AppSpacing.lg),
                      _buildSectionLabel('Crime Type'),
                      const SizedBox(height: AppSpacing.sm),
                      _buildCrimeTypeSelector(),
                      const SizedBox(height: AppSpacing.lg),
                      _buildSectionLabel('Description'),
                      const SizedBox(height: AppSpacing.sm),
                      _buildDescriptionField(),
                      const SizedBox(height: AppSpacing.lg),
                      _buildSectionLabel('Location'),
                      const SizedBox(height: AppSpacing.sm),
                      _buildLocationSection(),
                    ],
                  ),
                ),
                _buildBottomBar(),
              ],
            ),
            if (isUploading)
              UploadOverlay(
                uploadState: uploadState,
                onCancel: () => ref.read(uploadProvider.notifier).cancel(),
                onDismiss: () => ref.read(uploadProvider.notifier).reset(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: AppTypography.labelMedium.copyWith(
        color: AppColors.textTertiary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildMediaPreview() {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: SizedBox(
          width: AppConstants.mediaPreviewWidth,
          height: AppConstants.mediaPreviewHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.isVideo)
                Container(
                  color: AppColors.surface,
                  child: const Center(
                    child: Icon(
                      Icons.videocam_rounded,
                      color: AppColors.textTertiary,
                      size: 40,
                    ),
                  ),
                )
              else
                Image.file(File(widget.filePath), fit: BoxFit.cover),

              Positioned(
                bottom: AppSpacing.xs,
                left: AppSpacing.xs,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: widget.isVideo ? AppColors.primary : AppColors.info,
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Text(
                    widget.isVideo ? 'VIDEO' : 'PHOTO',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),

              Positioned(
                top: AppSpacing.xs,
                right: AppSpacing.xs,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(140),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCrimeTypeSelector() {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: ReportType.values.map((type) {
        final isSelected = _selectedType == type;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _selectedType = type);
          },
          child: AnimatedContainer(
            duration: AppConstants.standardTransition,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: isSelected ? type.color.withAlpha(40) : AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusXxl),
              border: Border.all(
                color: isSelected ? type.color : AppColors.divider,
                width: isSelected ? 1.5 : 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: type.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  type.displayName,
                  style: AppTypography.labelMedium.copyWith(
                    color:
                        isSelected ? type.color : AppColors.textSecondary,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDescriptionField() {
    return TextField(
      controller: _descriptionController,
      focusNode: _descriptionFocus,
      maxLines: 4,
      maxLength: _maxDescriptionLength,
      style: AppTypography.bodyMedium,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: 'Describe what happened...',
        hintStyle: AppTypography.bodyMedium.copyWith(
          color: AppColors.textTertiary,
        ),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          borderSide:
              const BorderSide(color: AppColors.divider, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          borderSide:
              const BorderSide(color: AppColors.primary, width: 1),
        ),
        contentPadding: const EdgeInsets.all(AppSpacing.md),
        counterStyle: AppTypography.caption.copyWith(
          color: AppColors.textTertiary,
        ),
      ),
    );
  }

  Widget _buildLocationSection() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Icon(
              _location != null
                  ? Icons.location_on_rounded
                  : Icons.location_off_rounded,
              color:
                  _location != null ? AppColors.success : AppColors.textTertiary,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _isLoadingLocation
                ? Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'Fetching location...',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  )
                : _location != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Location captured',
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_location!.latitude.toStringAsFixed(5)}, ${_location!.longitude.toStringAsFixed(5)}',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        _locationError ?? 'Location unavailable',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
          ),
          if (!_isLoadingLocation)
            GestureDetector(
              onTap: _fetchLocation,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: const Icon(
                  Icons.refresh_rounded,
                  color: AppColors.textSecondary,
                  size: 18,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final isUploading =
        ref.watch(uploadProvider).phase != UploadPhase.idle;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        MediaQuery.of(context).viewPadding.bottom + AppSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: GestureDetector(
        onTap: (_isFormValid && !isUploading) ? _submit : null,
        child: AnimatedContainer(
          duration: AppConstants.standardTransition,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: (_isFormValid && !isUploading)
                ? AppColors.primary
                : AppColors.elevated,
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.send_rounded,
                color: _isFormValid ? Colors.white : AppColors.textDisabled,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Submit Report',
                style: AppTypography.titleSmall.copyWith(
                  color:
                      _isFormValid ? Colors.white : AppColors.textDisabled,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
