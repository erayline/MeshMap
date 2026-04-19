import 'dart:math' as math;

import 'istanbul_data.dart';

// ── Public constant used by map layer for cell polygon corners ───────────────
const double cellDeg = 0.003; // ≈ 250 m per cell at Istanbul's latitude

// ── Models ───────────────────────────────────────────────────────────────────

class DangerCell {
  final double lat, lng; // bottom-left corner of the cell
  final double risk;     // 0.0 – 1.0

  const DangerCell({required this.lat, required this.lng, required this.risk});

  factory DangerCell.fromJson(Map<String, dynamic> j) => DangerCell(
        lat: (j['la'] as num).toDouble(),
        lng: (j['ln'] as num).toDouble(),
        risk: (j['r'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'la': lat, 'ln': lng, 'r': risk};
}

enum SafePlaceType { assembly, hospital }

class SafePlace {
  final double lat, lng;
  final String name;
  final SafePlaceType type;

  const SafePlace({
    required this.lat,
    required this.lng,
    required this.name,
    required this.type,
  });

  factory SafePlace.fromJson(Map<String, dynamic> j) => SafePlace(
        lat: (j['la'] as num).toDouble(),
        lng: (j['ln'] as num).toDouble(),
        name: j['nm'] as String,
        type: SafePlaceType.values.byName(j['tp'] as String),
      );

  Map<String, dynamic> toJson() =>
      {'la': lat, 'ln': lng, 'nm': name, 'tp': type.name};

  // Haversine distance in metres.
  double distanceTo(double fromLat, double fromLng) {
    const r = 6371000.0;
    final dLat = (lat - fromLat) * math.pi / 180;
    final dLng = (lng - fromLng) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(fromLat * math.pi / 180) *
            math.cos(lat * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}


// ── Hardcoded data (no download needed) ──────────────────────────────────────
//
// Safe places and danger grid are bundled in istanbul_data.dart.
// isSafetyDataDownloaded always returns true — data is always available.

Future<bool> isSafetyDataDownloaded() async => true;

Future<List<DangerCell>> loadDangerGrid() async =>
    buildIstanbulDangerGrid();

Future<List<SafePlace>> loadSafePlaces() async =>
    kIstanbulSafePlaces;

