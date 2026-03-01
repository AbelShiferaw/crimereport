# Milestone 11: Submit Report - Details Form

## Status
Completed

## Goal
Build the report details form where users select a crime type, write a description, and auto-capture GPS location after capturing or selecting media evidence.

## Dependencies
Requires **Milestone 10** complete (camera/gallery capture flow returns `filePath` and `isVideo` to this screen).

## What Was Built
- `ReportDetailsScreen` — a form with media thumbnail preview, animated crime type chip selector (using `ReportType` enum with per-type colors), multiline description with character counter, auto-detected GPS location with retry, and a sticky bottom submit button with loading state
- Form validation requires both crime type and non-empty description
- Location is fetched via `Geolocator` with permission checking and 10-second timeout
- Mock submission with simulated delay, returning `true` to the caller (`SubmitScreen`) which shows a success snackbar

## Key Files
| File | Description |
|------|-------------|
| `apps/mobile/lib/features/submit/presentation/report_details_screen.dart` | The full report details form screen |
| `apps/mobile/lib/features/submit/presentation/submit_screen.dart` | Parent screen that launches this form and shows success snackbar on result |
| `apps/mobile/lib/core/constants/enums.dart` | `ReportType` enum with `displayName` and `color` per type |
| `apps/mobile/lib/core/constants/app_constants.dart` | `maxDescriptionLength`, `mediaPreviewWidth`, `mediaPreviewHeight` |

## Implementation Details

### 1. Screen Structure

`ReportDetailsScreen` receives `filePath` and `isVideo` from the camera/gallery flow. It uses a `Column` with an `Expanded` `ListView` for scrollable content and a sticky `_buildBottomBar()` at the bottom:

```dart
class ReportDetailsScreen extends StatefulWidget {
  final String filePath;
  final bool isVideo;

  const ReportDetailsScreen({
    super.key,
    required this.filePath,
    required this.isVideo,
  });

  @override
  State<ReportDetailsScreen> createState() => _ReportDetailsScreenState();
}

class _ReportDetailsScreenState extends State<ReportDetailsScreen> {
  final _descriptionController = TextEditingController();
  final _descriptionFocus = FocusNode();
  static const int _maxDescriptionLength = AppConstants.maxDescriptionLength;

  ReportType? _selectedType;
  Position? _location;
  bool _isLoadingLocation = true;
  bool _isSubmitting = false;
  String? _locationError;
}
```

### 2. Media Preview Thumbnail

Shows a compact preview at the top. For photos, renders `Image.file`; for videos, shows a placeholder icon. Includes a VIDEO/PHOTO badge and a change-media button that pops back:

```dart
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
                  child: Icon(Icons.videocam_rounded,
                      color: AppColors.textTertiary, size: 40),
                ),
              )
            else
              Image.file(File(widget.filePath), fit: BoxFit.cover),
            // Badge (VIDEO/PHOTO) at bottom-left
            Positioned(
              bottom: AppSpacing.xs, left: AppSpacing.xs,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: widget.isVideo ? AppColors.primary : AppColors.info,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  widget.isVideo ? 'VIDEO' : 'PHOTO',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            // Change-media button at top-right
          ],
        ),
      ),
    ),
  );
}
```

### 3. Crime Type Chip Selector

Uses a `Wrap` of `ReportType.values` with animated selection styling. Each chip shows a colored dot + the type name. Selection triggers haptic feedback:

```dart
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
                width: 10, height: 10,
                decoration: BoxDecoration(
                    color: type.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                type.displayName,
                style: AppTypography.labelMedium.copyWith(
                  color: isSelected ? type.color : AppColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList(),
  );
}
```

### 4. Description Field

A `TextField` with `maxLines: 4`, `maxLength` from `AppConstants.maxDescriptionLength` (500), custom borders for enabled/focused states, and `onChanged` that triggers `setState` for live form validation:

```dart
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
      hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.textTertiary),
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        borderSide: const BorderSide(color: AppColors.primary, width: 1),
      ),
      contentPadding: const EdgeInsets.all(AppSpacing.md),
    ),
  );
}
```

