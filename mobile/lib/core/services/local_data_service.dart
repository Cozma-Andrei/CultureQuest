import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/providers/auth_provider.dart';

/// Stores all individual user behaviour on-device only, namespaced per user.
/// When a different user logs in they get a completely separate data set.
class LocalDataService {
  static const _visitedSuffix    = 'visited_landmarks';
  static const _ratingsSuffix    = 'my_ratings';
  static const _routesSuffix     = 'my_routes';
  static const _completedSuffix  = 'completed_quests';
  static const _votedSuffix      = 'voted_items';
  static const _commentIdsSuffix = 'my_comment_ids'; // landmarkId → commentId

  final SharedPreferences _prefs;
  final String _userId; // 'guest' for unauthenticated

  LocalDataService(this._prefs, [this._userId = 'guest']);

  // Key helper - every key is namespaced to this user
  String _k(String suffix) => 'cq_${_userId}_$suffix';

  // ── Visits ────────────────────────────────────────────────────────────────

  Set<String> getVisitedIds() {
    final raw = _prefs.getStringList(_k(_visitedSuffix));
    return raw != null ? Set<String>.from(raw) : {};
  }

  bool isVisited(String landmarkId) => getVisitedIds().contains(landmarkId);

  Future<void> markVisited(String landmarkId) async {
    final ids = getVisitedIds()..add(landmarkId);
    await _prefs.setStringList(_k(_visitedSuffix), ids.toList());
  }

  // ── Ratings ───────────────────────────────────────────────────────────────

  Map<String, double> getAllRatings() {
    final raw = _prefs.getString(_k(_ratingsSuffix));
    if (raw == null) return {};
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, (v as num).toDouble()));
  }

  double? getMyRating(String landmarkId) => getAllRatings()[landmarkId];

  Future<void> setMyRating(String landmarkId, double rating) async {
    final ratings = getAllRatings()..[landmarkId] = rating;
    await _prefs.setString(_k(_ratingsSuffix), jsonEncode(ratings));
  }

  // ── Completed quests ──────────────────────────────────────────────────────

  Set<String> getCompletedQuestIds() {
    final raw = _prefs.getStringList(_k(_completedSuffix));
    return raw != null ? Set<String>.from(raw) : {};
  }

  bool isQuestCompleted(String questId) => getCompletedQuestIds().contains(questId);

  Future<void> markQuestCompleted(String questId) async {
    final ids = getCompletedQuestIds()..add(questId);
    await _prefs.setStringList(_k(_completedSuffix), ids.toList());
  }

  // ── Comment IDs (per-landmark, for re-review / replace) ──────────────────

  Map<String, String> _getCommentIds() {
    final raw = _prefs.getString(_k(_commentIdsSuffix));
    if (raw == null) return {};
    return Map<String, String>.from(jsonDecode(raw));
  }

  String? getMyCommentId(String landmarkId) => _getCommentIds()[landmarkId];

  Future<void> setMyCommentId(String landmarkId, String commentId) async {
    final ids = _getCommentIds()..[landmarkId] = commentId;
    await _prefs.setString(_k(_commentIdsSuffix), jsonEncode(ids));
  }

  // ── Routes ────────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> getRoutes() {
    final raw = _prefs.getString(_k(_routesSuffix));
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  Future<void> saveRoute(Map<String, dynamic> routeJson) async {
    final routes = getRoutes();
    final idx = routes.indexWhere((r) => r['id'] == routeJson['id']);
    if (idx >= 0) {
      routes[idx] = routeJson;
    } else {
      routes.insert(0, routeJson);
    }
    await _prefs.setString(_k(_routesSuffix), jsonEncode(routes));
  }

  Future<void> updateRoute(Map<String, dynamic> routeJson) => saveRoute(routeJson);

  Future<void> deleteRoute(String routeId) async {
    final routes = getRoutes()..removeWhere((r) => r['id'] == routeId);
    await _prefs.setString(_k(_routesSuffix), jsonEncode(routes));
  }

  // ── Voted community items ─────────────────────────────────────────────────

  Set<String> getVotedItems() {
    final raw = _prefs.getStringList(_k(_votedSuffix));
    return raw != null ? Set<String>.from(raw) : {};
  }

  bool hasVoted(String itemId) => getVotedItems().contains(itemId);

  Future<void> markVoted(String itemId) async {
    final ids = getVotedItems()..add(itemId);
    await _prefs.setStringList(_k(_votedSuffix), ids.toList());
  }

  // ── Clear (this user's data only) ─────────────────────────────────────────

  Future<void> clearAll() async {
    await _prefs.remove(_k(_visitedSuffix));
    await _prefs.remove(_k(_ratingsSuffix));
    await _prefs.remove(_k(_routesSuffix));
    await _prefs.remove(_k(_completedSuffix));
    await _prefs.remove(_k(_votedSuffix));
    await _prefs.remove(_k(_commentIdsSuffix));
  }
}

// SharedPreferences instance exposed so localDataProvider can watch auth
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override in ProviderScope');
});

// Automatically scoped to the current user - changes when user logs in/out
final localDataProvider = Provider<LocalDataService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final userId = ref.watch(authProvider.select((s) => s.user?.id ?? 'guest'));
  return LocalDataService(prefs, userId);
});
