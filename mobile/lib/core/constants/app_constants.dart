class AppConstants {
  static const appName = 'CultureQuest';
  static const baseHost = 'localhost:8000';
  static const baseUrl = 'http://$baseHost/api';
  static const flServerUrl = 'localhost:9090';

  static const defaultRadiusMeters = 500;
  static const defaultMaxLandmarks = 5;
  static const defaultAvailableMinutes = 90;

  static const mlInputDim = 16;
  static const tfliteModelPath = 'assets/models/recommendation.tflite';
}
