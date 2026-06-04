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
  final int visitCount;
  final bool hasActiveQuest;
  final String? submittedBy;
  final String? website;
  final String? openingHours;
  final double? ticketPrice;   // null = free entry
  final String? discountInfo;  // e.g. "15% off for 200 pts or 5 quests"
  // These are computed locally — not from the server
  final bool visitedByMe;
  final double? myRating;

  const LandmarkModel({
    required this.id,
    required this.name,
    required this.type,
    required this.location,
    required this.description,
    this.categories = const [],
    this.stories = const [],
    this.rating = 0.0,
    this.visitCount = 0,
    this.hasActiveQuest = false,
    this.submittedBy,
    this.website,
    this.openingHours,
    this.ticketPrice,
    this.discountInfo,
    this.visitedByMe = false,
    this.myRating,
  });

  LandmarkModel withLocal({bool? visitedByMe, double? myRating}) => LandmarkModel(
    id: id, name: name, type: type, location: location, description: description,
    categories: categories, stories: stories, rating: rating, visitCount: visitCount,
    hasActiveQuest: hasActiveQuest, submittedBy: submittedBy, website: website,
    openingHours: openingHours, ticketPrice: ticketPrice, discountInfo: discountInfo,
    visitedByMe: visitedByMe ?? this.visitedByMe,
    myRating: myRating ?? this.myRating,
  );

  factory LandmarkModel.fromJson(Map<String, dynamic> json) => LandmarkModel(
        id: json['id'],
        name: json['name'],
        type: json['type'],
        location: GeoPoint.fromJson(json['location']),
        description: json['description'],
        categories: List<String>.from(json['categories'] ?? []),
        stories: List<String>.from(json['stories'] ?? []),
        rating: (json['rating'] ?? 0).toDouble(),
        visitCount: (json['visit_count'] ?? 0) as int,
        hasActiveQuest: json['has_active_quest'] ?? false,
        submittedBy: json['submitted_by'] as String?,
        website: json['website'] as String?,
        openingHours: json['opening_hours'] as String?,
        ticketPrice: (json['ticket_price'] as num?)?.toDouble(),
        discountInfo: json['discount_info'] as String?,
      );
}
