import 'dart:async';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/constants/app_constants.dart';

typedef NearbyUserCallback = void Function(String userId, String displayName, double distanceM);

/// Detects when other users are nearby using a WebSocket connection to the backend.
///
/// The device sends location updates through the socket every [_reportIntervalS]
/// seconds. The server queries MongoDB's 2dsphere index for other opted-in users
/// within the configured radius and pushes matches back through the same socket.
class UserProximityService {
  static const _reportIntervalS = 30;

  WebSocketChannel? _channel;
  StreamSubscription? _channelSub;
  StreamSubscription<Position>? _locationSub;
  Timer? _reportTimer;
  NearbyUserCallback? _onUserNearby;
  Position? _lastPosition;

  Future<void> start({
    required String authToken,
    required NearbyUserCallback onUserNearby,
  }) async {
    _onUserNearby = onUserNearby;

    final uri = Uri.parse('ws://${AppConstants.baseHost}/api/users/ws/proximity?token=$authToken');
    _channel = WebSocketChannel.connect(uri);

    _channelSub = _channel!.stream.listen(_onMessage);

    _locationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(distanceFilter: 30),
    ).listen((position) {
      _lastPosition = position;
    });

    _reportTimer = Timer.periodic(
      const Duration(seconds: _reportIntervalS),
      (_) => _reportLocation(),
    );
  }

  void _reportLocation() {
    if (_lastPosition == null || _channel == null) return;
    _channel!.sink.add(jsonEncode({
      'lat': _lastPosition!.latitude,
      'lng': _lastPosition!.longitude,
    }));
  }

  void _onMessage(dynamic raw) {
    final data = jsonDecode(raw as String) as Map<String, dynamic>;
    if (data['type'] == 'nearby_user') {
      _onUserNearby?.call(
        data['user_id'] as String,
        data['display_name'] as String,
        (data['distance_m'] as num).toDouble(),
      );
    }
  }

  Future<void> stop() async {
    _reportTimer?.cancel();
    await _locationSub?.cancel();
    await _channelSub?.cancel();
    await _channel?.sink.close();
  }
}
