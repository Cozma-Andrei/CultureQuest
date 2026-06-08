import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../shared/models/landmark_model.dart';
import '../../../shared/models/route_model.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/local_data_service.dart';
import '../../auth/providers/auth_provider.dart';

const _proximityMeters = 80.0;

class MapState {
  final Position? position;
  final List<LandmarkModel> landmarks;
  final List<LandmarkModel> allLandmarks;
  final RouteModel? activeRoute;
  final List<RouteWithProgress> myRoutes;
  final List<RouteWithProgress> globalRoutes;
  final RouteWithProgress? activeProgressRoute;
  final bool isLocating;
  final bool isLoadingLandmarks;
  final bool isGeneratingRoute;
  final bool isLoadingRoutes;
  final String? error;

  const MapState({
    this.position,
    this.landmarks = const [],
    this.allLandmarks = const [],
    this.activeRoute,
    this.myRoutes = const [],
    this.globalRoutes = const [],
    this.activeProgressRoute,
    this.isLocating = false,
    this.isLoadingLandmarks = false,
    this.isGeneratingRoute = false,
    this.isLoadingRoutes = false,
    this.error,
  });

  MapState copyWith({
    Position? position,
    List<LandmarkModel>? landmarks,
    List<LandmarkModel>? allLandmarks,
    RouteModel? activeRoute,
    List<RouteWithProgress>? myRoutes,
    List<RouteWithProgress>? globalRoutes,
    RouteWithProgress? activeProgressRoute,
    bool? isLocating,
    bool? isLoadingLandmarks,
    bool? isGeneratingRoute,
    bool? isLoadingRoutes,
    String? error,
    bool clearRoute = false,
    bool clearProgressRoute = false,
    bool clearError = false,
  }) =>
      MapState(
        position: position ?? this.position,
        landmarks: landmarks ?? this.landmarks,
        allLandmarks: allLandmarks ?? this.allLandmarks,
        activeRoute: clearRoute ? null : activeRoute ?? this.activeRoute,
        myRoutes: myRoutes ?? this.myRoutes,
        globalRoutes: globalRoutes ?? this.globalRoutes,
        activeProgressRoute: clearProgressRoute ? null : activeProgressRoute ?? this.activeProgressRoute,
        isLocating: isLocating ?? this.isLocating,
        isLoadingLandmarks: isLoadingLandmarks ?? this.isLoadingLandmarks,
        isGeneratingRoute: isGeneratingRoute ?? this.isGeneratingRoute,
        isLoadingRoutes: isLoadingRoutes ?? this.isLoadingRoutes,
        error: clearError ? null : error ?? this.error,
      );
}

class MapNotifier extends StateNotifier<MapState> {
  final ApiService _api;
  final LocalDataService _local;
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<Position>? _headingSub; // high-frequency, for arrow updates
  bool _disposed = false;

  MapNotifier(this._api, this._local) : super(const MapState(isLocating: true)) {
    _initLocation();
    _loadLocalRoutes();
    fetchGlobalRoutes();
  }

