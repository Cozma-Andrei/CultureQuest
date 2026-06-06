import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../services/fl_client_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../map/providers/map_provider.dart';
import '../../../shared/models/landmark_model.dart';
import '../../../core/services/api_service.dart';
import '../../../core/utils/opening_hours_parser.dart';

// Engagement labels — ordered weakest to strongest
const flLabelSheetOpened      = 0.3;
const flLabelAddedToRoute     = 0.5;
const flLabelQuestAttempted   = 0.5;
const flLabelNavigationStarted = 0.6;
const flLabelReviewSubmitted  = 0.7;
const flLabelQuestSuggested   = 0.80;
const flLabelStorySubmitted   = 0.85;
const flLabelQuestCompleted   = 0.9;

const _autoRoundThreshold = 15;

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
    } catch (_) {}
  }

  // ── Context helpers ────────────────────────────────────────────────────────

  List<String> get _userInterests =>
      _ref.read(authProvider).user?.interests.map((e) => e.toString()).toList() ?? [];

  /// Rank of this landmark's distance among all visible nearby landmarks.
  /// 0.0 = closest, 1.0 = farthest.
  double _relativeRank(LandmarkModel landmark, Position? pos, List<LandmarkModel> nearby) {
    if (pos == null || nearby.length <= 1) return 0.5;
    final myDist = Geolocator.distanceBetween(
        pos.latitude, pos.longitude, landmark.location.lat, landmark.location.lng);
    final sorted = nearby
        .map((l) => Geolocator.distanceBetween(
            pos.latitude, pos.longitude, l.location.lat, l.location.lng))
        .toList()
      ..sort();
    final closerCount = sorted.where((d) => d < myDist).length;
    return (closerCount / (sorted.length - 1)).clamp(0.0, 1.0);
  }

  List<double> _features(
    LandmarkModel landmark, {
    double relativeDistanceRank = 0.5,
    bool isPartOfRoute = false,
    int routeStopIndex = 0,
    int routeLength = 0,
  }) {
    return _client.buildFeatureVector(
      userInterests: _userInterests,
      landmarkType: landmark.type,
      landmarkCategories: landmark.categories,
      isOpen: OpeningHoursParser.isCurrentlyOpen(landmark.openingHours),
      isWeekend: OpeningHoursParser.isWeekend(),
      relativeDistanceRank: relativeDistanceRank,
      isPartOfRoute: isPartOfRoute,
      routeStopIndex: routeStopIndex,
      routeLength: routeLength,
    );
  }

  // ── Public recording API ───────────────────────────────────────────────────

  /// Generic engagement event (sheet opened, navigation, quest events, etc.)
  void recordEngagement(
    LandmarkModel landmark,
    double label, {
    bool isPartOfRoute = false,
    int routeStopIndex = 0,
    int routeLength = 0,
  }) {
    final mapState = _ref.read(mapProvider);
    final rank = _relativeRank(landmark, mapState.position, mapState.landmarks);
    final f = _features(
      landmark,
      relativeDistanceRank: rank,
      isPartOfRoute: isPartOfRoute,
      routeStopIndex: routeStopIndex,
      routeLength: routeLength,
    );
    _client.recordEngagement(landmark.id, f, label);
    _updateState();
  }

  /// Explicit star rating — overrides any engagement label for this landmark.
  void recordRating(LandmarkModel landmark, int stars) {
    final mapState = _ref.read(mapProvider);
    final rank = _relativeRank(landmark, mapState.position, mapState.landmarks);
    final f = _features(landmark, relativeDistanceRank: rank);
    _client.recordRating(landmark.id, f, stars);
    _updateState();
  }

  /// Convenience for quest screen which only has type/categories, not the full landmark list.
  void recordEngagementById(
    String landmarkId,
    String landmarkType,
    List<String> categories,
    double label,
  ) {
    final interests = _userInterests;
    final f = _client.buildFeatureVector(
      userInterests: interests,
      landmarkType: landmarkType,
      landmarkCategories: categories,
      isOpen: true,  // can't determine from quest screen
      isWeekend: OpeningHoursParser.isWeekend(),
    );
    _client.recordEngagement(landmarkId, f, label);
    _updateState();
  }

  // Keep backward compatibility — existing call sites use recordInteraction
  void recordInteraction(LandmarkModel landmark, double label) =>
      recordEngagement(landmark, label);

  void recordInteractionForType(String landmarkType, double label) {
    final f = _client.buildFeatureVector(
      userInterests: _userInterests,
      landmarkType: landmarkType,
      landmarkCategories: [],
      isOpen: true,
      isWeekend: OpeningHoursParser.isWeekend(),
    );
    _client.recordEngagement('$landmarkType\_${DateTime.now().millisecondsSinceEpoch}', f, label);
    _updateState();
  }

  void _updateState() {
    state = state.copyWith(pendingInteractions: _client.pendingInteractions);
    if (_client.pendingInteractions >= _autoRoundThreshold) runRound();
  }

  void clearBuffer() {
    _client.clearInteractions();
    state = state.copyWith(pendingInteractions: 0);
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
      state = state.copyWith(isTraining: false, lastResult: 'Round failed - will retry');
    }
  }

  Future<Map<String, dynamic>> getStatus() => _client.getStatus();
}

final flProvider = StateNotifierProvider<FLNotifier, FLState>((ref) {
  final api = ref.watch(apiServiceProvider);
  return FLNotifier(FLClientService(api), ref);
});
