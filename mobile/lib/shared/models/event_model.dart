class EventModel {
  final String id;
  final String landmarkId;
  final String? landmarkName;
  final String title;
  final String description;
  final DateTime startTime;
  final DateTime? endTime;
  final bool isUpcoming;
  final bool isOngoing;
  final String? createdBy;

  const EventModel({
    required this.id,
    required this.landmarkId,
    this.landmarkName,
    required this.title,
    required this.description,
    required this.startTime,
    this.endTime,
    this.isUpcoming = false,
    this.isOngoing = false,
    this.createdBy,
  });

  factory EventModel.fromJson(Map<String, dynamic> json) => EventModel(
        id: json['id'],
        landmarkId: json['landmark_id'],
        landmarkName: json['landmark_name'] as String?,
        title: json['title'],
        description: json['description'],
        startTime: DateTime.parse(json['start_time']),
        endTime: json['end_time'] != null ? DateTime.parse(json['end_time']) : null,
        isUpcoming: json['is_upcoming'] ?? false,
        isOngoing: json['is_ongoing'] ?? false,
        createdBy: json['created_by'] as String?,
      );
}
