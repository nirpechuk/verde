import 'package:supabase_flutter/supabase_flutter.dart';

class Report {
  final String id; // uuid (PK)
  final String? createdBy; // uuid (FK -> profiles.id), nullable
  final int label; // integer NOT NULL DEFAULT 0
  final int severity; // integer NOT NULL DEFAULT 0
  final int status; // integer NOT NULL DEFAULT 0

  /// PostGIS geography; commonly serialized as GeoJSON (WGS84).
  /// Example: {"type":"Point","coordinates":[lon, lat]}
  final Map<String, dynamic> location; // NOT NULL

  final DateTime createdAt; // timestamptz NOT NULL DEFAULT now()
  final DateTime updatedAt; // timestamptz NOT NULL DEFAULT now()

  const Report({
    required this.id,
    required this.createdBy,
    required this.label,
    required this.severity,
    required this.status,
    required this.location,
    required this.createdAt,
    required this.updatedAt,
  });

  Report copyWith({
    String? id,
    String? createdBy,
    int? label,
    int? severity,
    int? status,
    Map<String, dynamic>? location,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Report(
      id: id ?? this.id,
      createdBy: createdBy ?? this.createdBy,
      label: label ?? this.label,
      severity: severity ?? this.severity,
      status: status ?? this.status,
      location: location ?? this.location,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Report.fromJson(Map<String, dynamic> json) {
    return Report(
      id: json['id'] as String,
      createdBy: json['created_by'] as String?,
      label: (json['label'] as num).toInt(),
      severity: (json['severity'] as num).toInt(),
      status: (json['status'] as num).toInt(),
      location: (json['location'] as Map).cast<String, dynamic>(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'created_by': createdBy,
      'label': label,
      'severity': severity,
      'status': status,
      'location': location,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

// Supabase helper functions

/// Fetch multiple reports. Optionally pass `limit` and `offset` for paging.
Future<List<Report>> fetchReports(
  SupabaseClient supabase, {
  int? limit,
  int? offset,
}) async {
  try {
    dynamic builder = supabase.from('reports').select();
    if (limit != null) builder = builder.limit(limit);
    if (offset != null && limit != null) {
      builder = builder.range(offset, offset + limit - 1);
    }

    final res = await builder;
    final data = (res as List).cast<Map<String, dynamic>>();
    return data.map((d) => Report.fromJson(d)).toList();
  } catch (e) {
    rethrow;
  }
}

/// Fetch a single report by `id`. Returns `null` when not found.
Future<Report?> fetchReportById(SupabaseClient supabase, String id) async {
  try {
    final res = await supabase.from('reports').select().eq('id', id).limit(1);
    final list = (res as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return null;
    return Report.fromJson(list.first);
  } catch (e) {
    rethrow;
  }
}

/// Insert a new report. Returns the created `Report`.
Future<Report> createReport(SupabaseClient supabase, Report report) async {
  try {
    final payload = Map<String, dynamic>.from(report.toJson());
    if (payload['id'] == null || (payload['id'] as String).isEmpty) {
      payload.remove('id');
    }

    final res = await supabase.from('reports').insert(payload).select();
    final list = (res as List).cast<Map<String, dynamic>>();
    return Report.fromJson(list.first);
  } catch (e) {
    rethrow;
  }
}

/// Update an existing report by id. Returns the updated `Report` or null if not found.
Future<Report?> updateReport(
  SupabaseClient supabase,
  String id,
  Map<String, dynamic> changes,
) async {
  try {
    final res = await supabase
        .from('reports')
        .update(changes)
        .eq('id', id)
        .select();
    final list = (res as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return null;
    return Report.fromJson(list.first);
  } catch (e) {
    rethrow;
  }
}

/// Delete a report by id. Returns `true` when a row was deleted.
Future<bool> deleteReport(SupabaseClient supabase, String id) async {
  try {
    final res = await supabase.from('reports').delete().eq('id', id);
    if (res == null) return false;
    if (res is List) return res.isNotEmpty;
    return true;
  } catch (e) {
    rethrow;
  }
}
