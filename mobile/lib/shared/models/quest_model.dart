class QuestModel {
  final String id;
  final String landmarkId;
  final String type;
  final String title;
  final String description;
  final int points;
  final List<String> options;
  final int? correctOptionIndex;
  final bool completed;

  const QuestModel({
    required this.id,
    required this.landmarkId,
    required this.type,
    required this.title,
    required this.description,
    required this.points,
    this.options = const [],
    this.correctOptionIndex,
    this.completed = false,
  });

  factory QuestModel.fromJson(Map<String, dynamic> json) => QuestModel(
        id: json['id'],
        landmarkId: json['landmark_id'],
        type: json['type'],
        title: json['title'],
        description: json['description'],
        points: json['points'],
        options: List<String>.from(json['options'] ?? []),
        correctOptionIndex: json['correct_option_index'],
        completed: json['completed'] ?? false,
      );

  QuestModel copyWith({bool? completed}) => QuestModel(
        id: id,
        landmarkId: landmarkId,
        type: type,
        title: title,
        description: description,
        points: points,
        options: options,
        correctOptionIndex: correctOptionIndex,
        completed: completed ?? this.completed,
      );
}
