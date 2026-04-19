import 'building_service.dart';

// ── Hardcoded Istanbul safety data ───────────────────────────────────────────
//
// Safe places: real Istanbul hospitals and official assembly points.
// Danger grid: generated from risk zones based on known building age patterns.
//   High risk = pre-1975 dense neighborhoods (Fatih, Zeytinburnu, Bağcılar…)
//   Low risk  = post-2000 developments (Maslak, Başakşehir, Ataşehir new…)

const List<SafePlace> kIstanbulSafePlaces = [
  // ── Hospitals – European side ──────────────────────────────────────────────
  SafePlace(lat: 41.0165, lng: 28.9283, name: 'İstanbul Üniversitesi Çapa Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0119, lng: 28.9311, name: 'Haseki Eğitim ve Araştırma Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0622, lng: 28.9895, name: 'Şişli Etfal Eğitim ve Araştırma Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0498, lng: 28.9864, name: 'Okmeydanı Eğitim ve Araştırma Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0325, lng: 28.9503, name: 'Bakırköy Ruh ve Sinir Hastalıkları Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 40.9831, lng: 28.8720, name: 'Bakırköy Dr Sadi Konuk Eğitim Araştırma Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 40.9978, lng: 28.8944, name: 'İstanbul Eğitim ve Araştırma Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0445, lng: 28.9168, name: 'Bağcılar Eğitim ve Araştırma Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0728, lng: 28.9212, name: 'Gaziosmanpaşa Eğitim ve Araştırma Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0585, lng: 28.8912, name: 'Esenler Eğitim ve Araştırma Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0091, lng: 28.8622, name: 'Bahçelievler Devlet Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0833, lng: 29.0013, name: 'Sarıyer İsmail Akgün Devlet Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.1062, lng: 29.0285, name: 'Şişli Florence Nightingale Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0682, lng: 28.9995, name: 'American Hospital Istanbul', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0418, lng: 28.9906, name: 'Memorial Şişli Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0485, lng: 28.9562, name: 'Eyüpsultan Devlet Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0195, lng: 28.8720, name: 'Ağaoğlu Hastanesi Güneşli', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0620, lng: 28.7928, name: 'Büyükçekmece Devlet Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0008, lng: 28.7268, name: 'Beylikdüzü Devlet Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0288, lng: 28.7485, name: 'Esenyurt Devlet Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0558, lng: 28.7588, name: 'Başakşehir Şehir Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 40.9892, lng: 28.7135, name: 'Avcılar Devlet Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 40.9783, lng: 28.7888, name: 'Küçükçekmece Devlet Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0052, lng: 28.9538, name: 'Cerrahpaşa Tıp Fakültesi Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0288, lng: 28.9765, name: 'Taksim Eğitim ve Araştırma Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0412, lng: 28.9842, name: 'Kasımpaşa Asker Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0695, lng: 28.9568, name: 'Kâğıthane Devlet Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0935, lng: 28.9768, name: 'Eyüp Devlet Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0478, lng: 29.0168, name: 'Medical Park Florya Hastanesi', type: SafePlaceType.hospital),
  // ── Hospitals – Anatolian side ─────────────────────────────────────────────
  SafePlace(lat: 40.9908, lng: 29.0335, name: 'Kadıköy Şifa Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 40.9789, lng: 29.0672, name: 'Göztepe Eğitim ve Araştırma Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 40.9978, lng: 29.0571, name: 'Marmara Üniversitesi Pendik Eğitim Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0025, lng: 29.0628, name: 'Fatih Sultan Mehmet Eğitim Araştırma Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0228, lng: 29.0912, name: 'Ümraniye Eğitim ve Araştırma Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0582, lng: 29.0958, name: 'Beykoz Devlet Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 40.9350, lng: 29.1358, name: 'Maltepe Üniversitesi Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 40.9019, lng: 29.1778, name: 'Kartal Eğitim ve Araştırma Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 40.8978, lng: 29.1932, name: 'Kartal Devlet Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 40.8729, lng: 29.2245, name: 'Pendik Eğitim ve Araştırma Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 40.8562, lng: 29.2778, name: 'Tuzla Devlet Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 40.9562, lng: 29.1012, name: 'Sultanbeyli Devlet Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 40.9748, lng: 29.1528, name: 'Sancaktepe Devlet Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 40.9948, lng: 29.1895, name: 'Çekmeköy Devlet Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0128, lng: 29.1385, name: 'Taşdelen Devlet Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 40.9418, lng: 29.0568, name: 'Bostancı Özel Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 40.9628, lng: 29.0825, name: 'Acıbadem Kadıköy Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0068, lng: 29.0318, name: 'Haydarpaşa Numune Eğitim Araştırma Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 40.9785, lng: 29.0128, name: 'Üsküdar Devlet Hastanesi', type: SafePlaceType.hospital),
  SafePlace(lat: 41.0298, lng: 29.0628, name: 'Beykoz Şehit Kamil Devlet Hastanesi', type: SafePlaceType.hospital),

  // ── Assembly points (Toplanma Alanları) ────────────────────────────────────
  SafePlace(lat: 41.0082, lng: 28.9784, name: 'Taksim Meydanı Toplanma Alanı', type: SafePlaceType.assembly),
  SafePlace(lat: 41.0195, lng: 28.9348, name: 'Topkapı Demirkapı Parkı Toplanma Alanı', type: SafePlaceType.assembly),
  SafePlace(lat: 41.0588, lng: 28.9975, name: 'Yıldız Parkı Toplanma Alanı', type: SafePlaceType.assembly),
  SafePlace(lat: 41.0062, lng: 29.0158, name: 'Fenerbahçe Parkı Toplanma Alanı', type: SafePlaceType.assembly),
  SafePlace(lat: 40.9828, lng: 29.0718, name: 'Bostancı Sahil Parkı Toplanma Alanı', type: SafePlaceType.assembly),
  SafePlace(lat: 40.9922, lng: 29.0288, name: 'Kadıköy Meydanı Toplanma Alanı', type: SafePlaceType.assembly),
  SafePlace(lat: 41.0448, lng: 29.0092, name: 'Beşiktaş Meydanı Toplanma Alanı', type: SafePlaceType.assembly),
  SafePlace(lat: 41.0128, lng: 28.8985, name: 'Zeytinburnu Sahil Parkı Toplanma Alanı', type: SafePlaceType.assembly),
  SafePlace(lat: 40.9795, lng: 28.8512, name: 'Bakırköy Özgürlük Meydanı', type: SafePlaceType.assembly),
  SafePlace(lat: 41.0582, lng: 28.9268, name: 'Bağcılar Meydanı Parkı Toplanma Alanı', type: SafePlaceType.assembly),
  SafePlace(lat: 41.0738, lng: 28.9158, name: 'Gaziosmanpaşa Meydan Parkı', type: SafePlaceType.assembly),
  SafePlace(lat: 40.9985, lng: 28.7258, name: 'Avcılar Sahil Parkı Toplanma Alanı', type: SafePlaceType.assembly),
  SafePlace(lat: 41.0558, lng: 28.7628, name: 'Başakşehir Millet Bahçesi', type: SafePlaceType.assembly),
  SafePlace(lat: 41.0018, lng: 28.7485, name: 'Beylikdüzü Yaşam Vadisi', type: SafePlaceType.assembly),
  SafePlace(lat: 41.0412, lng: 29.1012, name: 'Beykoz Merkez Parkı Toplanma Alanı', type: SafePlaceType.assembly),
  SafePlace(lat: 40.9028, lng: 29.1748, name: 'Kartal Sahil Parkı Toplanma Alanı', type: SafePlaceType.assembly),
  SafePlace(lat: 40.8748, lng: 29.2178, name: 'Pendik Sahil Toplanma Alanı', type: SafePlaceType.assembly),
  SafePlace(lat: 41.0248, lng: 29.0912, name: 'Ümraniye Meydan Parkı Toplanma Alanı', type: SafePlaceType.assembly),
  SafePlace(lat: 40.9628, lng: 29.0148, name: 'Üsküdar Meydanı Toplanma Alanı', type: SafePlaceType.assembly),
  SafePlace(lat: 41.0862, lng: 29.0512, name: 'Sarıyer Sahil Parkı Toplanma Alanı', type: SafePlaceType.assembly),
  SafePlace(lat: 41.0995, lng: 28.9948, name: 'Kâğıthane Millet Bahçesi Toplanma Alanı', type: SafePlaceType.assembly),
  SafePlace(lat: 40.9348, lng: 29.1298, name: 'Maltepe Sahil Toplanma Alanı', type: SafePlaceType.assembly),
  SafePlace(lat: 40.9778, lng: 28.7928, name: 'Küçükçekmece Göl Parkı Toplanma Alanı', type: SafePlaceType.assembly),
  SafePlace(lat: 41.0688, lng: 28.7958, name: 'Büyükçekmece Sahil Toplanma Alanı', type: SafePlaceType.assembly),
  SafePlace(lat: 40.8562, lng: 29.2748, name: 'Tuzla Sahil Parkı Toplanma Alanı', type: SafePlaceType.assembly),
];

