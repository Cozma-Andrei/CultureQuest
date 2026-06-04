class CommentModel {
  final String id;
  final String landmarkId;
  final String text;
  final int rating;
  final String createdAt;
  final bool flagged;
  final String? flagSource; // "openai" | "local" | null

  const CommentModel({
    required this.id,
    required this.landmarkId,
    required this.text,
    required this.rating,
    required this.createdAt,
    this.flagged = false,
    this.flagSource,
  });

  factory CommentModel.fromJson(Map<String, dynamic> json) => CommentModel(
        id: json['id'],
        landmarkId: json['landmark_id'],
        text: json['text'],
        rating: json['rating'] as int,
        createdAt: json['created_at'] ?? '',
        flagged: json['flagged'] as bool? ?? false,
        flagSource: json['flag_source'] as String?,
      );
}
