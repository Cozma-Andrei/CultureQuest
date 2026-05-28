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
  final Set<String> _inside = {};

  // Hysteresis: require more distance to exit than to enter so GPS
  // noise cannot cause a false exit → re-enter loop.
  static const _enterRadiusM = 100.0;
  static const _exitRadiusM  = 130.0;

  ProximityNotifier(this._ref) : super(const ProximityState()) {
    // Check immediately with whatever is already loaded.
    final mapState = _ref.read(mapProvider);
    if (mapState.position != null) {
      _check(mapState.position!.latitude, mapState.position!.longitude, mapState.landmarks);
    }

    // Single source of position truth: reuse mapProvider's stream.
    // This avoids running a second parallel Geolocator stream.
    _ref.listen<MapState>(mapProvider, (prev, next) {
      final pos = next.position;
      if (pos == null) return;
      final landmarksChanged = prev?.landmarks != next.landmarks;
      final posChanged = prev?.position != next.position;
      if (landmarksChanged || posChanged) {
        _check(pos.latitude, pos.longitude, next.landmarks);
      }
    });
  }

  void _check(double lat, double lng, List<LandmarkModel> landmarks) {
    for (final l in landmarks) {
      final dist = Geolocator.distanceBetween(lat, lng, l.location.lat, l.location.lng);
      final wasInside = _inside.contains(l.id);

      if (!wasInside && dist <= _enterRadiusM) {
        _inside.add(l.id);
        if (state.nearbyLandmark == null) {
          state = ProximityState(nearbyLandmark: l);
        }
      } else if (wasInside && dist > _exitRadiusM) {
        _inside.remove(l.id);
        if (state.nearbyLandmark?.id == l.id) {
          state = const ProximityState();
        }
      }
    }
  }

  void dismiss() => state = const ProximityState();
}

final proximityProvider = StateNotifierProvider<ProximityNotifier, ProximityState>(
  (ref) => ProximityNotifier(ref),
);