// ── Risk zones: (minLat, minLng, maxLat, maxLng, risk) ───────────────────────
//
// Risk levels based on Istanbul's known neighborhood building ages:
//   ≥0.75 = pre-1975 dense residential (Fatih, Zeytinburnu, Bağcılar…)
//   0.50  = mixed 1975-1999 construction
//   ≤0.30 = post-2000 planned developments

const _riskZones = <(double, double, double, double, double)>[
  // ── Very high risk (pre-1975, dense, tall) ────────────────────────────────
  (41.005, 28.920, 41.030, 28.975, 0.92), // Fatih historic core
  (41.028, 28.940, 41.048, 28.968, 0.88), // Balat – Fener
  (40.990, 28.885, 41.012, 28.920, 0.90), // Zeytinburnu
  (41.030, 28.895, 41.060, 28.932, 0.85), // Bayrampaşa
  (41.040, 28.855, 41.078, 28.905, 0.82), // Esenler old
  (41.055, 28.895, 41.088, 28.935, 0.80), // Gaziosmanpaşa
  (41.000, 28.848, 41.025, 28.892, 0.82), // Güngören
  (41.025, 28.840, 41.065, 28.860, 0.78), // Bağcılar north
  (41.038, 28.860, 41.068, 28.898, 0.80), // Bağcılar south
  (41.068, 28.838, 41.105, 28.900, 0.78), // Sultangazi
  (41.030, 28.968, 41.045, 28.992, 0.75), // Tarlabaşı – Dolapdere
  (40.998, 28.918, 41.010, 28.950, 0.78), // Aksaray – Laleli
  (41.012, 28.948, 41.030, 28.970, 0.80), // Sultanahmet periphery
  // ── High risk (1975-1999, moderate density) ───────────────────────────────
  (41.042, 28.928, 41.072, 28.958, 0.70), // Kâğıthane
  (40.978, 29.060, 41.010, 29.095, 0.68), // Kadıköy center
  (41.012, 29.085, 41.050, 29.130, 0.72), // Ümraniye old
  (40.895, 29.168, 40.930, 29.210, 0.70), // Kartal old
  (40.922, 29.130, 40.960, 29.178, 0.68), // Maltepe old
  (40.960, 29.095, 40.998, 29.142, 0.65), // Sultanbeyli
  (41.050, 29.048, 41.082, 29.098, 0.68), // Beykoz old
  (40.975, 28.808, 41.002, 28.848, 0.65), // Küçükçekmece
  (40.978, 28.695, 41.008, 28.748, 0.62), // Avcılar inner
  (41.020, 28.720, 41.055, 28.765, 0.60), // Esenyurt old
  (41.008, 28.758, 41.042, 28.808, 0.62), // Bağcılar west
  (41.070, 28.908, 41.100, 28.945, 0.65), // Gaziosmanpaşa north
  (40.858, 29.188, 40.888, 29.235, 0.62), // Pendik old
  (40.838, 29.268, 40.865, 29.298, 0.58), // Tuzla old
  // ── Medium risk (mixed era) ───────────────────────────────────────────────
  (41.042, 29.008, 41.075, 29.048, 0.50), // Beşiktaş inner
  (40.995, 28.968, 41.015, 29.005, 0.48), // Üsküdar
  (40.862, 28.830, 40.895, 28.872, 0.50), // Bakırköy east
  (41.078, 28.958, 41.105, 28.998, 0.52), // Eyüp
  (41.015, 29.038, 41.042, 29.075, 0.48), // Ataşehir old
  // ── Low risk (post-2000 planned) ─────────────────────────────────────────
  (41.082, 28.985, 41.165, 29.075, 0.18), // Maslak – 4.Levent – Sarıyer new
  (41.048, 28.688, 41.115, 28.808, 0.18), // Başakşehir
  (40.978, 28.608, 41.022, 28.698, 0.20), // Beylikdüzü
  (41.020, 28.680, 41.058, 28.745, 0.22), // Esenyurt new
  (40.978, 29.098, 41.025, 29.165, 0.22), // Ataşehir new – Sancaktepe
  (40.998, 29.148, 41.035, 29.215, 0.25), // Çekmeköy – Taşdelen
  (41.040, 28.778, 41.072, 28.838, 0.25), // Başakşehir south
];

