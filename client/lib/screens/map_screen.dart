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
    42.35857,
    -71.09635,
  ); // Default to Boston/MIT area
  List<AppMarker> _markers = [];
  List<Event> _events = [];
  // Store vote statistics for each issue marker to determine alpha transparency
  // Map structure: markerId -> {upvotes: int, downvotes: int, total: int, score: int}
  Map<String, Map<String, int>> _markerVoteStats = {};
  bool _isLoading = true;
  int _userPoints = 0;
  bool _isDarkMode = false;

  // Realtime subscriptions
  RealtimeChannel? _markersChannel;
  RealtimeChannel? _eventsChannel;
  RealtimeChannel? _issuesChannel;
  RealtimeChannel? _issueVotesChannel;

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

  Future<bool> _isEnabled() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled don't continue
      // accessing the position and request users of the 
      // App to enable the location services.
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied, next time you could try
        // requesting permissions again (this is also where
        // Android's shouldShowRequestPermissionRationale 
        // returned true. According to Android guidelines
        // your App should show an explanatory UI now.
        return Future.error('Location permissions are denied');
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately. 
      return Future.error(
        'Location permissions are permanently denied, we cannot request permissions.');
    } 

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    return true;
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool working = await _isEnabled();

      try {
        final position = await Geolocator.getCurrentPosition();
        final double bostonLat = 42.3601;
        final double bostonLng = -71.0589;
        final double distanceThreshold = 0.01;
        final double distance = Geolocator.distanceBetween(
          _currentLocation.latitude,
          _currentLocation.longitude,
          position.latitude,
          position.longitude,
        );
        if (distance < distanceThreshold) {
          setState(() {
            _currentLocation = LatLng(position.latitude, position.longitude);
          });
        } else {
          setState(() {
            _currentLocation = LatLng(bostonLat, bostonLng);
          });
        }
      } catch (e) {
        // Use default location if permission denied or error
        print('Location error: $e');
      }
    } catch (e) {
      print('Error checking location services or permissions: $e');
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

      // Filter out issue markers that have linked fix events and load vote stats
      final filteredMarkers = <AppMarker>[];
      final Map<String, Map<String, int>> voteStats = {};

      for (final marker in markers) {
        if (marker.type == MarkerType.issue) {
          // Load the issue to check if it has a linked event
          try {
            final issue = await SupabaseService.getIssueByMarkerId(marker.id);
            if (!issueIdsWithEvents.contains(issue.id)) {
              filteredMarkers.add(marker);
              // Load vote statistics for this issue marker
              final issueVoteStats = await SupabaseService.getIssueVoteStats(
                issue.id,
              );
              // Add credibility score to vote stats
              issueVoteStats['credibility'] = issue.credibilityScore;
              voteStats[marker.id] = issueVoteStats;
            }
          } catch (e) {
            // If we can't load the issue, include the marker anyway with default vote stats
            filteredMarkers.add(marker);
            voteStats[marker.id] = {
              'upvotes': 0,
              'downvotes': 0,
              'total': 0,
              'score': 0,
              'credibility': 0,
            };
          }
        } else {
          // Always include event markers
          filteredMarkers.add(marker);
        }
      }

      setState(() {
        _markers = filteredMarkers;
        _events = events;
        _markerVoteStats = voteStats;
      });
    } catch (e) {
      print('Error loading map data: $e');
    }
  }

  List<Marker> _buildFlutterMapMarkers() {
    List<Marker> mapMarkers = [];

    // Add event markers with aesthetic colors (skip past events)
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

      // Skip events that have already ended
      if (DateTime.now().isAfter(event.endTime)) {
        continue;
      }

      // Different colors for active vs upcoming events
      final isActive = event.isActive;
      final baseColor = _isDarkMode ? darkModeMedium : lightModeMedium;
      final accentColor = _isDarkMode ? highlight : highlight;
      
      // Calculate outline effect based on event timing
      final outlineEffect = _calculateEventOutlineEffect(event);
      final outlineColor = outlineEffect['color'] as Color;
      final outlineAlpha = outlineEffect['alpha'] as double;

      mapMarkers.add(
        Marker(
          point: marker.location,
          width: 44,
          height: 44,
          child: GestureDetector(
            onTap: () => _onMarkerTapped(marker),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Main marker container
                Container(
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
                      ? (_isDarkMode ? highlight : lightModeDark)
                      : (_isDarkMode ? highlight : Colors.white),
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
                        ? (_isDarkMode ? highlight : lightModeDark)
                        : (_isDarkMode ? highlight : Colors.white),
                    size: 22,
                  ),
                ),
                // Time-based outline glow
                if (outlineAlpha > 0.1)
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: outlineColor.withValues(alpha: outlineAlpha),
                        width: 3.0,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }


    // Add issue markers with red outline based on credibility
    // Red outline alpha is based on both vote score and credibility score
    for (final marker in _markers.where((m) => m.type == MarkerType.issue)) {
      // Get vote statistics and credibility for this marker
      final voteStats = _markerVoteStats[marker.id] ?? {'score': 0, 'credibility': 0};
      final voteScore = voteStats['score'] ?? 0;
      final credibilityScore = voteStats['credibility'] ?? 0;
      final redOutlineAlpha = _calculateRedOutlineAlpha(voteScore, credibilityScore);

      mapMarkers.add(
        Marker(
          point: marker.location,
          width: 44,
          height: 44,
          child: GestureDetector(
            onTap: () => _onMarkerTapped(marker),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Main marker container
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _isDarkMode ? darkModeDark : lightModeDark,
                        _isDarkMode
                            ? darkModeDark.withValues(alpha: 0.8)
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
                // Red warning outline for low credibility/vote scores
                if (redOutlineAlpha > 0.1)
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.red.withValues(alpha: redOutlineAlpha),
                        width: 3.0,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // Add current location marker last (so it appears above other markers)
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

    return mapMarkers;
  }

  void _onMarkerTapped(AppMarker marker) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MarkerDetailsScreen(
          marker: marker,
          isDarkMode: _isDarkMode,
          onDataChanged: () {
            _loadMapData(); // Reload map data including vote statistics
            _loadUserData(); // Reload user data as well
          },
        ),
      ),
    );
  }

  void _toggleMapTheme() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
  }


  double _calculateRedOutlineAlpha(int voteScore, int credibilityScore) {
    // Calculate alpha for red outline based on both vote score and credibility
    // Higher scores = more visible red outline (higher alpha)
    // Range: 0.0 (low scores) to 0.8 (high scores)
    
    // Normalize vote score (typically ranges from -10 to +10)
    final normalizedVoteScore = (voteScore + 5) / 10.0; // 0.0 to 1.0
    
    // Normalize credibility score (ranges from 0 to 10)
    final normalizedCredibilityScore = credibilityScore / 10.0; // 0.0 to 1.0
    
    // Average the two scores (higher = more credible/well-voted)
    final averageScore = (normalizedVoteScore + normalizedCredibilityScore) / 2.0;
    
    // Higher scores give higher alpha (more visible red outline)
    final outlineAlpha = averageScore * 0.8;
    
    return outlineAlpha.clamp(0.0, 0.8);
  }

  Map<String, dynamic> _calculateEventOutlineEffect(Event event) {
    final now = DateTime.now();
    final startTime = event.startTime;
    final endTime = event.endTime;
    
    // Check if event is currently happening
    if (now.isAfter(startTime) && now.isBefore(endTime)) {
      // Calculate time pulse phase (0.0 - 1.0)
      final pulsePhase = (now.microsecond / Duration.microsecondsPerMillisecond) % 1000 / 1000;
      final pulseAlpha = pulsePhase < 0.5 ? pulsePhase * 2 : 1 - (pulsePhase - 0.5) * 2;
      
      return {
        'color': Colors.yellow,
        'alpha': pulseAlpha,
        'description': 'currently_occurring'
      };
    }
    
    // Calculate time until event starts (in hours)
    final hoursUntilStart = startTime.difference(now).inHours;
    final hoursAfterEnd = now.difference(endTime).inHours;
    
    
    // Event is in the future
    if (hoursUntilStart <= 1) {
      // Very soon (within 1 hour) - bright yellow
      return {
        'color': Colors.orange,
        'alpha': 0.7,
        'description': 'very_soon'
      };
    } else if (hoursUntilStart <= 6) {
      // Soon (within 6 hours) - orange
      return {
        'color': Colors.orange,
        'alpha': 0.6,
        'description': 'soon'
      };
    } else if (hoursUntilStart <= 24) {
      // Today (within 24 hours) - light orange
      return {
        'color': Colors.orange,
        'alpha': 0.5,
        'description': 'today'
      };
    } else if (hoursUntilStart <= 168) { // 7 days
      // This week - yellow with increasing intensity
      final intensity = 0.5 * ((hoursUntilStart - 24)/ 144.0).clamp(0.0, 1);
      return {
        'color': Colors.orange,
        'alpha': intensity,
        'description': 'this_week'
      };
    } else {
      // Too far out - minimal white glow
      return {
        'color': Colors.white,
        'alpha': 0.1,
        'description': 'far_future'
      };
    }
  }

  Future<void> _onReportIssue() async {
    if (!SupabaseService.isAuthenticated) {
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) =>
              AuthScreen(actionContext: 'to report an issue', isDarkMode: _isDarkMode),
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
          },
          isDarkMode: _isDarkMode,
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
              AuthScreen(actionContext: 'to create an event', isDarkMode: _isDarkMode),
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
          },
          isDarkMode: _isDarkMode,
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
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
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

                // Dark mode toggle button - top left (glass style)
                Positioned(
                  top:
                      MediaQuery.of(context).padding.top +
                      kFloatingButtonPadding,
                  left: kFloatingButtonPadding,
                  child: Container(
                    width: kFloatingButtonSize,
                    height: kFloatingButtonSize,
                    decoration: BoxDecoration(
                      color: _isDarkMode
                          ? highlight.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(
                        kFloatingButtonBorderRadius,
                      ),
                      border: Border.all(
                        color: _isDarkMode
                            ? highlight.withValues(alpha: 0.3)
                            : lightModeDark.withValues(alpha: 0.9),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: (_isDarkMode ? highlight : lightModeMedium)
                              .withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 0),
                        ),
                      ],
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
                            color: _isDarkMode ? highlight : lightModeDark,
                            size: kFloatingButtonIconSize,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // User info and account - top right (glass style)
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
                                ? highlight.withValues(alpha: 0.1)
                                : Colors.black.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(
                              kFloatingButtonBorderRadius,
                            ),
                            border: Border.all(
                              color: _isDarkMode
                                  ? highlight.withValues(alpha: 0.3)
                                  : lightModeDark.withValues(alpha: 0.9),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                              BoxShadow(
                                color: (_isDarkMode ? highlight : lightModeMedium)
                                    .withValues(alpha: 0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 0),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.stars,
                                size: kFloatingButtonIconSize - 4,
                                color: _isDarkMode ? highlight : lightModeDark,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$_userPoints',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: _isDarkMode
                                      ? highlight
                                      : lightModeDark,
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
                              ? highlight.withValues(alpha: 0.1)
                              : Colors.black.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(
                            kFloatingButtonBorderRadius,
                          ),
                          border: Border.all(
                            color: _isDarkMode
                                ? highlight.withValues(alpha: 0.3)
                                : lightModeDark.withValues(alpha: 0.9),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                            BoxShadow(
                              color: (_isDarkMode ? highlight : lightModeMedium)
                                  .withValues(alpha: 0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 0),
                            ),
                          ],
                        ),
                        child: SupabaseService.isAuthenticated
                            ? PopupMenuButton<String>(
                                icon: Icon(
                                  Icons.account_circle,
                                  color: _isDarkMode
                                      ? highlight
                                      : lightModeDark,
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
                                            AuthScreen(isDarkMode: _isDarkMode),
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
                                          ? highlight
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
            backgroundColor: _isDarkMode ? highlight : lightModeDark,
            iconColor: _isDarkMode ? highlight : lightModeDark,
            isDarkMode: _isDarkMode,
            children: [
              ActionButton(
                onPressed: _onCreateEvent,
                backgroundColor: _isDarkMode ? highlight : lightModeMedium,
                iconColor: _isDarkMode ? highlight : lightModeDark,
                isDarkMode: _isDarkMode,
                icon: const Icon(Icons.location_pin),
              ),
              ActionButton(
                onPressed: _onReportIssue,
                backgroundColor: _isDarkMode ? highlight : lightModeMedium,
                iconColor: _isDarkMode ? highlight : lightModeDark,
                isDarkMode: _isDarkMode,
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
