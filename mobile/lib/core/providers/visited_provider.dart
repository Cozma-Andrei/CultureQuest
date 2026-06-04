import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/local_data_service.dart';

class VisitedNotifier extends StateNotifier<Set<String>> {
  final LocalDataService _local;

  VisitedNotifier(this._local) : super(_local.getVisitedIds());

  Future<void> markVisited(String landmarkId) async {
    await _local.markVisited(landmarkId);
    state = {...state, landmarkId};
  }

  bool isVisited(String landmarkId) => state.contains(landmarkId);
}

final visitedProvider = StateNotifierProvider<VisitedNotifier, Set<String>>((ref) {
  // Recreates automatically when the user changes (login/logout)
  return VisitedNotifier(ref.watch(localDataProvider));
});
