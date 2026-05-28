import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/fl_client_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../shared/models/landmark_model.dart';

const _autoRoundThreshold = 5; // trigger FL round after this many interactions

class FLState {
  final int round;
  final bool isTraining;
  final int pendingInteractions;
  final String? lastResult;

  const FLState({
    this.round = 0,
    this.isTraining = false,
    this.pendingInteractions = 0,
    this.lastResult,
  });

  FLState copyWith({int? round, bool? isTraining, int? pendingInteractions, String? lastResult}) =>
      FLState(
        round: round ?? this.round,
        isTraining: isTraining ?? this.isTraining,
        pendingInteractions: pendingInteractions ?? this.pendingInteractions,
        lastResult: lastResult ?? this.lastResult,
      );
}

class FLNotifier extends StateNotifier<FLState> {
  final FLClientService _client;
  final Ref _ref;

  FLNotifier(this._client, this._ref) : super(const FLState()) {
    _init();
  }

  Future<void> _init() async {
    try {
      await _client.fetchGlobalWeights();
      state = state.copyWith(round: _client.round);
    } catch (_) {
      // Silently fail — FL is best-effort
    }
  }

  void recordInteraction(LandmarkModel landmark, double label) {
    _recordWithType(landmark.type, label);
  }

  void recordInteractionForType(String landmarkType, double label) {
    _recordWithType(landmarkType, label);
  }

  void _recordWithType(String landmarkType, double label) {
    final userInterests = _ref.read(authProvider).user?.interests ?? [];
    final features = _client.buildFeatureVector(
      userInterests: userInterests.map((e) => e.toString()).toList(),
      landmarkType: landmarkType,
    );
    _client.recordInteraction(features, label);
    state = state.copyWith(pendingInteractions: _client.pendingInteractions);

    if (_client.pendingInteractions >= _autoRoundThreshold) {
      runRound();
    }
  }

  Future<void> runRound() async {
    if (state.isTraining || _client.pendingInteractions == 0) return;
    state = state.copyWith(isTraining: true);
    try {
      final result = await _client.runFLRound();
      final skipped = result['skipped'] == true;
      state = state.copyWith(
        isTraining: false,
        round: _client.round,
        pendingInteractions: _client.pendingInteractions,
        lastResult: skipped ? 'No new interactions' : 'Round ${_client.round} complete',
      );
    } catch (_) {
      state = state.copyWith(isTraining: false, lastResult: 'Round failed — will retry');
    }
  }

  Future<Map<String, dynamic>> getStatus() => _client.getStatus();
}

final flProvider = StateNotifierProvider<FLNotifier, FLState>((ref) {
  final api = ref.watch(apiServiceProvider);
  return FLNotifier(FLClientService(api), ref);
});
