import 'landmark_model.dart';

class RouteStop {
  final LandmarkModel landmark;
  final int estimatedDurationMinutes;
  final double relevanceScore;

  const RouteStop({
    required this.landmark,
    required this.estimatedDurationMinutes,
    required this.relevanceScore,
  });

  factory RouteStop.fromJson(Map<String, dynamic> json) => RouteStop(
        landmark: LandmarkModel.fromJson(json['landmark']),
        estimatedDurationMinutes: json['estimated_duration_minutes'],
        relevanceScore: (json['relevance_score']).toDouble(),
      );
}

class RouteModel {
  final String id;
  final List<RouteStop> stops;
  final double totalDistanceM;
  final int totalDurationMinutes;

  const RouteModel({
    required this.id,
    required this.stops,
    required this.totalDistanceM,
    required this.totalDurationMinutes,
  });

  factory RouteModel.fromJson(Map<String, dynamic> json) => RouteModel(
        id: json['id'],
        stops: (json['stops'] as List).map((s) => RouteStop.fromJson(s)).toList(),
        totalDistanceM: (json['total_distance_m']).toDouble(),
        totalDurationMinutes: json['total_duration_minutes'],
      );
}

class RouteStopWithProgress {
  final LandmarkModel landmark;
  final bool visited;

  const RouteStopWithProgress({required this.landmark, required this.visited});

  factory RouteStopWithProgress.fromJson(Map<String, dynamic> json) =>
      RouteStopWithProgress(
        landmark: LandmarkModel.fromJson(json['landmark']),
        visited: json['visited'] as bool? ?? false,
      );
}

class RouteWithProgress {
  final String id;
  final String? name;
  final List<RouteStopWithProgress> stops;
  final double totalDistanceM;
  final int totalDurationMinutes;
  final String generatedAt;
  final int visitedCount;
  final bool isGlobal;

  const RouteWithProgress({
    required this.id,
    this.name,
    required this.stops,
    required this.totalDistanceM,
    required this.totalDurationMinutes,
    required this.generatedAt,
    required this.visitedCount,
    this.isGlobal = false,
  });

  factory RouteWithProgress.fromJson(Map<String, dynamic> json) =>
      RouteWithProgress(
        id: json['id'],
        name: json['name'] as String?,
        stops: (json['stops'] as List)
            .map((s) => RouteStopWithProgress.fromJson(s))
            .toList(),
        totalDistanceM: (json['total_distance_m']).toDouble(),
        totalDurationMinutes: json['total_duration_minutes'],
        generatedAt: json['generated_at'] ?? '',
        visitedCount: json['visited_count'] as int? ?? 0,
        isGlobal: json['is_global'] as bool? ?? false,
      );
}
