import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import '../models/marker.dart';
import '../models/issue.dart';
import '../models/event.dart';
import '../services/supabase_service.dart';
import 'auth_screen.dart';

class MarkerDetailsScreen extends StatefulWidget {
  final AppMarker marker;
  final VoidCallback onDataChanged;

  const MarkerDetailsScreen({
    super.key,
    required this.marker,
    required this.onDataChanged,
  });

  @override
  State<MarkerDetailsScreen> createState() => _MarkerDetailsScreenState();
}

class _MarkerDetailsScreenState extends State<MarkerDetailsScreen> {
  Issue? _issue;
  Event? _event;
  bool _isLoading = true;
  bool _hasVoted = false;
  int? _userVote; // -1, 1, or null
  Map<String, int> _voteStats = {'upvotes': 0, 'downvotes': 0, 'total': 0, 'score': 0};
  bool _hasRsvped = false;
  String _rsvpStatus = 'not_going';
  Placemark? _placemark;

  @override
  void initState() {
    super.initState();
    _loadMarkerDetails();
  }

  Future<void> _loadMarkerDetails() async {
    try {
      if (widget.marker.type == MarkerType.issue) {
        final issue = await SupabaseService.getIssueByMarkerId(widget.marker.id);
        final userVote = await SupabaseService.getUserVoteOnIssue(issue.id);
        final voteStats = await SupabaseService.getIssueVoteStats(issue.id);
        setState(() {
          _issue = issue;
          _hasVoted = userVote != null;
          _userVote = userVote;
          _voteStats = voteStats;
        });
      } else {
        final event = await SupabaseService.getEventByMarkerId(
          widget.marker.id,
        );
        final rsvpStatus = await SupabaseService.getUserRsvpStatus(event.id);
        setState(() {
          _event = event;
          _hasRsvped = rsvpStatus != null;
          _rsvpStatus = rsvpStatus ?? 'not_going';
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading details: $e')));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }

    // Fetch placemark for location display
    try {
      final placemarks = await placemarkFromCoordinates(
        widget.marker.location.latitude,
        widget.marker.location.longitude,
      );
      setState(() {
        _placemark = placemarks.isNotEmpty ? placemarks[0] : null;
      });
    } catch (e) {
      // Handle geocoding error silently or show a message if needed
      setState(() {
        _placemark = null;
      });
    }
  }

  Future<void> _voteOnIssue(int vote) async {
    if (_issue == null) return;

    if (!SupabaseService.isAuthenticated) {
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) =>
              const AuthScreen(actionContext: 'to vote on this issue'),
        ),
      );
      if (result != true) return;
    }

    try {
      await SupabaseService.voteOnIssue(_issue!.id, vote);
      // Show appropriate message based on whether it's a new vote or vote change
      String message;
      if (_userVote == null) {
        message = 'Vote submitted! +1 point';
      } else {
        message = 'Vote updated!';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
        ),
      );

      widget.onDataChanged();
      await _loadMarkerDetails(); // Refresh to get updated voting information
    } catch (e) {
      String errorMessage = 'Error voting: $e';
      if (e.toString().contains('already cast this vote')) {
        errorMessage = 'You have already cast this vote on this issue';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _rsvpToEvent(String status) async {
    if (_event == null) return;

    if (!SupabaseService.isAuthenticated) {
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) =>
              const AuthScreen(actionContext: 'to RSVP to this event'),
        ),
      );
      if (result != true) return;
    }

    try {
      await SupabaseService.rsvpToEvent(_event!.id, status);
      setState(() {
        _hasRsvped = true;
        _rsvpStatus = status;
      });

      if (status == 'going') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('RSVP confirmed! +5 points'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('RSVP updated!'),
            backgroundColor: Colors.blue,
          ),
        );
      }