// ── Grid generator ────────────────────────────────────────────────────────────

List<DangerCell> buildIstanbulDangerGrid() {
  // Istanbul bounding box — same as tile download area
  const minLat = 40.80, maxLat = 41.35;
  const minLng = 28.45, maxLng = 29.55;

  final cells = <DangerCell>[];

  double lat = minLat;
  while (lat < maxLat) {
    double lng = minLng;
    while (lng < maxLng) {
      final risk = _cellRisk(lat, lng);
      if (risk > 0.30) {
        cells.add(DangerCell(lat: lat, lng: lng, risk: risk));
      }
      lng += cellDeg;
    }
    lat += cellDeg;
  }

  return cells;
}

double _cellRisk(double cellLat, double cellLng) {
  // Cell centre
  final cLat = cellLat + cellDeg / 2;
  final cLng = cellLng + cellDeg / 2;

  double best = 0.0;
  for (final z in _riskZones) {
    if (cLat >= z.$1 && cLat <= z.$3 && cLng >= z.$2 && cLng <= z.$4) {
      if (z.$5 > best) best = z.$5;
    }
  }
  // Default for unclassified Istanbul urban area: moderate risk
  if (best == 0.0 && _isIstanbulUrban(cLat, cLng)) best = 0.45;
  return best;
}

bool _isIstanbulUrban(double lat, double lng) {
  // Rough urban boundary — excludes sea, forests, and rural fringe
  if (lat < 40.87 || lat > 41.22) return false;
  if (lng < 28.58 || lng > 29.38) return false;
  // Exclude Bosphorus / sea areas (very rough check)
  if (lng > 28.95 && lng < 29.05 && lat > 41.02 && lat < 41.08) return false;
  return true;
}
