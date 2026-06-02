class UserModel {
  final String id;
  final String email;
  final String name;
  final List<String> interests;
  final int points;
  final int completedQuests;
  final bool isAdmin;

  const UserModel({
    required this.id,
    required this.email,
    required this.name,
    required this.interests,
    this.points = 0,
    this.completedQuests = 0,
    this.isAdmin = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'],
        email: json['email'],
        name: json['name'],
        interests: List<String>.from(json['interests']),
        points: json['points'] ?? 0,
        completedQuests: json['completed_quests'] ?? 0,
        isAdmin: json['is_admin'] ?? false,
      );
}
