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
  final LandmarkModel? resumeTarget;
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
    this.resumeTarget,
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
    LandmarkModel? resumeTarget,
    bool? isLocating,
    bool? isLoadingLandmarks,
    bool? isGeneratingRoute,
    bool? isLoadingRoutes,
    String? error,
    bool clearRoute = false,
    bool clearProgressRoute = false,
    bool clearResumeTarget = false,
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
        resumeTarget: clearResumeTarget ? null : resumeTarget ?? this.resumeTarget,
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
  final Set<String> _autoVisited = {};

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

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      state = state.copyWith(position: position, isLocating: false);
      await Future.wait([
        fetchLandmarks(position.latitude, position.longitude),
        fetchAllLandmarks(),
      ]);

      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          distanceFilter: 8,           // only update after 8m real movement
          accuracy: LocationAccuracy.high,
        ),
      ).listen(_onPosition);
    } catch (_) {
      state = state.copyWith(isLocating: false, error: 'Could not get location');
    }
  }

  void _onPosition(Position pos) {
    state = state.copyWith(position: pos);
    _checkRouteProximity(pos);
  }

  void _checkRouteProximity(Position pos) {
    final route = state.activeProgressRoute;
    if (route == null) return;
    final nextStop = route.stops.firstWhere(
      (s) => !s.visited && !_autoVisited.contains(s.landmark.id),
      orElse: () => const RouteStopWithProgress(landmark: _dummy, visited: true),
    );
    if (nextStop.visited) return; // all done or nothing left

    final dist = Geolocator.distanceBetween(
      pos.latitude, pos.longitude,
      nextStop.landmark.location.lat, nextStop.landmark.location.lng,
    );
    if (dist <= _proximityMeters) {
      _autoVisited.add(nextStop.landmark.id);
      _arriveAtStop(nextStop.landmark, route);
    }
  }

  Future<void> _arriveAtStop(LandmarkModel landmark, RouteWithProgress route) async {
    // Mark visited locally; only increment server counter on first visit
    final isFirstVisit = !_local.isVisited(landmark.id);
    await _local.markVisited(landmark.id);
    _applyVisit(landmark.id);
    if (isFirstVisit) _api.post('/landmarks/${landmark.id}/visit').ignore();
    // Set resumeTarget so map screen fetches navigation to the NEXT stop
    final updated = state.activeProgressRoute;
    if (updated == null) return;
    final nextUnvisited = updated.stops.firstWhere(
      (s) => !s.visited,
      orElse: () => const RouteStopWithProgress(landmark: _dummy, visited: true),
    );
    if (!nextUnvisited.visited) {
      state = state.copyWith(resumeTarget: nextUnvisited.landmark);
    }
  }

  void _applyVisit(String landmarkId) {
    final route = state.activeProgressRoute;
    if (route == null) return;
    final newStops = route.stops.map((s) =>
      s.landmark.id == landmarkId
          ? RouteStopWithProgress(landmark: s.landmark, visited: true)
          : s,
    ).toList();
    final updated = RouteWithProgress(
      id: route.id, name: route.name, stops: newStops,
      totalDistanceM: route.totalDistanceM, totalDurationMinutes: route.totalDurationMinutes,
      generatedAt: route.generatedAt, visitedCount: newStops.where((s) => s.visited).length,
    );
    final newRoutes = state.myRoutes.map((r) => r.id == route.id ? updated : r).toList();
    state = state.copyWith(activeProgressRoute: updated, myRoutes: newRoutes);
    // Persist progress locally
    _local.updateRoute(_routeToJson(updated));
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
      state = state.copyWith(isLoadingLandmarks: false);
    }
  }

  Future<void> fetchAllLandmarks() async {
    try {
      final res = await _api.get('/landmarks/all');
      final raw = (res.data as List).map((j) => LandmarkModel.fromJson(j as Map<String, dynamic>)).toList();
      state = state.copyWith(allLandmarks: _annotate(raw));
    } catch (_) {}
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
    state = state.copyWith(activeProgressRoute: route, clearRoute: true, clearResumeTarget: true);
  }

  void resumeRoute(RouteWithProgress route) {
    final next = route.stops.firstWhere((s) => !s.visited, orElse: () => route.stops.first);
    state = state.copyWith(activeProgressRoute: route, resumeTarget: next.landmark, clearRoute: true);
  }

  void consumeResumeTarget() => state = state.copyWith(clearResumeTarget: true);

  void clearProgressRoute() {
    _autoVisited.clear();
    state = state.copyWith(clearProgressRoute: true, clearResumeTarget: true);
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
    }).toList(),
    'total_distance_m': r.totalDistanceM,
    'total_duration_minutes': r.totalDurationMinutes,
    'generated_at': r.generatedAt,
    'visited_count': r.visitedCount,
  };

  Future<void> generateRoute({int availableMinutes = 90}) async {
    final pos = state.position;
    if (pos == null) return;
    state = state.copyWith(isGeneratingRoute: true, clearError: true, clearProgressRoute: true);
    try {
      final res = await _api.post('/routes/generate', data: {
        'start_location': {'lat': pos.latitude, 'lng': pos.longitude},
        'interests': [],
        'available_minutes': availableMinutes,
        'max_landmarks': 5,
      });
      final route = RouteModel.fromJson(res.data);
      // Convert to RouteWithProgress (no stops visited yet) and save locally
      final withProgress = RouteWithProgress(
        id: route.id,
        stops: route.stops.map((s) => RouteStopWithProgress(landmark: s.landmark, visited: false)).toList(),
        totalDistanceM: route.totalDistanceM,
        totalDurationMinutes: route.totalDurationMinutes,
        generatedAt: res.data['generated_at'] ?? '',
        visitedCount: 0,
      );
      await _local.saveRoute(jsonDecode(jsonEncode({
        'id': withProgress.id,
        'name': withProgress.name,
        'stops': withProgress.stops.map((s) => {
          'landmark': {
            'id': s.landmark.id, 'name': s.landmark.name, 'type': s.landmark.type,
            'location': {'lat': s.landmark.location.lat, 'lng': s.landmark.location.lng},
            'description': s.landmark.description,
            'categories': s.landmark.categories, 'stories': s.landmark.stories,
            'rating': s.landmark.rating, 'visit_count': s.landmark.visitCount,
            'has_active_quest': s.landmark.hasActiveQuest,
          },
          'visited': s.visited,
        }).toList(),
        'total_distance_m': withProgress.totalDistanceM,
        'total_duration_minutes': withProgress.totalDurationMinutes,
        'generated_at': withProgress.generatedAt,
        'visited_count': 0,
      })));
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
    _positionSub?.cancel();
    super.dispose();
  }
}

// Sentinel used in firstWhere orElse — never actually shown in UI
const _dummy = LandmarkModel(
  id: '', name: '', type: '', location: GeoPoint(lat: 0, lng: 0),
  description: '',
);

final mapProvider = StateNotifierProvider<MapNotifier, MapState>(
  (ref) => MapNotifier(ref.watch(apiServiceProvider), ref.watch(localDataProvider)),
);
