import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import '../models/marker.dart';
import '../models/issue.dart';
import '../models/event.dart';
import '../models/user.dart' as app_user;

class SupabaseService {
  static final SupabaseClient _client = Supabase.instance.client;
  
  // Authentication methods
  static bool get isAuthenticated => _client.auth.currentUser != null;
  
  static User? get currentAuthUser => _client.auth.currentUser;
  
  static Future<void> signOut() async {
    await _client.auth.signOut();
  }
  
  // User methods
  static Future<app_user.User?> getCurrentUser() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    
    try {
      final response = await _client
          .from('users')
          .select()
          .eq('id', user.id)
          .single();
      
      return app_user.User.fromJson(response);
    } catch (e) {
      // User doesn't exist in our users table, create them
      final newUser = {
        'id': user.id,
        'email': user.email,
        'username': user.email?.split('@')[0],
        'points': 0,
      };
      
      final response = await _client
          .from('users')
          .insert(newUser)
          .select()
          .single();
      
      return app_user.User.fromJson(response);
    }
  }

  // Marker methods
  static Future<List<AppMarker>> getMarkersInBounds(
    LatLng southwest,
    LatLng northeast,
  ) async {
    final response = await _client
        .from('markers')
        .select()
        .gte('latitude', southwest.latitude)
        .lte('latitude', northeast.latitude)
        .gte('longitude', southwest.longitude)
        .lte('longitude', northeast.longitude);

    return response.map<AppMarker>((json) => AppMarker.fromJson(json)).toList();
  }

  static Future<AppMarker> createMarker(MarkerType type, LatLng location) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final markerData = {
      'type': type.name,
      'latitude': location.latitude,
      'longitude': location.longitude,
      'created_by': user.id,
    };

    final response = await _client
        .from('markers')
        .insert(markerData)
        .select()
        .single();

    return AppMarker.fromJson(response);
  }

  // Issue methods
  static Future<List<Issue>> getIssues() async {
    final response = await _client
        .from('issues')
        .select()
        .eq('status', 'active')
        .order('created_at', ascending: false);

    return response.map<Issue>((json) => Issue.fromJson(json)).toList();
  }

  static Future<Issue> getIssueByMarkerId(String markerId) async {
    final response = await _client
        .from('issues')
        .select()
        .eq('marker_id', markerId)
        .single();

    return Issue.fromJson(response);
  }

  static Future<Issue> createIssue({
    required String markerId,
    required String title,
    String? description,
    required IssueCategory category,
    String? imageUrl,
    int credibilityScore = 0,
  }) async {
    final issueData = {
      'marker_id': markerId,
      'title': title,
      'description': description,
      'category': _issueCategoryToString(category),
      'image_url': imageUrl,
      'credibility_score': credibilityScore,
    };

    final response = await _client
        .from('issues')
        .insert(issueData)
        .select()
        .single();

    // Award points for reporting issue
    await _awardPoints('report_issue', 10, response['id']);

    return Issue.fromJson(response);
  }

  static Future<bool> hasUserVotedOnIssue(String issueId) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;

    try {
      final response = await _client
          .from('issue_votes')
          .select()
          .eq('issue_id', issueId)
          .eq('user_id', user.id)
          .maybeSingle();
      
      return response != null;
    } catch (e) {
      return false;
    }
  }

  // Get user's specific vote on an issue (returns -1, 1, or null if not voted)
  static Future<int?> getUserVoteOnIssue(String issueId) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    try {
      final response = await _client
          .from('issue_votes')
          .select('vote')
          .eq('issue_id', issueId)
          .eq('user_id', user.id)
          .maybeSingle();
      
      return response?['vote'];
    } catch (e) {
      return null;
    }
  }

  // Get detailed voting statistics for an issue
  static Future<Map<String, int>> getIssueVoteStats(String issueId) async {
    try {
      final response = await _client
          .from('issue_votes')
          .select('vote')
          .eq('issue_id', issueId);
      
      int upvotes = 0;
      int downvotes = 0;
      
      for (final vote in response) {
        if (vote['vote'] == 1) {
          upvotes++;
        } else if (vote['vote'] == -1) {
          downvotes++;
        }
      }
      
      return {
        'upvotes': upvotes,
        'downvotes': downvotes,
        'total': upvotes + downvotes,
        'score': upvotes - downvotes,
      };
    } catch (e) {
      return {
        'upvotes': 0,
        'downvotes': 0,
        'total': 0,
        'score': 0,
      };
    }
  }

  static Future<void> voteOnIssue(String issueId, int vote) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    // Check if user has already voted
    final currentVote = await getUserVoteOnIssue(issueId);
    
    if (currentVote == vote) {
      throw Exception('You have already cast this vote on this issue');
    }

    // Use upsert to handle both new votes and vote changes
    // Specify onConflict to handle the unique constraint on (issue_id, user_id)
    await _client.from('issue_votes').upsert({
      'issue_id': issueId,
      'user_id': user.id,
      'vote': vote,
    }, onConflict: 'issue_id,user_id');

    // Award points for voting (only if it's a new vote, not a change)
    if (currentVote == null) {
      await _awardPoints('vote_issue', 1, issueId);
    }
  }

  // Event methods
  static Future<List<Event>> getEvents() async {
    final response = await _client
        .from('events')
        .select()
        .inFilter('status', ['upcoming', 'active'])
        .order('start_time', ascending: true);

    return response.map<Event>((json) => Event.fromJson(json)).toList();
  }

  static Future<Event> getEventByMarkerId(String markerId) async {
    final response = await _client
        .from('events')
        .select()
        .eq('marker_id', markerId)
        .single();

    return Event.fromJson(response);
  }

  static Future<Event> createEvent({
    required String markerId,
    required String title,
    String? description,
    required EventCategory category,
    required DateTime startTime,
    required DateTime endTime,
    int? maxParticipants,
    String? imageUrl,
    String? issueId,
  }) async {
    final eventData = {
      'marker_id': markerId,
      'title': title,
      'description': description,
      'category': _eventCategoryToString(category),
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'max_participants': maxParticipants,
      'image_url': imageUrl,
      'issue_id': issueId,
    };

    final response = await _client
        .from('events')
        .insert(eventData)
        .select()
        .single();

    // Award points for creating event
    await _awardPoints('create_event', 20, response['id']);

    return Event.fromJson(response);
  }

  static Future<String?> getUserRsvpStatus(String eventId) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    try {
      final response = await _client
          .from('event_rsvps')
          .select('status')
          .eq('event_id', eventId)
          .eq('user_id', user.id)
          .maybeSingle();
      
      return response?['status'];
    } catch (e) {
      return null;
    }
  }

  static Future<void> rsvpToEvent(String eventId, String status) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    // Check if user has already RSVPed
    final existingStatus = await getUserRsvpStatus(eventId);
    
    if (existingStatus != null) {
      // Update existing RSVP
      await _client
          .from('event_rsvps')
          .update({'status': status})
          .eq('event_id', eventId)
          .eq('user_id', user.id);
    } else {
      // Create new RSVP
      await _client.from('event_rsvps').insert({
        'event_id': eventId,
        'user_id': user.id,
        'status': status,
      });
    }

    // Award points for RSVP (only for 'going' status and only if not previously going)
    if (status == 'going' && existingStatus != 'going') {
      await _awardPoints('rsvp_event', 5, eventId);
    }
  }

  // Image upload methods
  static Future<String?> uploadImage(File imageFile, String folder) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${user.id}.jpg';
      final filePath = '$folder/$fileName';

      await _client.storage
          .from('images')
          .upload(filePath, imageFile);

      final publicUrl = _client.storage
          .from('images')
          .getPublicUrl(filePath);

      return publicUrl;
    } catch (e) {
      print('Error uploading image: $e');
      return null;
    }
  }

  static Future<void> deleteImage(String imageUrl) async {
    try {
      // Extract file path from URL
      final uri = Uri.parse(imageUrl);
      final pathSegments = uri.pathSegments;
      if (pathSegments.length >= 3) {
        final filePath = pathSegments.sublist(2).join('/');
        await _client.storage
            .from('images')
            .remove([filePath]);
      }
    } catch (e) {
      print('Error deleting image: $e');
    }
  }

  // Get events linked to a specific issue
  static Future<List<Event>> getEventsForIssue(String issueId) async {
    final response = await _client
        .from('events')
        .select()
        .eq('issue_id', issueId)
        .order('start_time', ascending: true);

    return response.map<Event>((json) => Event.fromJson(json)).toList();
  }

  // Create a fix event for an issue
  static Future<Event> createFixEventForIssue({
    required String issueId,
    required String issueTitle,
    required LatLng location,
    DateTime? startTime,
    DateTime? endTime,
    int? maxParticipants,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    // Create marker for the fix event at the same location as the issue
    final marker = await createMarker(MarkerType.event, location);

    // Default times: tomorrow at 10 AM for 2 hours
    final defaultStart = DateTime.now().add(const Duration(days: 1)).copyWith(
      hour: 10,
      minute: 0,
      second: 0,
      microsecond: 0,
      millisecond: 0,
    );
    final defaultEnd = defaultStart.add(const Duration(hours: 2));

    return await createEvent(
      markerId: marker.id,
      title: 'Fix: $issueTitle',
      description: 'Community event to address and fix the reported issue.',
      category: EventCategory.cleanup,
      startTime: startTime ?? defaultStart,
      endTime: endTime ?? defaultEnd,
      maxParticipants: maxParticipants,
      issueId: issueId,
    );
  }

  // Helper methods
  static Future<void> _awardPoints(String actionType, int points, String referenceId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _client.rpc('award_points', params: {
      'p_user_id': user.id,
      'p_action_type': actionType,
      'p_points': points,
      'p_reference_id': referenceId,
    });
  }

  static String _issueCategoryToString(IssueCategory category) {
    switch (category) {
      case IssueCategory.waste:
        return 'waste';
      case IssueCategory.pollution:
        return 'pollution';
      case IssueCategory.water:
        return 'water';
      case IssueCategory.other:
        return 'other';
    }
  }

  static String _eventCategoryToString(EventCategory category) {
    switch (category) {
      case EventCategory.cleanup:
        return 'cleanup';
      case EventCategory.advocacy:
        return 'advocacy';
      case EventCategory.education:
        return 'education';
      case EventCategory.other:
        return 'other';
    }
  }
}