      widget.onDataChanged();
      await _loadMarkerDetails(); // Refresh to get updated participant count
    } catch (e) {
      String errorMessage = 'Error with RSVP: $e';
      if (e.toString().contains('duplicate key')) {
        errorMessage = 'RSVP status updated!';
        setState(() {
          _hasRsvped = true;
          _rsvpStatus = status;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: e.toString().contains('duplicate key')
              ? Colors.blue
              : Colors.red,
        ),
      );
    }
  }

  Widget _buildIssueDetails() {
    if (_issue == null) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red),
                      ),
                      child: Text(
                        _issue!.categoryDisplayName,
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Enhanced credibility display with vote breakdown
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _voteStats['score']! >= 0 ? Icons.thumb_up : Icons.thumb_down,
                              size: 16,
                              color: _voteStats['score']! >= 0 ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${_voteStats['score']}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _voteStats['score']! >= 0 ? Colors.green : Colors.red,
                              ),
                            ),
                          ],
                        ),
                        if (_voteStats['total']! > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${_voteStats['total']} vote${_voteStats['total'] == 1 ? '' : 's'}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Credibility: ${_issue!.credibilityScore}/10',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _issue!.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_issue!.description != null) ...[
                  const SizedBox(height: 8),
                  Text(_issue!.description!),
                ],
                if (_issue!.imageUrl != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        _issue!.imageUrl!,
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 200,
                            color: Colors.grey[300],
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.broken_image,
                                  size: 50,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Failed to load image',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'URL: ${_issue!.imageUrl}',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 10,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          );
                        },
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            height: 200,
                            color: Colors.grey[200],
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Loading image...',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Reported: ${_formatDate(_issue!.createdAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        
        // Voting statistics card
        if (_voteStats['total']! > 0)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Community Voting',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.withOpacity(0.3)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.thumb_up, color: Colors.green, size: 20),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_voteStats['upvotes']}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                              const Text(
                                'Credible',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.withOpacity(0.3)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.thumb_down, color: Colors.red, size: 20),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_voteStats['downvotes']}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                              const Text(
                                'Not Credible',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.red,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        
        const SizedBox(height: 16),
        
        // Voting action section
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _hasVoted 
                    ? 'Your Vote' 
                    : 'Is this issue credible?',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                
                if (_hasVoted) ...[
                  // Show current vote and allow changing
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (_userVote == 1 ? Colors.green : Colors.red).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (_userVote == 1 ? Colors.green : Colors.red).withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _userVote == 1 ? Icons.thumb_up : Icons.thumb_down,
                          color: _userVote == 1 ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'You voted: ${_userVote == 1 ? 'Credible' : 'Not Credible'}',
                          style: TextStyle(
                            color: _userVote == 1 ? Colors.green : Colors.red,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Change your vote:',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                ],
                
                // Voting buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _userVote == 1 ? null : () => _voteOnIssue(1),
                        icon: const Icon(Icons.thumb_up),
                        label: Text(_hasVoted 
                          ? (_userVote == 1 ? 'Current Vote' : 'Change to Credible')
                          : 'Yes (+1 Point)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _userVote == 1 
                            ? Colors.green.shade700 
                            : Colors.green,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.green.shade700,
                          disabledForegroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _userVote == -1 ? null : () => _voteOnIssue(-1),
                        icon: const Icon(Icons.thumb_down),
                        label: Text(_hasVoted 
                          ? (_userVote == -1 ? 'Current Vote' : 'Change to Not Credible')
                          : 'No (+1 Point)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _userVote == -1 
                            ? Colors.red.shade700 
                            : Colors.red,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.red.shade700,
                          disabledForegroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEventDetails() {
    if (_event == null) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green),
                      ),
                      child: Text(
                        _event!.categoryDisplayName,
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (_event!.isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _event!.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_event!.description != null) ...[
                  const SizedBox(height: 8),
                  Text(_event!.description!),
                ],
                if (_event!.imageUrl != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        _event!.imageUrl!,
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          print('Event image load error: $error');
                          print('Event image URL: ${_event!.imageUrl}');
                          return Container(
                            height: 200,
                            color: Colors.grey[300],
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.broken_image,
                                  size: 50,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Failed to load image',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'URL: ${_event!.imageUrl}',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 10,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          );
                        },
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            height: 200,
                            color: Colors.grey[200],
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Loading image...',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${_formatDateTime(_event!.startTime)} - ${_formatDateTime(_event!.endTime)}',
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.people, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      _event!.maxParticipants != null
                          ? '${_event!.currentParticipants}/${_event!.maxParticipants} participants'
                          : '${_event!.currentParticipants} participants',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (!_event!.isFull) ...[
          Text(
            _hasRsvped ? 'Update your RSVP:' : 'Will you attend this event?',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _rsvpToEvent('going'),
                  icon: Icon(
                    _rsvpStatus == 'going'
                        ? Icons.check_circle
                        : Icons.check_circle_outline,
                  ),
                  label: Text(
                    _rsvpStatus == 'going'
                        ? 'Going!'
                        : 'Yes, I\'m going! (+5 Points)',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _rsvpStatus == 'going'
                        ? Colors.green.shade700
                        : Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _rsvpToEvent('maybe'),
                  icon: Icon(
                    _rsvpStatus == 'maybe' ? Icons.help : Icons.help_outline,
                  ),
                  label: Text(_rsvpStatus == 'maybe' ? 'Maybe going' : 'Maybe'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _rsvpStatus == 'maybe'
                        ? Colors.orange.shade700
                        : Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              if (_hasRsvped) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _rsvpToEvent('not_going'),
                    icon: Icon(
                      _rsvpStatus == 'not_going'
                          ? Icons.cancel
                          : Icons.cancel_outlined,
                    ),
                    label: Text(
                      _rsvpStatus == 'not_going' ? 'Not going' : 'Cancel RSVP',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _rsvpStatus == 'not_going'
                          ? Colors.grey.shade700
                          : Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ] else if (_event!.isFull) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange),
            ),
            child: const Row(
              children: [
                Icon(Icons.people, color: Colors.orange),
                SizedBox(width: 8),
                Text('This event is full'),
              ],
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'You\'re ${_rsvpStatus == 'going'
                      ? 'going'
                      : _rsvpStatus == 'maybe'
                      ? 'maybe going'
                      : 'not going'}',
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatDateTime(DateTime date) {
    return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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
    if (placemark.administrativeArea != null &&
        placemark.administrativeArea!.isNotEmpty) {
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.marker.type == MarkerType.issue
              ? 'Issue Details'
              : 'Event Details',
        ),
        backgroundColor: widget.marker.type == MarkerType.issue
            ? Colors.red
            : Colors.green,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Location',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              // 'Lat: ${widget.marker.location.latitude.toStringAsFixed(6)}\n'
                              // 'Lng: ${widget.marker.location.longitude.toStringAsFixed(6)}',
                              _placemark != null
                                  ? _formatAddress(_placemark!)
                                  : 'Loading location...',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (widget.marker.type == MarkerType.issue)
                      _buildIssueDetails()
                    else
                      _buildEventDetails(),
                  ],
                ),
              ),
            ),
    );
  }
}
