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