  Future<void> _initLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        state = state.copyWith(isLocating: false, error: 'Location permission denied');
        return;
      }

      // Don't use getCurrentPosition (can return stale cached fix).
      // The position stream will provide the first accurate fix via _onPosition.
      state = state.copyWith(isLocating: false);

      // Main position stream - triggers map dot movement (8m filter reduces jitter)
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          distanceFilter: 8,
          accuracy: LocationAccuracy.high,
        ),
      ).listen(_onPosition);

      // High-frequency heading stream - only updates the heading for the arrow overlay
      _headingSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          distanceFilter: 0,
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      ).listen((pos) {
        if (_disposed) return;
        // Only update heading; keep existing lat/lng to avoid jitter on the dot
        final cur = state.position;
        if (cur != null && pos.heading != cur.heading) {
          state = state.copyWith(
            position: Position(
              latitude: cur.latitude,
              longitude: cur.longitude,
              accuracy: cur.accuracy,
              altitude: cur.altitude,
              altitudeAccuracy: cur.altitudeAccuracy,
              heading: pos.heading,
              headingAccuracy: pos.headingAccuracy,
              speed: pos.speed,
              speedAccuracy: pos.speedAccuracy,
              timestamp: cur.timestamp,
            ),
          );
        }
      });
    } catch (_) {
      state = state.copyWith(isLocating: false, error: 'Could not get location');
    }
  }

  void _onPosition(Position pos) {
    if (_disposed) return;
    final isFirstFix = state.position == null;
    // Reject any fix worse than 50 m: network-location noise on bad-internet days
    // can produce large accuracy spikes that make the dot jump erratically.
    // The threshold is 100 m only for the very first fix (we need something to start with);
    // after that we tighten to 50 m.
    final threshold = isFirstFix ? 100.0 : 50.0;
    if (pos.accuracy > threshold) return;
    state = state.copyWith(position: pos);
    // Fetch landmarks on the first accepted fix
    if (isFirstFix) {
      fetchLandmarks(pos.latitude, pos.longitude);
      fetchAllLandmarks();
    }
  }

  /// Annotate a list of raw landmarks with local visited/rating data.
  List<LandmarkModel> _annotate(List<LandmarkModel> raw) {
    final visited = _local.getVisitedIds();
    final ratings = _local.getAllRatings();
    return raw.map((l) => l.withLocal(
      visitedByMe: visited.contains(l.id),
      myRating: ratings[l.id],
    )).toList();
  }

  Future<void> fetchLandmarks(double lat, double lng) async {
    state = state.copyWith(isLoadingLandmarks: true, clearError: true);
    try {
      final res = await _api.get('/landmarks/', params: {'lat': lat, 'lng': lng, 'radius_m': 1500});
      final raw = (res.data as List).map((j) => LandmarkModel.fromJson(j as Map<String, dynamic>)).toList();
      state = state.copyWith(landmarks: _annotate(raw), isLoadingLandmarks: false);
    } catch (_) {
      // Offline fallback: filter the cached allLandmarks by distance
      final all = state.allLandmarks;
      if (all.isNotEmpty) {
        final nearby = all.where((l) {
          final d = Geolocator.distanceBetween(lat, lng, l.location.lat, l.location.lng);
          return d <= 1500;
        }).toList();
        state = state.copyWith(landmarks: nearby, isLoadingLandmarks: false);
      } else {
        state = state.copyWith(isLoadingLandmarks: false);
      }
    }
  }

  Future<void> fetchAllLandmarks() async {
    try {
      final res = await _api.get('/landmarks/all');
      final raw = (res.data as List).map((j) => LandmarkModel.fromJson(j as Map<String, dynamic>)).toList();
      // Persist to cache so the app works offline on next launch
      _local.saveLandmarksCache(jsonEncode(res.data));
      state = state.copyWith(allLandmarks: _annotate(raw));
    } catch (_) {
      // Offline fallback: load from SharedPreferences cache
      final cached = _local.getLandmarksCache();
      if (cached != null && state.allLandmarks.isEmpty) {
        try {
          final raw = (jsonDecode(cached) as List)
              .map((j) => LandmarkModel.fromJson(j as Map<String, dynamic>))
              .toList();
          state = state.copyWith(allLandmarks: _annotate(raw));
        } catch (_) {}
      }
    }
  }

  void _loadLocalRoutes() {
    final stored = _local.getRoutes();
    final routes = stored.map((j) => RouteWithProgress.fromJson(j)).toList();
    state = state.copyWith(myRoutes: routes, isLoadingRoutes: false);
  }

  Future<void> fetchMyRoutes() async {
    _loadLocalRoutes();
  }

  Future<void> fetchGlobalRoutes() async {
    try {
      final res = await _api.get('/routes/global');
      final routes = (res.data as List)
          .map((j) => RouteWithProgress.fromJson(j as Map<String, dynamic>))
          .toList();
      state = state.copyWith(globalRoutes: routes);
    } catch (_) {}
  }

  Future<void> renameRoute(String routeId, String name) async {
    final updated = state.myRoutes.map((r) {
      if (r.id != routeId) return r;
      return RouteWithProgress(
        id: r.id, name: name.trim().isEmpty ? null : name.trim(),
        stops: r.stops, totalDistanceM: r.totalDistanceM,
        totalDurationMinutes: r.totalDurationMinutes,
        generatedAt: r.generatedAt, visitedCount: r.visitedCount,
      );
    }).toList();
    for (final r in updated) {
      if (r.id == routeId) await _local.updateRoute(_routeToJson(r));
    }
    final isActive = state.activeProgressRoute?.id == routeId;
    state = state.copyWith(
      myRoutes: updated,
      activeProgressRoute: isActive ? updated.firstWhere((r) => r.id == routeId) : null,
    );
  }

  void viewRouteOnMap(RouteWithProgress route) {
    state = state.copyWith(activeProgressRoute: route, clearRoute: true);
  }

  void clearProgressRoute() {
    state = state.copyWith(clearProgressRoute: true);
  }


  Map<String, dynamic> _routeToJson(RouteWithProgress r) => {
    'id': r.id, 'name': r.name,
    'stops': r.stops.map((s) => {
      'landmark': {
        'id': s.landmark.id, 'name': s.landmark.name, 'type': s.landmark.type,
        'location': {'lat': s.landmark.location.lat, 'lng': s.landmark.location.lng},
        'description': s.landmark.description, 'categories': s.landmark.categories,
        'stories': s.landmark.stories, 'rating': s.landmark.rating,
        'visit_count': s.landmark.visitCount, 'has_active_quest': s.landmark.hasActiveQuest,
      },
      'visited': s.visited,
      'dwell_minutes': s.dwellMinutes,
    }).toList(),
    'total_distance_m': r.totalDistanceM,
    'total_duration_minutes': r.totalDurationMinutes,
    'generated_at': r.generatedAt,
    'visited_count': r.visitedCount,
  };

  Future<void> generateRoute({int availableMinutes = 300, double flTiebreakerM = 200.0}) async {
    final pos = state.position;
    if (pos == null) return;
    state = state.copyWith(isGeneratingRoute: true, clearError: true, clearProgressRoute: true);
    try {
      final res = await _api.post('/routes/generate', data: {
        'start_location': {'lat': pos.latitude, 'lng': pos.longitude},
        'interests': [],
        'available_minutes': availableMinutes,
        'max_landmarks': 5,
        'fl_tiebreaker_m': flTiebreakerM,
      });
      final route = RouteModel.fromJson(res.data);
      // Convert to RouteWithProgress (no stops visited yet) and save locally
      final withProgress = RouteWithProgress(
        id: route.id,
        stops: route.stops.map((s) => RouteStopWithProgress(
          landmark: s.landmark, visited: false,
          dwellMinutes: s.estimatedDurationMinutes,  // preserves type-based time from backend
        )).toList(),
        totalDistanceM: route.totalDistanceM,
        totalDurationMinutes: route.totalDurationMinutes,
        generatedAt: res.data['generated_at'] ?? '',
        visitedCount: 0,
      );
      // Use _routeToJson so dwell_minutes is persisted correctly
      await _local.saveRoute(_routeToJson(withProgress));
      _loadLocalRoutes();
      state = state.copyWith(activeRoute: route, isGeneratingRoute: false);
    } catch (_) {
      state = state.copyWith(isGeneratingRoute: false, error: 'Could not generate route. Make sure landmarks are seeded.');
    }
  }

  Future<void> seedAndReload() async {
    final pos = state.position;
    if (pos == null) return;
    state = state.copyWith(isLoadingLandmarks: true);
    try {
      await _api.post('/landmarks/seed?lat=${pos.latitude}&lng=${pos.longitude}');
      await Future.wait([fetchLandmarks(pos.latitude, pos.longitude), fetchAllLandmarks()]);
    } catch (_) {
      state = state.copyWith(isLoadingLandmarks: false, error: 'Could not seed landmarks');
    }
  }

  void clearRoute() => state = state.copyWith(clearRoute: true);

  @override
  void dispose() {
    _disposed = true;
    _positionSub?.cancel();
    _headingSub?.cancel();
    super.dispose();
  }
}

// Sentinel used in firstWhere orElse - never actually shown in UI
const _dummy = LandmarkModel(
  id: '', name: '', type: '', location: GeoPoint(lat: 0, lng: 0),
  description: '',
);

final mapProvider = StateNotifierProvider<MapNotifier, MapState>(
  (ref) => MapNotifier(ref.watch(apiServiceProvider), ref.watch(localDataProvider)),
);
