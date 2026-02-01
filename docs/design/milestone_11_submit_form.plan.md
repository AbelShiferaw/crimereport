# Milestone 11: Submit Report - Details Form

## Goal
Build the form screen where users add crime details (type, description, location) after capturing media.

## Dependencies
Requires **Milestone 10** complete (camera capture working).

## Implementation

### 1. Report Details Screen
```dart
// lib/features/submit/presentation/report_details_screen.dart
class ReportDetailsScreen extends StatefulWidget {
  final String mediaPath;
  final bool isVideo;
  
  @override
  State<ReportDetailsScreen> createState() => _ReportDetailsScreenState();
}

class _ReportDetailsScreenState extends State<ReportDetailsScreen> {
  ReportType? _selectedType;
  final _descriptionController = TextEditingController();
  Position? _location;
  String? _address;
  bool _isSubmitting = false;
  
  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }
  
  Future<void> _getCurrentLocation() async {
    final position = await Geolocator.getCurrentPosition();
    final placemarks = await placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    );
    
    setState(() {
      _location = position;
      _address = '${placemarks.first.street}, ${placemarks.first.locality}';
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF121212),
      appBar: AppBar(
        title: Text('Report Details'),
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Media thumbnail
            _buildMediaPreview(),
            SizedBox(height: 24),
            
            // Crime type selector
            _buildTypeSelector(),
            SizedBox(height: 24),
            
            // Description input
            _buildDescriptionInput(),
            SizedBox(height: 24),
            
            // Location display
            _buildLocationCard(),
            SizedBox(height: 32),
            
            // Submit button
            _buildSubmitButton(),
          ],
        ),
      ),
    );
  }
}
```

### 2. Crime Type Selector
```dart
Widget _buildTypeSelector() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'What happened?',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: ReportType.values.map((type) {
          final isSelected = _selectedType == type;
          return GestureDetector(
            onTap: () => setState(() => _selectedType = type),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? Colors.red : Colors.grey[800],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? Colors.red : Colors.grey[600]!,
                ),
              ),
              child: Text(
                type.displayName,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    ],
  );
}
```

### 3. Description Input
```dart
Widget _buildDescriptionInput() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Description (optional)',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      SizedBox(height: 12),
      TextField(
        controller: _descriptionController,
        maxLines: 4,
        maxLength: 500,
        style: TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'What did you witness? Any details that might help...',
          hintStyle: TextStyle(color: Colors.grey),
          filled: true,
          fillColor: Colors.grey[900],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          counterStyle: TextStyle(color: Colors.grey),
        ),
      ),
    ],
  );
}
```

### 4. Location Card
```dart
Widget _buildLocationCard() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Location',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      SizedBox(height: 12),
      Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.location_on, color: Colors.red),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _address ?? 'Getting location...',
                    style: TextStyle(color: Colors.white),
                  ),
                  if (_location != null)
                    Text(
                      '${_location!.latitude.toStringAsFixed(4)}, ${_location!.longitude.toStringAsFixed(4)}',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                ],
              ),
            ),
            Icon(Icons.check_circle, color: Colors.green),
          ],
        ),
      ),
    ],
  );
}
```

### 5. Submit Button
```dart
Widget _buildSubmitButton() {
  final canSubmit = _selectedType != null && _location != null;
  
  return SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: canSubmit && !_isSubmitting ? _submitReport : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red,
        padding: EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: _isSubmitting
          ? SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
          : Text(
              'Submit Report',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
    ),
  );
}

Future<void> _submitReport() async {
  setState(() => _isSubmitting = true);
  
  // TODO: Actually submit to backend in integration phase
  await Future.delayed(Duration(seconds: 2)); // Simulate upload
  
  // Show success and return to feed
  Navigator.of(context).popUntil((route) => route.isFirst);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Report submitted successfully!')),
  );
}
```

## Complete Submit Flow
```
Submit Tab (tap)
    │
    ▼
Camera Screen
    │ (capture)
    ▼
Media Preview
    │ (use)
    ▼
Report Details Form
    │ (submit)
    ▼
Feed Tab (success)
```

## Deliverable Checklist
- [ ] Media thumbnail shows at top
- [ ] Crime type chips selectable
- [ ] Only one type can be selected
- [ ] Description field with character limit
- [ ] Location auto-detected
- [ ] Address reverse geocoded
- [ ] Submit button disabled until type selected
- [ ] Loading state on submit
- [ ] Success snackbar shown
- [ ] Returns to feed after submit

## Files (2 total)
1. `lib/features/submit/presentation/report_details_screen.dart` - Create
2. `lib/features/submit/presentation/media_preview_screen.dart` - Update navigation
