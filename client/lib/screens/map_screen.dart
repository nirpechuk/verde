import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:client/helpers/fab.dart';
import 'package:client/helpers/utils.dart';
import '../models/marker.dart';
import '../models/event.dart';
import '../services/supabase_service.dart';
import 'report_issue_screen.dart';
import 'create_event_screen.dart';
import 'marker_details_screen.dart';
import 'auth_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  LatLng _currentLocation = const LatLng(
    42.3601,
    -71.0589,
  ); // Default to Boston/MIT area
  List<AppMarker> _markers = [];
  List<Event> _events = [];
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
      // Load markers in current view bounds
      final southwest = LatLng(
        _currentLocation.latitude - 0.971,
        _currentLocation.longitude - 0.971,
      );
      final northeast = LatLng(
        _currentLocation.latitude + 0.971,
        _currentLocation.longitude + 0.971,
      );

      final markers = await SupabaseService.getMarkersInBounds(
        southwest,
        northeast,
      );
      final events = await SupabaseService.getEvents();

      setState(() {
        _markers = markers;
        _events = events;
      });
    } catch (e) {
      print('Error loading map data: $e');
    }
  }

  List<Marker> _buildFlutterMapMarkers() {
    List<Marker> mapMarkers = [];

    // Add current location marker first (so it appears behind other markers)
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
                color: Colors.blue.withValues(alpha: 0.2),
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
                    color: Colors.black.withValues(alpha: 0.3),
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

    // Add issue markers (red) - these will appear on top
    for (final marker in _markers.where((m) => m.type == MarkerType.issue)) {
      mapMarkers.add(
        Marker(
          point: marker.location,
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
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.warning, color: Colors.white, size: 20),
            ),
          ),
        ),
      );
    }

    // Add event markers (green)
    for (final marker in _markers.where((m) => m.type == MarkerType.event)) {
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

      mapMarkers.add(
        Marker(
          point: marker.location,
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
                    color: Colors.black.withValues(alpha: 0.3),
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
        ),
      );
    }

    return mapMarkers;
  }

  void _onMarkerTapped(AppMarker marker) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            MarkerDetailsScreen(marker: marker, onDataChanged: _loadMapData),
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
          builder: (context) =>
              const AuthScreen(actionContext: 'to report an issue'),
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
          builder: (context) =>
              const AuthScreen(actionContext: 'to create an event'),
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
        title: Text(
          'verde',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w300,
            fontFamily: 'Pacifico',
          ),
        ),
        titleTextStyle: const TextStyle(fontStyle: FontStyle.italic),
        leading: FloatingActionButton(
          heroTag: "theme_toggle",
          onPressed: _toggleMapTheme,
          backgroundColor: _isDarkMode ? lightBrown : darkGreen,
          child: Icon(
            _isDarkMode ? Icons.light_mode : Icons.dark_mode,
            color: tan,
          ),
        ),
        backgroundColor: _isDarkMode ? darkBrown : lightGreen,
        foregroundColor: _isDarkMode ? lightBrown : darkGreen,
        actions: [
          if (SupabaseService.isAuthenticated) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
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
                  MaterialPageRoute(builder: (context) => const AuthScreen()),
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
                MarkerLayer(markers: _buildFlutterMapMarkers()),
              ],
            ),

      floatingActionButton: Stack(
        children: [
          ExpandableFab(
            distance: kIconDistanceBetweenFab,
            backgroundColor: _isDarkMode ? tan : lightGreen,
            iconColor: _isDarkMode ? darkBrown : darkGreen,
            children: [
              ActionButton(
                onPressed: _onCreateEvent,
                backgroundColor: _isDarkMode ? tan : lightGreen,
                iconColor: _isDarkMode ? darkBrown : darkGreen,
                icon: const Icon(Icons.location_pin),
              ),
              ActionButton(
                onPressed: _onReportIssue,
                backgroundColor: _isDarkMode ? tan : lightGreen,
                iconColor: _isDarkMode ? darkBrown : darkGreen,
                icon: const Icon(Icons.add_alert),
              ),
            ],
          ),
        ],
      ),
    );
  }
}



// FloatingActionButton(
//   heroTag: "report_issue",
//   onPressed: _onReportIssue,
//   backgroundColor: Colors.red,
//   child: const Icon(Icons.add_alert, color: Colors.white),
// ),

// FloatingActionButton(
//   heroTag: "create_event",
//   onPressed: _onCreateEvent,
//   backgroundColor: Colors.green,
//   child: const Icon(Icons.add_circle, color: Colors.white),
// ),