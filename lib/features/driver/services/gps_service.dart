import 'package:geolocator/geolocator.dart';

/// Wraps Geolocator: permission handling + continuous position stream.
class GpsService {
  static const _settings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 15, // emit only when moved ≥15 m
  );

  /// Request location permissions. Throws if denied.
  Future<void> requestPermissions() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Location services are disabled. Please enable GPS.');
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      throw Exception(
          'Location permission denied. Enable it in Settings to go on route.');
    }
  }

  Stream<Position> get positionStream =>
      Geolocator.getPositionStream(locationSettings: _settings);

  Future<Position> getCurrentPosition() =>
      Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
}
