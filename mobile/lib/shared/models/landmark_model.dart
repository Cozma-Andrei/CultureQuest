class GeoPoint {
  final double lat;
  final double lng;
  const GeoPoint({required this.lat, required this.lng});

  factory GeoPoint.fromJson(Map<String, dynamic> json) =>
      GeoPoint(lat: json['lat'].toDouble(), lng: json['lng'].toDouble());
}

class LandmarkModel {
  final String id;
  final String name;
  final String type;
  final GeoPoint location;
  final String description;
  final List<String> categories;
  final List<String> stories;
  final double rating;
  final bool hasActiveQuest;

  const LandmarkModel({
    required this.id,
    required this.name,
    required this.type,
    required this.location,
    required this.description,
    this.categories = const [],
    this.stories = const [],
    this.rating = 0.0,
    this.hasActiveQuest = false,
  });

  factory LandmarkModel.fromJson(Map<String, dynamic> json) => LandmarkModel(
        id: json['id'],
        name: json['name'],
        type: json['type'],
        location: GeoPoint.fromJson(json['location']),
        description: json['description'],
        categories: List<String>.from(json['categories'] ?? []),
        stories: List<String>.from(json['stories'] ?? []),
        rating: (json['rating'] ?? 0).toDouble(),
        hasActiveQuest: json['has_active_quest'] ?? false,
      );
}
