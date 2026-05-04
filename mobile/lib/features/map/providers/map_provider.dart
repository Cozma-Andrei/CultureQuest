import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/route_model.dart';
import '../../../shared/models/landmark_model.dart';

class MapState {
  final RouteModel? activeRoute;
  final List<LandmarkModel> nearbyLandmarks;
  final bool isLoading;

  const MapState({this.activeRoute, this.nearbyLandmarks = const [], this.isLoading = false});
}

class MapNotifier extends StateNotifier<MapState> {
  MapNotifier() : super(const MapState());

  Future<void> loadNearbyLandmarks(double lat, double lng) async {}

  Future<void> generateRoute(List<String> interests, int availableMinutes) async {}
}

final mapProvider = StateNotifierProvider<MapNotifier, MapState>(
  (_) => MapNotifier(),
);
