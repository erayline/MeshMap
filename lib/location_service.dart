import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'mesh_service.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  static const _interval = Duration(seconds: 30);

  Timer? _timer;

  Future<void> start() async {
    await _sendBeacon();
    _timer = Timer.periodic(_interval, (_) => _sendBeacon());
  }

  Future<void> _sendBeacon() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 10));
      await MeshService().sendLocationBeacon(pos.latitude, pos.longitude);
    } catch (_) {
      // GPS unavailable — try last known as fallback.
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          await MeshService().sendLocationBeacon(last.latitude, last.longitude);
        }
      } catch (_) {}
    }
  }

  // Force an immediate beacon (e.g. when map screen opens).
  Future<void> sendNow() => _sendBeacon();

  void dispose() => _timer?.cancel();
}
