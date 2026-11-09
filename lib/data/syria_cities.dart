import 'package:latlong2/latlong.dart';

/// Official Syrian governorates used as the app-wide city choices.
class SyriaCity {
  const SyriaCity({
    required this.id,
    required this.ar,
    required this.en,
    required this.center,
    this.aliases = const [],
  });

  final String id;
  final String ar;
  final String en;
  final LatLng center;
  final List<String> aliases;

  String label(String languageCode) => languageCode == 'ar' ? ar : en;

  /// All searchable names (normalized lowercase).
  List<String> get searchKeys => [
        id,
        ar,
        en,
        ...aliases,
      ].map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toList();
}

const syriaCities = <SyriaCity>[
  SyriaCity(
    id: 'damascus',
    ar: 'دمشق',
    en: 'Damascus',
    center: LatLng(33.5138, 36.2765),
    aliases: ['الشام', 'dimashq'],
  ),
  SyriaCity(
    id: 'rif_dimashq',
    ar: 'ريف دمشق',
    en: 'Rif Dimashq',
    center: LatLng(33.5167, 36.4833),
    aliases: ['ريف الشام', 'rural damascus'],
  ),
  SyriaCity(
    id: 'aleppo',
    ar: 'حلب',
    en: 'Aleppo',
    center: LatLng(36.2021, 37.1343),
    aliases: ['halab'],
  ),
  SyriaCity(
    id: 'homs',
    ar: 'حمص',
    en: 'Homs',
    center: LatLng(34.7268, 36.7234),
    aliases: ['حُمص'],
  ),
  SyriaCity(
    id: 'hama',
    ar: 'حماة',
    en: 'Hama',
    center: LatLng(35.1318, 36.7578),
    aliases: ['حماه'],
  ),
  SyriaCity(
    id: 'latakia',
    ar: 'اللاذقية',
    en: 'Latakia',
    center: LatLng(35.5317, 35.7906),
    aliases: ['لاذقية', 'lattakia'],
  ),
  SyriaCity(
    id: 'tartus',
    ar: 'طرطوس',
    en: 'Tartus',
    center: LatLng(34.8950, 35.8867),
    aliases: ['طرطوس', 'tartous'],
  ),
  SyriaCity(
    id: 'idlib',
    ar: 'إدلب',
    en: 'Idlib',
    center: LatLng(35.9306, 36.6339),
    aliases: ['ادلب'],
  ),
  SyriaCity(
    id: 'deir_ez_zor',
    ar: 'دير الزور',
    en: 'Deir ez-Zor',
    center: LatLng(35.3333, 40.1500),
    aliases: ['ديرالزور', 'deir al-zor'],
  ),
  SyriaCity(
    id: 'raqqa',
    ar: 'الرقة',
    en: 'Raqqa',
    center: LatLng(35.9500, 39.0167),
    aliases: ['رقة', 'ar-raqqah'],
  ),
  SyriaCity(
    id: 'hasakah',
    ar: 'الحسكة',
    en: 'Al-Hasakah',
    center: LatLng(36.5000, 40.7500),
    aliases: ['حسكة', 'al hasakah'],
  ),
  SyriaCity(
    id: 'daraa',
    ar: 'درعا',
    en: 'Daraa',
    center: LatLng(32.6189, 36.1021),
    aliases: ['درعة', 'dara'],
  ),
  SyriaCity(
    id: 'suwayda',
    ar: 'السويداء',
    en: 'As-Suwayda',
    center: LatLng(32.7089, 36.5695),
    aliases: ['سويداء', 'sweida'],
  ),
  SyriaCity(
    id: 'quneitra',
    ar: 'القنيطرة',
    en: 'Quneitra',
    center: LatLng(33.1253, 35.8240),
    aliases: ['قنيطرة'],
  ),
];

SyriaCity? findSyriaCity(String? raw) {
  final blob = (raw ?? '').trim().toLowerCase();
  if (blob.isEmpty) return null;
  for (final city in syriaCities) {
    for (final key in city.searchKeys) {
      if (blob == key || blob.contains(key) || key.contains(blob)) return city;
    }
  }
  return null;
}

/// Canonical stored label — Arabic name (matches existing Petsy data).
String syriaCityStorageLabel(SyriaCity city) => city.ar;

SyriaCity nearestSyriaCity(LatLng point) {
  final distance = const Distance();
  SyriaCity best = syriaCities.first;
  var bestKm = distance.as(LengthUnit.Kilometer, point, best.center);
  for (final city in syriaCities.skip(1)) {
    final km = distance.as(LengthUnit.Kilometer, point, city.center);
    if (km < bestKm) {
      best = city;
      bestKm = km;
    }
  }
  return best;
}
