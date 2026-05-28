import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../shared/models/landmark_model.dart';
import '../../../shared/models/route_model.dart';
import '../../../core/services/api_service.dart';
import '../../auth/providers/auth_provider.dart';

class MapState {
  final Position? position;
  final List<LandmarkModel> landmarks;
  final List<LandmarkModel> allLandmarks;
  final RouteModel? activeRoute;
  final List<RouteWithProgress> myRoutes;
  final RouteWithProgress? activeProgressRoute;
  final LandmarkModel? resumeTarget; // next unvisited stop to centre the map on
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
  StreamSubscription<Position>? _positionSub;

  MapNotifier(this._api) : super(const MapState(isLocating: true)) {
    _initLocation();
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

      final position = await Geolocator.getCurrentPosition();
      state = state.copyWith(position: position, isLocating: false);
      await Future.wait([
        fetchLandmarks(position.latitude, position.longitude),
        fetchAllLandmarks(),
      ]);

      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(distanceFilter: 20),
      ).listen((pos) => state = state.copyWith(position: pos));
    } catch (_) {
      state = state.copyWith(isLocating: false, error: 'Could not get location');
    }
  }

  Future<void> fetchLandmarks(double lat, double lng) async {
    state = state.copyWith(isLoadingLandmarks: true, clearError: true);
    try {
      final res = await _api.get('/landmarks/', params: {'lat': lat, 'lng': lng, 'radius_m': 1500});
      final landmarks = (res.data as List).map((j) => LandmarkModel.fromJson(j as Map<String, dynamic>)).toList();
      state = state.copyWith(landmarks: landmarks, isLoadingLandmarks: false);
    } catch (_) {
      state = state.copyWith(isLoadingLandmarks: false);
    }
  }

  Future<void> fetchAllLandmarks() async {
    try {
      final res = await _api.get('/landmarks/all');
      final all = (res.data as List).map((j) => LandmarkModel.fromJson(j as Map<String, dynamic>)).toList();
      state = state.copyWith(allLandmarks: all);
    } catch (_) {}
  }

  Future<void> fetchMyRoutes() async {
    state = state.copyWith(isLoadingRoutes: true);
    try {
      final res = await _api.get('/routes/history/me');
      final routes = (res.data as List)
          .map((j) => RouteWithProgress.fromJson(j as Map<String, dynamic>))
          .toList();
      state = state.copyWith(myRoutes: routes, isLoadingRoutes: false);
    } catch (_) {
      state = state.copyWith(isLoadingRoutes: false);
    }
  }

  void viewRouteOnMap(RouteWithProgress route) {
    state = state.copyWith(
      activeProgressRoute: route,
      clearRoute: true,
      clearResumeTarget: true,
    );
  }

  void resumeRoute(RouteWithProgress route) {
    final next = route.stops.firstWhere((s) => !s.visited, orElse: () => route.stops.first);
    state = state.copyWith(
      activeProgressRoute: route,
      resumeTarget: next.landmark,
      clearRoute: true,
    );
  }

  void consumeResumeTarget() => state = state.copyWith(clearResumeTarget: true);

  void clearProgressRoute() => state = state.copyWith(clearProgressRoute: true, clearResumeTarget: true);

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
      state = state.copyWith(activeRoute: RouteModel.fromJson(res.data), isGeneratingRoute: false);
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
      await Future.wait([
        fetchLandmarks(pos.latitude, pos.longitude),
        fetchAllLandmarks(),
      ]);
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

final mapProvider = StateNotifierProvider<MapNotifier, MapState>(
  (ref) => MapNotifier(ref.watch(apiServiceProvider)),
);