### 5. Location Auto-Fetch with Error Handling

Location is fetched in `initState` via `_fetchLocation()`. It checks permission, then calls `Geolocator.getCurrentPosition` with a 10-second timeout. Displays loading spinner, coordinates on success, or error message with retry button:

```dart
Future<void> _fetchLocation() async {
  setState(() { _isLoadingLocation = true; _locationError = null; });

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
      setState(() { _location = position; _isLoadingLocation = false; });
    }
  } catch (e) {
    if (mounted) {
      setState(() {
        _isLoadingLocation = false;
        _locationError = 'Could not get location';
      });
    }
  }
}
```

### 6. Form Validation and Submit

The form requires both a selected crime type **and** non-empty description text (deviation from original plan which only required crime type):

```dart
bool get _isFormValid =>
    _selectedType != null &&
    _descriptionController.text.trim().isNotEmpty;
```

Submit performs a mock delay, then pops with `true`:

```dart
Future<void> _submit() async {
  if (!_isFormValid || _isSubmitting) return;
  _descriptionFocus.unfocus();
  setState(() => _isSubmitting = true);

  await Future.delayed(const Duration(milliseconds: 800));

  if (!mounted) return;
  setState(() => _isSubmitting = false);
  Navigator.of(context).pop(true);
}
```

### 7. Sticky Bottom Submit Bar

A container pinned to the bottom with an `AnimatedContainer` button that changes color based on form validity. Shows a spinner during submission:

```dart
Widget _buildBottomBar() {
  return Container(
    padding: EdgeInsets.fromLTRB(
      AppSpacing.md, AppSpacing.md, AppSpacing.md,
      MediaQuery.of(context).viewPadding.bottom + AppSpacing.md,
    ),
    decoration: const BoxDecoration(
      color: AppColors.surface,
      border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
    ),
    child: GestureDetector(
      onTap: (_isFormValid && !_isSubmitting) ? _submit : null,
      child: AnimatedContainer(
        duration: AppConstants.standardTransition,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: (_isFormValid && !_isSubmitting)
              ? AppColors.primary : AppColors.elevated,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        child: _isSubmitting
            ? const Center(child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              ))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.send_rounded,
                    color: _isFormValid ? Colors.white : AppColors.textDisabled,
                    size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Submit Report',
                    style: AppTypography.titleSmall.copyWith(
                      color: _isFormValid ? Colors.white : AppColors.textDisabled,
                    )),
                ],
              ),
      ),
    ),
  );
}
```

## Complete Submit Flow
```
SubmitScreen
    │ (camera or gallery)
    ▼
CameraScreen / ImagePicker → MediaPreviewScreen
    │ (confirm)
    ▼
ReportDetailsScreen
    ├── Select crime type chip
    ├── Write description
    ├── Location auto-detected
    │ (submit)
    ▼
Pop with result=true → SubmitScreen shows success SnackBar
```

## Testing
No dedicated test files were created. Manual testing required for:
- Form validation states (type unselected, description empty, both valid)
- Location permission denied scenarios
- Location timeout handling
- Keyboard interaction (dismiss on tap outside, scroll with keyboard open)
- Submit loading state

## Notes
- **Deviation from plan:** Description is **required** (not optional as in original plan). `_isFormValid` checks `_descriptionController.text.trim().isNotEmpty`.
- **Deviation from plan:** No reverse geocoding — the implementation shows raw coordinates (`lat, lng`) rather than a street address. The `geocoding` package is not used.
- **Deviation from plan:** Location is not required for form submission — the form can be submitted without a location (only crime type + description are required).
- **Deviation from plan:** The submit button is a sticky bottom bar instead of inline in the scroll list.
- Crime type chips use `AnimatedContainer` with per-type color tinting rather than a flat red selection color.
- `GestureDetector` wrapping the `Scaffold` body dismisses the keyboard on tap outside the text field.
- Media preview has dimensions controlled by `AppConstants.mediaPreviewWidth` (140) and `AppConstants.mediaPreviewHeight` (180).
