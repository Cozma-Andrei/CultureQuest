import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/quest_model.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/local_data_service.dart';
import '../../auth/providers/auth_provider.dart';

class QuestState {
  final List<QuestModel> quests;
  final String landmarkName;
  final bool isLoading;
  final String? error;

  const QuestState({
    this.quests = const [],
    this.landmarkName = '',
    this.isLoading = false,
    this.error,
  });

  QuestState copyWith({
    List<QuestModel>? quests,
    String? landmarkName,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) =>
      QuestState(
        quests: quests ?? this.quests,
        landmarkName: landmarkName ?? this.landmarkName,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : error ?? this.error,
      );
}

class QuestNotifier extends StateNotifier<QuestState> {
  final ApiService _api;
  final Ref _ref;

  QuestNotifier(this._api, this._ref) : super(const QuestState());

  Future<void> loadQuests(String landmarkId, {String landmarkName = '', bool isNearby = false}) async {
    state = QuestState(isLoading: true, landmarkName: landmarkName);
    try {
      if (isNearby) {
        final isFirst = !_ref.read(localDataProvider).isVisited(landmarkId);
        await _ref.read(localDataProvider).markVisited(landmarkId);
        if (isFirst) _api.post('/landmarks/$landmarkId/visit').ignore();
      }
      final res = await _api.get('/quests/', params: {'landmark_id': landmarkId});
      final completedIds = _ref.read(localDataProvider).getCompletedQuestIds();
      final quests = (res.data as List)
          .map((j) => QuestModel.fromJson(j as Map<String, dynamic>))
          .map((q) => completedIds.contains(q.id) ? q.copyWith(completed: true) : q)
          .toList();
      state = QuestState(quests: quests, landmarkName: landmarkName);
    } catch (_) {
      state = QuestState(landmarkName: landmarkName, error: 'Failed to load quests');
    }
  }

  Future<Map<String, dynamic>?> completeQuest(
    String questId, {
    int? answerIndex,
    String? noteText,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (answerIndex != null) body['answer_index'] = answerIndex;
      if (noteText != null) body['note_text'] = noteText;

      final res = await _api.post('/quests/$questId/complete', data: body);
      final result = Map<String, dynamic>.from(res.data as Map);

      if (result['correct'] == true) {
        // Mark completed locally — server no longer tracks which quests each user finished
        await _ref.read(localDataProvider).markQuestCompleted(questId);
        state = state.copyWith(
          quests: state.quests
              .map((q) => q.id == questId ? q.copyWith(completed: true) : q)
              .toList(),
        );
      }

      await _ref.read(authProvider.notifier).refreshUser();

      return result;
    } catch (_) {
      return null;
    }
  }
}

final questProvider = StateNotifierProvider<QuestNotifier, QuestState>(
  (ref) => QuestNotifier(ref.watch(apiServiceProvider), ref),
);
