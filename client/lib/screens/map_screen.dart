import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  // Realtime subscriptions
  RealtimeChannel? _markersChannel;
  RealtimeChannel? _eventsChannel;
  RealtimeChannel? _issuesChannel;

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  @override
  void dispose() {
    // Clean up realtime subscriptions
    _markersChannel?.unsubscribe();
    _eventsChannel?.unsubscribe();
    _issuesChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _initializeMap() async {
    await _getCurrentLocation();
    await _loadUserData();
    await _loadMapData();
    _setupRealtimeSubscriptions();
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

  void _setupRealtimeSubscriptions() {
    final client = Supabase.instance.client;

    // Subscribe to markers table changes
    _markersChannel = client
        .channel('markers_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'markers',
          callback: (payload) {
            print('Markers change detected: ${payload.eventType}');
            _loadMapData(); // Refresh map data when markers change
          },
        )
        .subscribe();

    // Subscribe to events table changes
    _eventsChannel = client
        .channel('events_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'events',
          callback: (payload) {
            print('Events change detected: ${payload.eventType}');
            _loadMapData(); // Refresh map data when events change
          },
        )
        .subscribe();

    // Subscribe to issues table changes
    _issuesChannel = client
        .channel('issues_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'issues',
          callback: (payload) {
            print('Issues change detected: ${payload.eventType}');
            _loadMapData(); // Refresh map data when issues change
          },
        )
        .subscribe();
  }

  Future<void> _loadMapData() async {
    try {
      const bound = 0.971;
      // Load markers in current view bounds
      final southwest = LatLng(
        _currentLocation.latitude - bound,
        _currentLocation.longitude - bound,
      );
      final northeast = LatLng(
        _currentLocation.latitude + bound,
        _currentLocation.longitude + bound,
      );

      final markers = await SupabaseService.getMarkersInBounds(
        southwest,
        northeast,
      );
      final events = await SupabaseService.getEvents();

      // Get issue IDs that have linked fix events
      final issueIdsWithEvents =
          await SupabaseService.getIssueIdsWithLinkedEvents();

      // Filter out issue markers that have linked fix events
      final filteredMarkers = <AppMarker>[];
      for (final marker in markers) {
        if (marker.type == MarkerType.issue) {
          // Load the issue to check if it has a linked event
          try {
            final issue = await SupabaseService.getIssueByMarkerId(marker.id);
            if (!issueIdsWithEvents.contains(issue.id)) {
              filteredMarkers.add(marker);
            }
          } catch (e) {
            // If we can't load the issue, include the marker anyway
            filteredMarkers.add(marker);
          }
        } else {
          // Always include event markers
          filteredMarkers.add(marker);
        }
      }

      setState(() {
        _markers = filteredMarkers;
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

    // Add issue markers with aesthetic colors - these will appear on top
    for (final marker in _markers.where((m) => m.type == MarkerType.issue)) {
      mapMarkers.add(
        Marker(
          point: marker.location,
          width: 44,
          height: 44,
          child: GestureDetector(
            onTap: () => _onMarkerTapped(marker),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _isDarkMode ? darkModeMedium : lightModeDark,
                    _isDarkMode
                        ? darkModeDark
                        : lightModeDark.withValues(alpha: 0.8),
                  ],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _isDarkMode
                      ? highlight.withValues(alpha: 0.8)
                      : Colors.white,
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: (_isDarkMode ? darkModeMedium : lightModeDark)
                        .withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Transform.translate(
                offset: const Offset(0, -1),
                child: Icon(
                  Icons.warning_rounded,
                  color: _isDarkMode ? highlight : Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Add event markers with aesthetic colors
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

      // Different colors for active vs upcoming events
      final isActive = event.isActive;
      final baseColor = _isDarkMode ? darkModeMedium : lightModeMedium;
      final accentColor = _isDarkMode ? highlight : highlight;

      mapMarkers.add(
        Marker(
          point: marker.location,
          width: 44,
          height: 44,
          child: GestureDetector(
            onTap: () => _onMarkerTapped(marker),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isActive
                      ? [accentColor, accentColor.withValues(alpha: 0.8)]
                      : [baseColor, baseColor.withValues(alpha: 0.8)],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isActive
                      ? (_isDarkMode ? darkModeDark : lightModeDark)
                      : (_isDarkMode ? darkModeDark : Colors.white),
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: (isActive ? accentColor : baseColor).withValues(
                      alpha: 0.3,
                    ),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                  // Add a subtle glow for active events
                  if (isActive)
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 0),
                      spreadRadius: 2,
                    ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(
                isActive ? Icons.flash_on_rounded : Icons.event_rounded,
                color: isActive
                    ? (_isDarkMode ? darkModeDark : lightModeDark)
                    : (_isDarkMode ? darkModeDark : Colors.white),
                size: 22,
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // Main map
                FlutterMap(
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

                // Dark mode toggle button - top left
                Positioned(
                  top:
                      MediaQuery.of(context).padding.top +
                      kFloatingButtonPadding,
                  left: kFloatingButtonPadding,
                  child: Container(
                    width: kFloatingButtonSize,
                    height: kFloatingButtonSize,
                    decoration: BoxDecoration(
                      color: _isDarkMode ? darkModeMedium : lightModeDark,
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
                        onTap: _toggleMapTheme,
                        child: Container(
                          width: kFloatingButtonSize,
                          height: kFloatingButtonSize,
                          alignment: Alignment.center,
                          child: Icon(
                            _isDarkMode ? Icons.light_mode : Icons.dark_mode,
                            color: highlight,
                            size: kFloatingButtonIconSize,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // User info and account - top right
                Positioned(
                  top:
                      MediaQuery.of(context).padding.top +
                      kFloatingButtonPadding,
                  right: kFloatingButtonPadding,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Stars display (only when authenticated)
                      if (SupabaseService.isAuthenticated) ...[
                        Container(
                          height: kFloatingButtonSize,
                          padding: const EdgeInsets.symmetric(
                            horizontal: kFloatingButtonPadding,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: _isDarkMode
                                ? darkModeDark.withValues(alpha: 0.95)
                                : lightModeMedium.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(
                              kFloatingButtonBorderRadius,
                            ),
                            boxShadow: kFloatingButtonShadow,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.stars,
                                size: kFloatingButtonIconSize - 4,
                                color: _isDarkMode ? darkModeMedium : highlight,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$_userPoints',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: _isDarkMode
                                      ? darkModeMedium
                                      : highlight,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: kFloatingButtonSpacing),
                      ],

                      // Account button
                      Container(
                        width: kFloatingButtonSize,
                        height: kFloatingButtonSize,
                        decoration: BoxDecoration(
                          color: _isDarkMode
                              ? darkModeDark.withValues(alpha: 0.95)
                              : lightModeMedium.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(
                            kFloatingButtonBorderRadius,
                          ),
                          boxShadow: kFloatingButtonShadow,
                        ),
                        child: SupabaseService.isAuthenticated
                            ? PopupMenuButton<String>(
                                icon: Icon(
                                  Icons.account_circle,
                                  color: _isDarkMode
                                      ? darkModeMedium
                                      : highlight,
                                  size: kFloatingButtonIconSize + 4,
                                ),
                                onSelected: (value) async {
                                  if (value == 'signout') {
                                    await SupabaseService.signOut();
                                    await _loadUserData();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Signed out successfully',
                                        ),
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
                                        const Icon(
                                          Icons.logout,
                                          color: Colors.red,
                                        ),
                                        const SizedBox(width: 8),
                                        const Text('Sign Out'),
                                      ],
                                    ),
                                  ),
                                ],
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    kFloatingButtonBorderRadius,
                                  ),
                                ),
                                offset: const Offset(0, 8),
                              )
                            : Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                  kFloatingButtonBorderRadius,
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(
                                    kFloatingButtonBorderRadius,
                                  ),
                                  onTap: () async {
                                    final result = await Navigator.push<bool>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const AuthScreen(),
                                      ),
                                    );
                                    if (result == true) {
                                      await _loadUserData();
                                    }
                                  },
                                  child: Container(
                                    width: kFloatingButtonSize,
                                    height: kFloatingButtonSize,
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.login,
                                      color: _isDarkMode
                                          ? darkModeMedium
                                          : lightModeDark,
                                      size: kFloatingButtonIconSize + 4,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

      floatingActionButton: Stack(
        children: [
          ExpandableFab(
            distance: kFabButtonSpacing,
            backgroundColor: _isDarkMode ? highlight : lightModeMedium,
            iconColor: _isDarkMode ? darkModeDark : highlight,
            children: [
              ActionButton(
                onPressed: _onCreateEvent,
                backgroundColor: _isDarkMode ? highlight : lightModeMedium,
                iconColor: _isDarkMode ? darkModeDark : lightModeDark,
                icon: const Icon(Icons.location_pin),
              ),
              ActionButton(
                onPressed: _onReportIssue,
                backgroundColor: _isDarkMode ? highlight : lightModeMedium,
                iconColor: _isDarkMode ? darkModeDark : lightModeDark,
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
