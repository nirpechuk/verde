enum IssueCategory {
  waste,
  pollution,
  water,
  other,
}

enum IssueStatus { active, resolved, removed }

class Issue {
  final String id;
  final String markerId;
  final String title;
  final String? description;
  final IssueCategory category;
  final String? imageUrl;
  final int credibilityScore;
  final IssueStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  Issue({
    required this.id,
    required this.markerId,
    required this.title,
    this.description,
    required this.category,
    this.imageUrl,
    required this.credibilityScore,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Issue.fromJson(Map<String, dynamic> json) {
    return Issue(
      id: json['id'],
      markerId: json['marker_id'],
      title: json['title'],
      description: json['description'],
      category: categoryFromString(json['category']),
      imageUrl: json['image_url'],
      credibilityScore: json['credibility_score'] ?? 0,
      status: _statusFromString(json['status']),
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
      'category': categoryToString(category),
      'image_url': imageUrl,
      'credibility_score': credibilityScore,
      'status': _statusToString(status),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static IssueCategory categoryFromString(String category) {
    switch (category) {
      case 'waste':
        return IssueCategory.waste;
      case 'pollution':
        return IssueCategory.pollution;
      case 'water':
        return IssueCategory.water;
      default:
        return IssueCategory.other;
    }
  }

  static String categoryToString(IssueCategory category) {
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

  static IssueStatus _statusFromString(String status) {
    switch (status) {
      case 'active':
        return IssueStatus.active;
      case 'resolved':
        return IssueStatus.resolved;
      case 'removed':
        return IssueStatus.removed;
      default:
        return IssueStatus.active;
    }
  }

  static String _statusToString(IssueStatus status) {
    switch (status) {
      case IssueStatus.active:
        return 'active';
      case IssueStatus.resolved:
        return 'resolved';
      case IssueStatus.removed:
        return 'removed';
    }
  }

  String get categoryDisplayName {
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

  Issue copyWith({
    String? id,
    String? markerId,
    String? title,
    String? description,
    IssueCategory? category,
    String? imageUrl,
    int? credibilityScore,
    IssueStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Issue(
      id: id ?? this.id,
      markerId: markerId ?? this.markerId,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      imageUrl: imageUrl ?? this.imageUrl,
      credibilityScore: credibilityScore ?? this.credibilityScore,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
