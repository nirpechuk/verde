import 'package:flutter/material.dart';
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
  bool _hasRsvped = false;
  String _rsvpStatus = 'not_going';

  @override
  void initState() {
    super.initState();
    _loadMarkerDetails();
  }

  Future<void> _loadMarkerDetails() async {
    try {
      if (widget.marker.type == MarkerType.issue) {
        final issue = await SupabaseService.getIssueByMarkerId(widget.marker.id);
        setState(() {
          _issue = issue;
        });
      } else {
        final event = await SupabaseService.getEventByMarkerId(widget.marker.id);
        setState(() {
          _event = event;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading details: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _voteOnIssue(int vote) async {
    if (_issue == null) return;

    if (!SupabaseService.isAuthenticated) {
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => const AuthScreen(
            actionContext: 'to vote on this issue',
          ),
        ),
      );
      if (result != true) return;
    }

    try {
      await SupabaseService.voteOnIssue(_issue!.id, vote);
      setState(() {
        _hasVoted = true;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vote submitted! +1 point'),
          backgroundColor: Colors.green,
        ),
      );
      
      widget.onDataChanged();
      await _loadMarkerDetails(); // Refresh to get updated credibility score
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error voting: $e')),
      );
    }
  }

  Future<void> _rsvpToEvent(String status) async {
    if (_event == null) return;

    if (!SupabaseService.isAuthenticated) {
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => const AuthScreen(
            actionContext: 'to RSVP to this event',
          ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error with RSVP: $e')),
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                    Row(
                      children: [
                        Icon(
                          _issue!.credibilityScore >= 0 ? Icons.thumb_up : Icons.thumb_down,
                          size: 16,
                          color: _issue!.credibilityScore >= 0 ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_issue!.credibilityScore}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _issue!.credibilityScore >= 0 ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
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
        if (!_hasVoted) ...[
          const Text(
            'Is this issue credible?',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _voteOnIssue(1),
                  icon: const Icon(Icons.thumb_up),
                  label: const Text('Yes (+1 Point)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _voteOnIssue(-1),
                  icon: const Icon(Icons.thumb_down),
                  label: const Text('No (+1 Point)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.blue),
                SizedBox(width: 8),
                Text('Thank you for voting!'),
              ],
            ),
          ),
        ],
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 16),
                    const SizedBox(width: 4),
                    Text('${_formatDateTime(_event!.startTime)} - ${_formatDateTime(_event!.endTime)}'),
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
        if (!_hasRsvped && !_event!.isFull) ...[
          const Text(
            'Will you attend this event?',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _rsvpToEvent('going'),
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Yes, I\'m going! (+5 Points)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _rsvpToEvent('maybe'),
                  icon: const Icon(Icons.help),
                  label: const Text('Maybe'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
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
                Text('You\'re ${_rsvpStatus == 'going' ? 'going' : _rsvpStatus == 'maybe' ? 'maybe going' : 'not going'}'),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatDateTime(DateTime date) {
    return '${date.day}/${date.month} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.marker.type == MarkerType.issue ? 'Issue Details' : 'Event Details'),
        backgroundColor: widget.marker.type == MarkerType.issue ? Colors.red : Colors.green,
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
                              'Lat: ${widget.marker.location.latitude.toStringAsFixed(6)}\n'
                              'Lng: ${widget.marker.location.longitude.toStringAsFixed(6)}',
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
