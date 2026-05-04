import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/quest_model.dart';

class QuestState {
  final List<QuestModel> quests;
  final int totalPoints;
  final bool isLoading;

  const QuestState({this.quests = const [], this.totalPoints = 0, this.isLoading = false});
}

class QuestNotifier extends StateNotifier<QuestState> {
  QuestNotifier() : super(const QuestState());

  Future<void> loadQuests(String landmarkId) async {}

  Future<bool> completeQuest(String questId, {int? answerIndex, String? noteText}) async {
    return false;
  }
}

final questProvider = StateNotifierProvider<QuestNotifier, QuestState>(
  (_) => QuestNotifier(),
);
