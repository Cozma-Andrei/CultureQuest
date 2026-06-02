import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../shared/models/landmark_model.dart';
import '../../map/providers/map_provider.dart';

class ProximityState {
  final LandmarkModel? nearbyLandmark;
  const ProximityState({this.nearbyLandmark});
}

class ProximityNotifier extends StateNotifier<ProximityState> {
  final Ref _ref;
  static const _radiusM = 1500.0; // matches the map landmark display radius

  ProximityNotifier(this._ref) : super(const ProximityState());

  /// Call this when the user explicitly taps "Find Nearby".
  /// Returns true if a landmark was found within radius.
  bool checkNow() {
    final mapState = _ref.read(mapProvider);
    final pos = mapState.position;
    if (pos == null) return false;

    // Find the closest landmark within radius
    LandmarkModel? closest;
    double closestDist = double.infinity;
    for (final l in mapState.allLandmarks.isNotEmpty
        ? mapState.allLandmarks
        : mapState.landmarks) {
      final dist = Geolocator.distanceBetween(
          pos.latitude, pos.longitude, l.location.lat, l.location.lng);
      if (dist <= _radiusM && dist < closestDist) {
        closest = l;
        closestDist = dist;
      }
    }

    if (closest != null) {
      state = ProximityState(nearbyLandmark: closest);
      return true;
    } else {
      state = const ProximityState();
      return false;
    }
  }

  void dismiss() => state = const ProximityState();
}

final proximityProvider =
    StateNotifierProvider<ProximityNotifier, ProximityState>(
  (ref) => ProximityNotifier(ref),
);
