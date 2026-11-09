import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/i18n.dart';
import '../data/syria_cities.dart';

/// Damascus as a sensible default center for Petsy (Syria).
const petsyMapCenter = LatLng(33.5138, 36.2765);

class CurrentLocationResult {
  const CurrentLocationResult({
    required this.point,
    required this.fromDevice,
    this.denied = false,
    this.serviceDisabled = false,
  });

  final LatLng point;
  final bool fromDevice;
  final bool denied;
  final bool serviceDisabled;
}

class GeoService {
  GeoService._();
  static final GeoService instance = GeoService._();

  static final _distance = Distance();

  LatLng? fromKnownPlace(String text) {
    final city = findSyriaCity(text);
    if (city != null) return city.center;
    return null;
  }

  SyriaCity? cityFromText(String? text) => findSyriaCity(text);

  SyriaCity nearestCity(LatLng point) => nearestSyriaCity(point);

  /// Resolves the closest Syrian governorate from the device GPS.
  Future<({SyriaCity? city, CurrentLocationResult location})> detectCityFromGps({
    LatLng fallback = petsyMapCenter,
  }) async {
    final location = await currentLocation(fallback: fallback);
    if (!location.fromDevice) {
      return (city: null, location: location);
    }
    return (city: nearestCity(location.point), location: location);
  }

  /// Distance in kilometers between two points.
  double kmBetween(LatLng a, LatLng b) => _distance.as(LengthUnit.Kilometer, a, b);

  String formatKm(double km, String languageCode) {
    if (km < 1) return '${(km * 1000).round()} ${translate(languageCode, 'unit_m')}';
    final unit = translate(languageCode, 'unit_km');
    if (km < 10) return '${km.toStringAsFixed(1)} $unit';
    return '${km.round()} $unit';
  }

  Future<LatLng?> geocode(String text) async {
    final local = fromKnownPlace(text);
    if (local != null) return local;
    var q = text.trim();
    if (q.isEmpty) return null;
    if (!q.toLowerCase().contains('syria') && !q.contains('سوريا') && !q.contains('سورية')) {
      q = '$q, Syria';
    }
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': q,
      'format': 'json',
      'limit': '1',
    });
    try {
      final res = await http.get(uri, headers: {'User-Agent': 'PetsyApp/1.0 (lost-found)'});
      if (res.statusCode != 200) return local;
      final data = jsonDecode(res.body);
      if (data is! List || data.isEmpty) return local;
      final row = data.first as Map;
      return LatLng(double.parse('${row['lat']}'), double.parse('${row['lon']}'));
    } catch (_) {
      return local;
    }
  }

  Future<CurrentLocationResult> currentLocation({LatLng fallback = petsyMapCenter}) async {
    try {
      final service = await Geolocator.isLocationServiceEnabled();
      if (!service) {
        return CurrentLocationResult(point: fallback, fromDevice: false, serviceDisabled: true);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return CurrentLocationResult(point: fallback, fromDevice: false, denied: true);
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      return CurrentLocationResult(
        point: LatLng(pos.latitude, pos.longitude),
        fromDevice: true,
      );
    } catch (_) {
      return CurrentLocationResult(point: fallback, fromDevice: false);
    }
  }

  /// Approximate zoom level for a radius in km.
  double zoomForRadiusKm(double km) {
    if (km <= 3) return 13.5;
    if (km <= 6) return 12.5;
    if (km <= 12) return 11.5;
    if (km <= 30) return 10.5;
    if (km <= 60) return 9.5;
    return 8.5;
  }

  /// Circle points for drawing a radius ring on the map.
  List<LatLng> circlePoints(LatLng center, double radiusKm, {int steps = 64}) {
    final result = <LatLng>[];
    for (var i = 0; i <= steps; i++) {
      final bearing = (360 / steps) * i;
      result.add(_distance.offset(center, radiusKm * 1000, bearing));
    }
    return result;
  }
}
