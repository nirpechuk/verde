import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/marker.dart';
import '../models/event.dart';
import '../models/issue.dart';
import '../services/supabase_service.dart';
import 'marker_details_screen.dart';
import 'report_issue_screen.dart';
import 'create_event_screen.dart';
import 'auth_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  LatLng _currentLocation = const LatLng(42.3601, -71.0589); // Default to Boston/MIT area
  List<AppMarker> _markers = [];
  List<Event> _events = [];
  List<Issue> _issues = [];
  bool _isLoading = true;
  int _userPoints = 0;
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  Future<void> _initializeMap() async {
    await _getCurrentLocation();
    await _loadUserData();
    await _loadMapData();
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _getCurrentLocation() async {
    try {
      final permission = await Permission.location.request();
      if (permission.isGranted) {
        final position = await Geolocator.getCurrentPosition();
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });
      }
    } catch (e) {
      // Use default location if permission denied or error
      print('Location error: $e');
    }
  }

  Future<void> _loadUserData() async {
    try {
      if (SupabaseService.isAuthenticated) {
        final user = await SupabaseService.getCurrentUser();
        if (user != null) {
          setState(() {
            _userPoints = user.points;
          });
        }
      } else {
        setState(() {
          _userPoints = 0;
        });
      }
    } catch (e) {
      print('Error loading user data: $e');
    }
  }

  Future<void> _loadMapData() async {
    try {
      final markers = await SupabaseService.getMarkersInBounds(
        LatLng(_currentLocation.latitude - 0.1, _currentLocation.longitude - 0.1),
        LatLng(_currentLocation.latitude + 0.1, _currentLocation.longitude + 0.1),
      );
      final events = <Event>[];
      final issues = <Issue>[];
      
      // Load events and issues for each marker
      for (final marker in markers) {
        if (marker.type == MarkerType.event) {
          try {
            final event = await SupabaseService.getEventByMarkerId(marker.id);
            events.add(event);
          } catch (e) {
            print('Error loading event for marker ${marker.id}: $e');
          }
        } else if (marker.type == MarkerType.issue) {
          try {
            final issue = await SupabaseService.getIssueByMarkerId(marker.id);
            issues.add(issue);
          } catch (e) {
            print('Error loading issue for marker ${marker.id}: $e');
          }
        }
      }
      
      setState(() {
        _markers = markers;
        _events = events;
        _issues = issues;
      });
    } catch (e) {
      print('Error loading map data: $e');
    }
  }

  List<Marker> _buildFlutterMapMarkers() {
    List<Marker> mapMarkers = [];

    // Add current location marker (blue)
    mapMarkers.add(
      Marker(
        point: _currentLocation,
        width: 40,
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outer pulse ring
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
            ),
            // Inner location dot
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    // Filter markers: show only issues without linked events, and all events
    List<AppMarker> filteredMarkers = [];
    
    // Get all issue IDs that have linked events
    Set<String> issuesWithEvents = {};
    for (final event in _events) {
      if (event.issueId != null) {
        issuesWithEvents.add(event.issueId!);
      }
    }
    
    // Add markers based on filtering logic
    for (final marker in _markers) {
      if (marker.type == MarkerType.issue) {
        // Only show issue markers that don't have linked fix events
        final issue = _issues.where((i) => i.markerId == marker.id).firstOrNull;
        if (issue != null && !issuesWithEvents.contains(issue.id)) {
          filteredMarkers.add(marker);
        }
      } else {
        // Always show event markers
        filteredMarkers.add(marker);
      }
    }
    
    // Group filtered markers by location to handle overlapping
    Map<String, List<AppMarker>> markerGroups = {};
    for (final marker in filteredMarkers) {
      final key = '${marker.location.latitude.toStringAsFixed(6)}_${marker.location.longitude.toStringAsFixed(6)}';
      markerGroups[key] ??= [];
      markerGroups[key]!.add(marker);
    }
    
    // Process each location group
    for (final entry in markerGroups.entries) {
      final markers = entry.value;
      final location = markers.first.location;
      
      if (markers.length == 1) {
        // Single marker - place normally
        final marker = markers.first;
        mapMarkers.add(_createSingleMarker(marker));
      } else {
        // Multiple markers - arrange side by side
        for (int i = 0; i < markers.length; i++) {
          final marker = markers[i];
          // Offset each marker slightly to avoid overlap
          final offsetLat = location.latitude + (i - (markers.length - 1) / 2) * 0.00005;
          final offsetLocation = LatLng(offsetLat, location.longitude);
          
          mapMarkers.add(_createSingleMarker(marker, customLocation: offsetLocation));
        }
      }
    }


    return mapMarkers;
  }

  Marker _createSingleMarker(AppMarker marker, {LatLng? customLocation}) {
    final location = customLocation ?? marker.location;
    
    if (marker.type == MarkerType.issue) {
      return Marker(
        point: location,
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => _onMarkerTapped(marker),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.warning,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      );
    } else {
      // Event marker
      final event = _events.firstWhere(
        (e) => e.markerId == marker.id,
        orElse: () => Event(
          id: '',
          markerId: marker.id,
          title: 'Unknown Event',
          category: EventCategory.other,
          startTime: DateTime.now(),
          endTime: DateTime.now(),
          currentParticipants: 0,
          status: EventStatus.upcoming,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      return Marker(
        point: location,
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => _onMarkerTapped(marker),
          child: Container(
            decoration: BoxDecoration(
              color: event.isActive ? Colors.lightGreen : Colors.green,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              event.isActive ? Icons.flash_on : Icons.event,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      );
    }
  }

  void _onMarkerTapped(AppMarker marker) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MarkerDetailsScreen(
          marker: marker,
          onDataChanged: _loadMapData,
        ),
      ),
    );
  }

  void _toggleMapTheme() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
  }

  Future<void> _onReportIssue() async {
    if (!SupabaseService.isAuthenticated) {
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => const AuthScreen(
            actionContext: 'to report an issue',
          ),
        ),
      );
      
      if (result != true) return; // User cancelled or didn't authenticate
      await _loadUserData(); // Refresh user data after auth
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReportIssueScreen(
          initialLocation: _currentLocation,
          onIssueReported: () {
            _loadMapData();
            _loadUserData();
          },
        ),
      ),
    );
  }

  Future<void> _onCreateEvent() async {
    if (!SupabaseService.isAuthenticated) {
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => const AuthScreen(
            actionContext: 'to create an event',
          ),
        ),
      );
      
      if (result != true) return; // User cancelled or didn't authenticate
      await _loadUserData(); // Refresh user data after auth
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateEventScreen(
          initialLocation: _currentLocation,
          onEventCreated: () {
            _loadMapData();
            _loadUserData();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EcoAction'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          if (SupabaseService.isAuthenticated) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.stars, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '$_userPoints',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.account_circle),
              onSelected: (value) async {
                if (value == 'signout') {
                  await SupabaseService.signOut();
                  await _loadUserData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Signed out successfully'),
                      backgroundColor: Colors.blue,
                    ),
                  );
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'signout',
                  child: Row(
                    children: [
                      const Icon(Icons.logout, color: Colors.red),
                      const SizedBox(width: 8),
                      const Text('Sign Out'),
                    ],
                  ),
                ),
              ],
            ),
          ] else ...[
            TextButton.icon(
              onPressed: () async {
                final result = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AuthScreen(),
                  ),
                );
                if (result == true) {
                  await _loadUserData();
                }
              },
              icon: const Icon(Icons.login, color: Colors.white),
              label: const Text(
                'Sign In',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentLocation,
                initialZoom: 15.0,
                minZoom: 5.0,
                maxZoom: 90.0,
                onMapEvent: (event) {
                  if (event is MapEventMoveEnd) {
                    // Optionally reload markers when map moves
                    // _loadMapData();
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: _isDarkMode 
                    ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                    : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.example.ecoaction',
                  retinaMode: RetinaMode.isHighDensity(context),
                ),
                MarkerLayer(
                  markers: _buildFlutterMapMarkers(),
                ),
              ],
            ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "theme_toggle",
            onPressed: _toggleMapTheme,
            backgroundColor: _isDarkMode ? Colors.yellow[700] : Colors.grey[800],
            child: Icon(
              _isDarkMode ? Icons.light_mode : Icons.dark_mode,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: "report_issue",
            onPressed: _onReportIssue,
            backgroundColor: Colors.red,
            child: const Icon(Icons.add_alert, color: Colors.white),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: "create_event",
            onPressed: _onCreateEvent,
            backgroundColor: Colors.green,
            child: const Icon(Icons.add_circle, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
