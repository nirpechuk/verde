import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';

import '../models/issue.dart';
import '../models/marker.dart';
import '../services/claude_service.dart';
import '../services/supabase_service.dart';
import '../widgets/location_picker.dart';
import '../helpers/utils.dart';

class ReportIssueScreen extends StatefulWidget {
  final LatLng initialLocation;
  final VoidCallback onIssueReported;

  const ReportIssueScreen({
    super.key,
    required this.initialLocation,
    required this.onIssueReported,
  });

  @override
  State<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends State<ReportIssueScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  IssueCategory _selectedCategory = IssueCategory.other;
  File? _selectedImage;
  bool _isSubmitting = false;
  bool _hasGenerated = false;
  bool _showEditFields = false;
  int _credibilityScore = 0;
  late LatLng _selectedLocation;
  Placemark? _placemark;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
    _fetchPlacemark();
  }

  Future<void> _fetchPlacemark() async {
    try {
      final placemarks = await placemarkFromCoordinates(
        _selectedLocation.latitude,
        _selectedLocation.longitude,
      );
      setState(() {
        _placemark = placemarks.isNotEmpty ? placemarks[0] : null;
      });
    } catch (e) {
      setState(() {
        _placemark = null;
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
        await _analyzeImage();
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error taking photo: $e')));
    }
  }

  Future<void> _analyzeImage() async {
    if (_selectedImage == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await ClaudeService.analyzeIssue(_selectedImage!);
      setState(() {
        _titleController.text = result['title'] ?? '';
        _descriptionController.text = result['description'] ?? '';
        _selectedCategory = Issue.categoryFromString(result['category'] ?? '');
        _credibilityScore = ((result['credibility_score'] ?? 0) as num).toInt();
        _hasGenerated = true;
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error analyzing photo: $e')));

      setState(() {
        // Allow manual entry if AI analysis fails
        _hasGenerated = true;
        _showEditFields = true;
      });
    } finally {
      Navigator.of(context).pop();
    }
  }

  Future<void> _submitIssue() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Upload image if selected
      String? imageUrl;
      if (_selectedImage != null) {
        imageUrl = await SupabaseService.uploadImage(_selectedImage!, 'issues');
      }

      final marker = await SupabaseService.createMarker(
        MarkerType.issue,
        _selectedLocation,
      );

      await SupabaseService.createIssue(
        markerId: marker.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        category: _selectedCategory,
        imageUrl: imageUrl,
        credibilityScore: _credibilityScore,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Issue reported successfully! +10 points'),
          backgroundColor: Colors.green,
        ),
      );

      widget.onIssueReported();
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error reporting issue: $e')));
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  String _getCategoryDisplayName(IssueCategory category) {
    switch (category) {
      case IssueCategory.waste:
        return 'Waste';
      case IssueCategory.pollution:
        return 'Pollution';
      case IssueCategory.water:
        return 'Water';
      case IssueCategory.other:
        return 'Other';
    }
  }

  String _formatAddress(Placemark placemark) {
    final parts = <String>[];
    
    // Add street address
    if (placemark.street != null && placemark.street!.isNotEmpty) {
      parts.add(placemark.street!);
    }
    
    // Add locality (city)
    if (placemark.locality != null && placemark.locality!.isNotEmpty) {
      parts.add(placemark.locality!);
    }
    
    // Add administrative area (state/province)
    if (placemark.administrativeArea != null && placemark.administrativeArea!.isNotEmpty) {
      parts.add(placemark.administrativeArea!);
    }
    
    // Add postal code
    if (placemark.postalCode != null && placemark.postalCode!.isNotEmpty) {
      parts.add(placemark.postalCode!);
    }
    
    // Add country
    if (placemark.country != null && placemark.country!.isNotEmpty) {
      parts.add(placemark.country!);
    }
    
    return parts.isNotEmpty ? parts.join(', ') : 'Unknown location';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDarkMode ? darkModeDark : Colors.grey[50],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header with back button
                Row(
                  children: [
                    Container(
                      width: kFloatingButtonSize,
                      height: kFloatingButtonSize,
                      decoration: BoxDecoration(
                        color: isDarkMode ? darkModeMedium : lightModeDark,
                        borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                        boxShadow: kFloatingButtonShadow,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                          onTap: () => Navigator.pop(context),
                          child: Icon(
                            Icons.arrow_back_rounded,
                            color: isDarkMode ? highlight : Colors.white,
                            size: kFloatingButtonIconSize,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Report Issue',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? highlight : lightModeDark,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              Card(
                child: InkWell(
                  onTap: _pickImage,
                  child: Container(
                    height: 120,
                    padding: const EdgeInsets.all(16),
                    child: _selectedImage != null
                        ? Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  _selectedImage!,
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Photo Added',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text('Tap to change photo'),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.camera_alt,
                                size: 40,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 8),
                              Text('Tap to add photo'),
                            ],
                          ),
                  ),
                ),
              ),
              if (_hasGenerated && !_showEditFields) ...[
                const SizedBox(height: 16),
                Text(
                  _titleController.text,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(_descriptionController.text),
                const SizedBox(height: 8),
                Text('Category: ${_getCategoryDisplayName(_selectedCategory)}'),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        _showEditFields = true;
                      });
                    },
                    child: const Text('Edit'),
                  ),
                ),
              ],
              if (_showEditFields) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: 'Issue Title *',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                      borderSide: BorderSide(color: isDarkMode ? darkModeMedium : lightModeMedium),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                      borderSide: BorderSide(color: isDarkMode ? darkModeMedium : lightModeMedium),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                      borderSide: BorderSide(color: isDarkMode ? highlight : lightModeDark, width: 2),
                    ),
                    fillColor: isDarkMode ? darkModeMedium.withValues(alpha: 0.3) : Colors.white,
                    filled: true,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a title';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<IssueCategory>(
                  value: _selectedCategory,
                  decoration: InputDecoration(
                    labelText: 'Category *',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                      borderSide: BorderSide(color: isDarkMode ? darkModeMedium : lightModeMedium),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                      borderSide: BorderSide(color: isDarkMode ? darkModeMedium : lightModeMedium),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                      borderSide: BorderSide(color: isDarkMode ? highlight : lightModeDark, width: 2),
                    ),
                    fillColor: isDarkMode ? darkModeMedium.withValues(alpha: 0.3) : Colors.white,
                    filled: true,
                  ),
                  items: IssueCategory.values.map((category) {
                    return DropdownMenuItem(
                      value: category,
                      child: Text(_getCategoryDisplayName(category)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedCategory = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                      borderSide: BorderSide(color: isDarkMode ? darkModeMedium : lightModeMedium),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                      borderSide: BorderSide(color: isDarkMode ? darkModeMedium : lightModeMedium),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                      borderSide: BorderSide(color: isDarkMode ? highlight : lightModeDark, width: 2),
                    ),
                    fillColor: isDarkMode ? darkModeMedium.withValues(alpha: 0.3) : Colors.white,
                    filled: true,
                  ),
                  maxLines: 3,
                ),
              ],
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                height: kFloatingButtonSize,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: (_isSubmitting || !_hasGenerated) ? [
                      (isDarkMode ? darkModeMedium : lightModeDark).withValues(alpha: 0.5),
                      (isDarkMode ? darkModeMedium : lightModeDark).withValues(alpha: 0.5),
                    ] : [
                      isDarkMode ? darkModeMedium : lightModeDark,
                      isDarkMode ? darkModeDark : lightModeDark.withValues(alpha: 0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                  boxShadow: (_isSubmitting || !_hasGenerated) ? [] : kFloatingButtonShadow,
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                    onTap: (_isSubmitting || !_hasGenerated) ? null : _submitIssue,
                    child: Container(
                      alignment: Alignment.center,
                      child: _isSubmitting
                          ? CircularProgressIndicator(
                              color: isDarkMode ? highlight : Colors.white,
                              strokeWidth: 2,
                            )
                          : Text(
                              'Report Issue (+10 Points)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDarkMode ? highlight : Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Move location section to bottom
              Card(
                elevation: 0,
                color: isDarkMode ? darkModeMedium.withValues(alpha: 0.3) : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                  side: BorderSide(
                    color: isDarkMode ? darkModeMedium : lightModeMedium.withValues(alpha: 0.3),
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                  onTap: () async {
                    final result = await Navigator.push<LatLng>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LocationPickerScreen(
                          initialLocation: _selectedLocation,
                          title: 'Select Issue Location',
                        ),
                      ),
                    );
                    if (result != null) {
                      setState(() {
                        _selectedLocation = result;
                      });
                      _fetchPlacemark();
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_rounded,
                              color: isDarkMode ? highlight : lightModeDark,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Issue Location',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDarkMode ? highlight : lightModeDark,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.edit_rounded,
                              color: isDarkMode ? darkModeMedium : lightModeMedium,
                              size: 18,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _placemark != null
                              ? _formatAddress(_placemark!)
                              : 'Loading location...',
                          style: TextStyle(
                            color: isDarkMode ? darkModeMedium : Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap to change location',
                          style: TextStyle(
                            color: isDarkMode ? lightModeMedium : lightModeDark,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
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
