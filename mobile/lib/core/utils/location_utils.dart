import 'package:geolocator/geolocator.dart';

class LocationUtils {
  static Future<Position?> getCurrentPosition() async {
    // TODO: request permission, return position
    return null;
  }

  static double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
  }
}
