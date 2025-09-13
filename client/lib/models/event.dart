enum EventCategory { cleanup, advocacy, education, other }

enum EventStatus { upcoming, active, completed, cancelled }

class Event {
  final String id;
  final String markerId;
  final String title;
  final String? description;
  final EventCategory category;
  final DateTime startTime;
  final DateTime endTime;
  final int? maxParticipants;
  final int currentParticipants;
  final EventStatus status;
  final String? imageUrl;
  final String? issueId; // Link to issue this event addresses
  final DateTime createdAt;
  final DateTime updatedAt;

  Event({
    required this.id,
    required this.markerId,
    required this.title,
    this.description,
    required this.category,
    required this.startTime,
    required this.endTime,
    this.maxParticipants,
    required this.currentParticipants,
    required this.status,
    this.imageUrl,
    this.issueId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: json['id'],
      markerId: json['marker_id'],
      title: json['title'],
      description: json['description'],
      category: _categoryFromString(json['category']),
      startTime: DateTime.parse(json['start_time']),
      endTime: DateTime.parse(json['end_time']),
      maxParticipants: json['max_participants'],
      currentParticipants: json['current_participants'] ?? 0,
      status: _statusFromString(json['status']),
      imageUrl: json['image_url'],
      issueId: json['issue_id'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'marker_id': markerId,
      'title': title,
      'description': description,
      'category': _categoryToString(category),
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'max_participants': maxParticipants,
      'current_participants': currentParticipants,
      'status': _statusToString(status),
      'image_url': imageUrl,
      'issue_id': issueId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static EventCategory _categoryFromString(String category) {
    switch (category) {
      case 'cleanup':
        return EventCategory.cleanup;
      case 'advocacy':
        return EventCategory.advocacy;
      case 'education':
        return EventCategory.education;
      default:
        return EventCategory.other;
    }
  }

  static String _categoryToString(EventCategory category) {
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

  static EventStatus _statusFromString(String status) {
    switch (status) {
      case 'upcoming':
        return EventStatus.upcoming;
      case 'active':
        return EventStatus.active;
      case 'completed':
        return EventStatus.completed;
      case 'cancelled':
        return EventStatus.cancelled;
      default:
        return EventStatus.upcoming;
    }
  }

  static String _statusToString(EventStatus status) {
    switch (status) {
      case EventStatus.upcoming:
        return 'upcoming';
      case EventStatus.active:
        return 'active';
      case EventStatus.completed:
        return 'completed';
      case EventStatus.cancelled:
        return 'cancelled';
    }
  }

  String get categoryDisplayName {
    switch (category) {
      case EventCategory.cleanup:
        return 'Cleanup';
      case EventCategory.advocacy:
        return 'Advocacy';
      case EventCategory.education:
        return 'Education';
      case EventCategory.other:
        return 'Other';
    }
  }

  bool get isFull => maxParticipants != null && currentParticipants >= maxParticipants!;

  bool get isActive {
    final now = DateTime.now();
    return now.isAfter(startTime) && now.isBefore(endTime) && status == EventStatus.active;
  }

  Event copyWith({
    String? id,
    String? markerId,
    String? title,
    String? description,
    EventCategory? category,
    DateTime? startTime,
    DateTime? endTime,
    int? maxParticipants,
    int? currentParticipants,
    EventStatus? status,
    String? imageUrl,
    String? issueId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Event(
      id: id ?? this.id,
      markerId: markerId ?? this.markerId,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      currentParticipants: currentParticipants ?? this.currentParticipants,
      status: status ?? this.status,
      imageUrl: imageUrl ?? this.imageUrl,
      issueId: issueId ?? this.issueId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
