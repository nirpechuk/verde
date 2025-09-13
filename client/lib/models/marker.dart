import 'package:latlong2/latlong.dart';

enum MarkerType { issue, event }

class AppMarker {
  final String id;
  final MarkerType type;
  final LatLng location;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  AppMarker({
    required this.id,
    required this.type,
    required this.location,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AppMarker.fromJson(Map<String, dynamic> json) {
    return AppMarker(
      id: json['id'],
      type: MarkerType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MarkerType.issue,
      ),
      location: LatLng(json['latitude'], json['longitude']),
      createdBy: json['created_by'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'latitude': location.latitude,
      'longitude': location.longitude,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
