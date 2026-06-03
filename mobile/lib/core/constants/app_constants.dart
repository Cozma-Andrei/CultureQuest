class AppConstants {
  static const appName = 'CultureQuest';

  // Set at build time with --dart-define=API_HOST=<ip>:8000
  // Falls back to 10.0.2.2 (Android emulator → host machine).
  // For a real device on the same network use the machine's LAN IP:
  //   flutter run --dart-define=API_HOST=192.168.x.x:8000
  // Default: localhost works on a real device when `adb reverse tcp:8000 tcp:8000` is active.
  // For emulator use 10.0.2.2:8000. For wireless use --dart-define=API_HOST=<ip>:8000.
  static const _apiHost =
      String.fromEnvironment('API_HOST', defaultValue: 'localhost:8000');

  static const baseHost = _apiHost;
  static const baseUrl = 'http://$_apiHost/api';
  static const flServerUrl = _apiHost; // port handled separately if needed

  static const defaultRadiusMeters = 500;
  static const defaultMaxLandmarks = 5;
  static const defaultAvailableMinutes = 90;

  static const mlInputDim = 16;
  static const tfliteModelPath = 'assets/models/recommendation.tflite';
}
