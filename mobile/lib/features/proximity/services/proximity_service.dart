import 'dart:async';
import 'package:geolocator/geolocator.dart';

typedef LandmarkPin = ({String id, double lat, double lng, double radiusM});
typedef LandmarkFetcher = Future<List<LandmarkPin>> Function(double lat, double lng);

/// Manual geofencing built on geolocator position streams.
///
/// On every position update, distances to all active landmarks are computed.
/// ENTER fires when the user crosses into a radius; EXIT when they leave.
/// Windowing: when the user moves [_reRegisterThresholdM] from the last
/// fetch point, nearby landmarks are re-fetched from the backend.
class ProximityService {
  static const _reRegisterThresholdM = 200.0;

  StreamSubscription<Position>? _locationSub;
  Position? _lastFetchPosition;
  List<LandmarkPin> _landmarks = [];
  final Set<String> _inside = {};
  LandmarkFetcher? _fetcher;

  Future<void> refreshNow() async {
    final pos = _lastFetchPosition;
    if (pos == null || _fetcher == null) return;
    _landmarks = await _fetcher!(pos.latitude, pos.longitude);
  }

  Future<void> start({
    required LandmarkFetcher fetchNearbyLandmarks,
    required void Function(String landmarkId) onEnter,
    void Function(String landmarkId)? onExit,
  }) async {
    _fetcher = fetchNearbyLandmarks;
    final position = await Geolocator.getCurrentPosition();
    _landmarks = await fetchNearbyLandmarks(position.latitude, position.longitude);
    _lastFetchPosition = position;

    _locationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(distanceFilter: 10),
    ).listen((pos) async {
      final movedFromFetch = Geolocator.distanceBetween(
        _lastFetchPosition!.latitude,
        _lastFetchPosition!.longitude,
        pos.latitude,
        pos.longitude,
      );
      if (movedFromFetch >= _reRegisterThresholdM) {
        _landmarks = await fetchNearbyLandmarks(pos.latitude, pos.longitude);
        _lastFetchPosition = pos;
      }

      for (final l in _landmarks) {
        final distance = Geolocator.distanceBetween(pos.latitude, pos.longitude, l.lat, l.lng);
        final isInside = distance <= l.radiusM;
        final wasInside = _inside.contains(l.id);

        if (isInside && !wasInside) {
          _inside.add(l.id);
          onEnter(l.id);
        } else if (!isInside && wasInside) {
          _inside.remove(l.id);
          onExit?.call(l.id);
        }
      }
    });
  }

  Future<void> stop() async {
    await _locationSub?.cancel();
    _inside.clear();
    _landmarks = [];
  }
}
