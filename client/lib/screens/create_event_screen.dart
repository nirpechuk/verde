import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import '../models/event.dart';
import '../models/marker.dart';
import '../services/supabase_service.dart';
import '../widgets/location_picker.dart';
import '../widgets/mini_map.dart';
import '../helpers/utils.dart';

class CreateEventScreen extends StatefulWidget {
  final LatLng? initialLocation;
  final VoidCallback onEventCreated;
  final bool isDarkMode;

  const CreateEventScreen({
    super.key,
    this.initialLocation,
    required this.onEventCreated,
    required this.isDarkMode,
  });

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _maxParticipantsController = TextEditingController();

  EventCategory _selectedCategory = EventCategory.cleanup;
  DateTime _startDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _startTime = const TimeOfDay(hour: 10, minute: 0);
  DateTime _endDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _endTime = const TimeOfDay(hour: 12, minute: 0);
  bool _isSubmitting = false;
  late LatLng _selectedLocation;
  File? _selectedImage;
  Placemark? _placemark;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation ?? const LatLng(42.3601, -71.0589);
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

  Future<void> _selectStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() {
        _startDate = date;
        // Ensure end date is not before start date
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      });
    }
  }

  Future<void> _selectStartTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (time != null) {
      setState(() {
        _startTime = time;
      });
    }
  }

  Future<void> _selectEndDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() {
        _endDate = date;
      });
    }
  }

  Future<void> _selectEndTime() async {
    final time = await showTimePicker(context: context, initialTime: _endTime);
    if (time != null) {
      setState(() {
        _endTime = time;
      });
    }
  }

  DateTime get _startDateTime => DateTime(
    _startDate.year,
    _startDate.month,
    _startDate.day,
    _startTime.hour,
    _startTime.minute,
  );

  DateTime get _endDateTime => DateTime(
    _endDate.year,
    _endDate.month,
    _endDate.day,
    _endTime.hour,
    _endTime.minute,
  );

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
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error taking photo: $e')));
    }
  }

  Future<void> _submitEvent() async {
    if (!_formKey.currentState!.validate()) return;

    if (_endDateTime.isBefore(_startDateTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Upload image if selected
      String? imageUrl;
      if (_selectedImage != null) {
        imageUrl = await SupabaseService.uploadImage(_selectedImage!, 'events');
      }

      // Create marker first
      final marker = await SupabaseService.createMarker(
        MarkerType.event,
        _selectedLocation,
      );

      // Create event
      await SupabaseService.createEvent(
        markerId: marker.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        category: _selectedCategory,
        startTime: _startDateTime,
        endTime: _endDateTime,
        maxParticipants: _maxParticipantsController.text.trim().isEmpty
            ? null
            : int.tryParse(_maxParticipantsController.text.trim()),
        imageUrl: imageUrl,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Event created successfully! +20 points'),
          backgroundColor: Colors.green,
        ),
      );

      widget.onEventCreated();
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error creating event: $e')));
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  String _formatAddress(Placemark placemark) {
    final parts = <String>[];
    
    if (placemark.street != null && placemark.street!.isNotEmpty) {
      parts.add(placemark.street!);
    }
    if (placemark.locality != null && placemark.locality!.isNotEmpty) {
      parts.add(placemark.locality!);
    }
    if (placemark.administrativeArea != null && placemark.administrativeArea!.isNotEmpty) {
      parts.add(placemark.administrativeArea!);
    }
    
    return parts.isNotEmpty ? parts.join(', ') : 'Unknown location';
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = widget.isDarkMode;

    return Scaffold(
      backgroundColor: isDarkMode ? darkModeDark : Colors.grey[50],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
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
                          color: isDarkMode ? darkModeMedium : lightModeMedium,
                          borderRadius: BorderRadius.circular(
                            kFloatingButtonBorderRadius,
                          ),
                          boxShadow: kFloatingButtonShadow,
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(
                            kFloatingButtonBorderRadius,
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(
                              kFloatingButtonBorderRadius,
                            ),
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
                          'Create Event',
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
                    elevation: 0,
                    color: isDarkMode
                        ? darkModeMedium.withValues(alpha: 0.3)
                        : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                      side: BorderSide(
                        color: isDarkMode
                            ? darkModeMedium
                            : lightModeMedium.withValues(alpha: 0.3),
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
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
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Photo Added',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isDarkMode ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                        Text(
                                          'Tap to change photo',
                                          style: TextStyle(
                                            color: isDarkMode ? Colors.white.withOpacity(0.7) : Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.camera_alt,
                                    size: 40,
                                    color: isDarkMode ? Colors.white.withOpacity(0.6) : Colors.grey,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Tap to add photo (optional)',
                                    style: TextStyle(
                                      color: isDarkMode ? Colors.white.withOpacity(0.8) : Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: 'Event Title *',
                      labelStyle: TextStyle(
                        color: isDarkMode ? Colors.white.withOpacity(0.8) : Colors.grey[700],
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          kFloatingButtonBorderRadius,
                        ),
                        borderSide: BorderSide(
                          color: isDarkMode ? darkModeMedium : lightModeMedium.withValues(alpha: 0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          kFloatingButtonBorderRadius,
                        ),
                        borderSide: BorderSide(
                          color: isDarkMode ? darkModeMedium : lightModeMedium.withValues(alpha: 0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          kFloatingButtonBorderRadius,
                        ),
                        borderSide: BorderSide(
                          color: isDarkMode ? highlight : lightModeDark,
                          width: 2,
                        ),
                      ),
                      hintText: 'e.g., Community Park Cleanup',
                      fillColor: isDarkMode
                          ? darkModeMedium.withValues(alpha: 0.3)
                          : Colors.white,
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
                  DropdownButtonFormField<EventCategory>(
                    value: _selectedCategory,
                    dropdownColor: isDarkMode 
                        ? darkModeMedium.withValues(alpha: 0.95)
                        : Colors.white,
                    decoration: InputDecoration(
                      labelText: 'Category *',
                      labelStyle: TextStyle(
                        color: isDarkMode ? Colors.white.withOpacity(0.8) : Colors.grey[700],
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          kFloatingButtonBorderRadius,
                        ),
                        borderSide: BorderSide(
                          color: isDarkMode ? darkModeMedium : lightModeMedium.withValues(alpha: 0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          kFloatingButtonBorderRadius,
                        ),
                        borderSide: BorderSide(
                          color: isDarkMode ? darkModeMedium : lightModeMedium.withValues(alpha: 0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          kFloatingButtonBorderRadius,
                        ),
                        borderSide: BorderSide(
                          color: isDarkMode ? highlight : lightModeDark,
                          width: 2,
                        ),
                      ),
                      fillColor: isDarkMode
                          ? darkModeMedium.withValues(alpha: 0.3)
                          : Colors.white,
                      filled: true,
                    ),
                    items: EventCategory.values.map((category) {
                      return DropdownMenuItem(
                        value: category,
                        child: Text(
                          _getCategoryDisplayName(category),
                          style: TextStyle(
                            color: isDarkMode ? Colors.white.withOpacity(0.8) : Colors.grey[700],
                          ),
                        ),
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
                      labelText: 'Description (Optional)',
                      labelStyle: TextStyle(
                        color: isDarkMode ? Colors.white.withOpacity(0.8) : Colors.grey[700],
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          kFloatingButtonBorderRadius,
                        ),
                        borderSide: BorderSide(
                          color: isDarkMode ? darkModeMedium : lightModeMedium.withValues(alpha: 0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          kFloatingButtonBorderRadius,
                        ),
                        borderSide: BorderSide(
                          color: isDarkMode ? darkModeMedium : lightModeMedium.withValues(alpha: 0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          kFloatingButtonBorderRadius,
                        ),
                        borderSide: BorderSide(
                          color: isDarkMode ? highlight : lightModeDark,
                          width: 2,
                        ),
                      ),
                      hintText: 'Event details, what to bring, etc...',
                      fillColor: isDarkMode
                          ? darkModeMedium.withValues(alpha: 0.3)
                          : Colors.white,
                      filled: true,
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          elevation: 0,
                          color: isDarkMode
                              ? darkModeMedium.withValues(alpha: 0.3)
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                            side: BorderSide(
                              color: isDarkMode
                                  ? darkModeMedium
                                  : lightModeMedium.withValues(alpha: 0.3),
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                            onTap: _selectStartDate,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_today,
                                        size: 16,
                                        color: isDarkMode ? highlight : lightModeDark,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Start Date',
                                        style: TextStyle(
                                          color: isDarkMode ? Colors.white.withOpacity(0.8) : Colors.grey[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_startDate.month.toString().padLeft(2, '0')}/${_startDate.day.toString().padLeft(2, '0')}/${_startDate.year}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isDarkMode ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Card(
                          elevation: 0,
                          color: isDarkMode
                              ? darkModeMedium.withValues(alpha: 0.3)
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                            side: BorderSide(
                              color: isDarkMode
                                  ? darkModeMedium
                                  : lightModeMedium.withValues(alpha: 0.3),
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                            onTap: _selectStartTime,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.access_time,
                                        size: 16,
                                        color: isDarkMode ? highlight : lightModeDark,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Start Time',
                                        style: TextStyle(
                                          color: isDarkMode ? Colors.white.withOpacity(0.8) : Colors.grey[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _startTime.format(context),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isDarkMode ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          elevation: 0,
                          color: isDarkMode
                              ? darkModeMedium.withValues(alpha: 0.3)
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                            side: BorderSide(
                              color: isDarkMode
                                  ? darkModeMedium
                                  : lightModeMedium.withValues(alpha: 0.3),
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                            onTap: _selectEndDate,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_today,
                                        size: 16,
                                        color: isDarkMode ? highlight : lightModeDark,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'End Date',
                                        style: TextStyle(
                                          color: isDarkMode ? Colors.white.withOpacity(0.8) : Colors.grey[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_endDate.month.toString().padLeft(2, '0')}/${_endDate.day.toString().padLeft(2, '0')}/${_endDate.year}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isDarkMode ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Card(
                          elevation: 0,
                          color: isDarkMode
                              ? darkModeMedium.withValues(alpha: 0.3)
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                            side: BorderSide(
                              color: isDarkMode
                                  ? darkModeMedium
                                  : lightModeMedium.withValues(alpha: 0.3),
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                            onTap: _selectEndTime,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.access_time,
                                        size: 16,
                                        color: isDarkMode ? highlight : lightModeDark,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'End Time',
                                        style: TextStyle(
                                          color: isDarkMode ? Colors.white.withOpacity(0.8) : Colors.grey[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _endTime.format(context),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isDarkMode ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _maxParticipantsController,
                    decoration: InputDecoration(
                      labelText: 'Max Participants (Optional)',
                      labelStyle: TextStyle(
                        color: isDarkMode ? Colors.white.withOpacity(0.8) : Colors.grey[700],
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          kFloatingButtonBorderRadius,
                        ),
                        borderSide: BorderSide(
                          color: isDarkMode ? darkModeMedium : lightModeMedium.withValues(alpha: 0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          kFloatingButtonBorderRadius,
                        ),
                        borderSide: BorderSide(
                          color: isDarkMode ? darkModeMedium : lightModeMedium.withValues(alpha: 0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          kFloatingButtonBorderRadius,
                        ),
                        borderSide: BorderSide(
                          color: isDarkMode ? highlight : lightModeDark,
                          width: 2,
                        ),
                      ),
                      hintText: 'Leave empty for unlimited',
                      fillColor: isDarkMode
                          ? darkModeMedium.withValues(alpha: 0.3)
                          : Colors.white,
                      filled: true,
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value != null && value.trim().isNotEmpty) {
                        final number = int.tryParse(value.trim());
                        if (number == null || number <= 0) {
                          return 'Please enter a valid positive number';
                        }
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 0,
                    color: isDarkMode
                        ? darkModeMedium.withValues(alpha: 0.3)
                        : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        kFloatingButtonBorderRadius,
                      ),
                      side: BorderSide(
                        color: isDarkMode
                            ? darkModeMedium
                            : lightModeMedium.withValues(alpha: 0.3),
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(
                        kFloatingButtonBorderRadius,
                      ),
                      onTap: () async {
                        final result = await Navigator.push<LatLng>(
                          context,
                          MaterialPageRoute(
                            builder: (context) => LocationPickerScreen(
                              initialLocation: _selectedLocation,
                              title: 'Select Event Location',
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
                                  'Event Location',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isDarkMode
                                        ? highlight
                                        : lightModeDark,
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  Icons.edit_rounded,
                                  color: isDarkMode
                                      ? darkModeMedium
                                      : lightModeMedium,
                                  size: 18,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _placemark != null
                                            ? _formatAddress(_placemark!)
                                            : 'Loading address...',
                                        style: TextStyle(
                                          color: isDarkMode
                                              ? Colors.white.withOpacity(0.8)
                                              : Colors.grey[600],
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Tap to change location',
                                        style: TextStyle(
                                          color: isDarkMode
                                              ? lightModeMedium
                                              : lightModeDark,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                MiniMap(
                                  location: _selectedLocation,
                                  height: 80,
                                  width: 80,
                                  borderRadius: 8,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    height: kFloatingButtonSize,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _isSubmitting
                            ? [
                              (isDarkMode ? darkModeMedium : lightModeDark)
                                  .withValues(alpha: 0.5),
                              (isDarkMode ? darkModeMedium : lightModeDark)
                                  .withValues(alpha: 0.5),
                            ]
                          : [
                              isDarkMode ? darkModeMedium : lightModeDark,
                              isDarkMode
                                  ? darkModeDark
                                  : lightModeDark.withValues(alpha: 0.8),
                            ],
                      ),
                      borderRadius: BorderRadius.circular(
                        kFloatingButtonBorderRadius,
                      ),
                      boxShadow: _isSubmitting ? [] : kFloatingButtonShadow,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(
                        kFloatingButtonBorderRadius,
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                          kFloatingButtonBorderRadius,
                        ),
                        onTap: _isSubmitting ? null : _submitEvent,
                        child: Container(
                          alignment: Alignment.center,
                          child: _isSubmitting
                              ? CircularProgressIndicator(
                                  color: isDarkMode ? highlight : Colors.white,
                                  strokeWidth: 2,
                                )
                              : Text(
                                  'Create Event (+20 Points)',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isDarkMode
                                        ? highlight
                                        : Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getCategoryDisplayName(EventCategory category) {
    switch (category) {
      case EventCategory.cleanup:
        return 'Cleanup';
      case EventCategory.advocacy:
        return 'Advocacy';
      case EventCategory.education:
        return 'Education';
      case EventCategory.other:
        return 'Volunteering';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _maxParticipantsController.dispose();
    super.dispose();
  }
}
