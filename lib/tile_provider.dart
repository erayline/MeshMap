import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineTileProvider extends TileProvider {
  final String cacheDir;
  OfflineTileProvider(this.cacheDir);

  @override
  ImageProvider<Object> getImage(TileCoordinates coordinates, TileLayer options) {
    final file = File('$cacheDir/${coordinates.z}/${coordinates.x}/${coordinates.y}.png');
    if (file.existsSync()) return FileImage(file);
    return NetworkImage(
      'https://tile.openstreetmap.org/${coordinates.z}/${coordinates.x}/${coordinates.y}.png',
      headers: const {'User-Agent': 'meshapp-prototype/1.0'},
    );
  }
}

Future<String> getTileCacheDir() async {
  final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/tiles');
  await dir.create(recursive: true);
  return dir.path;
}

// Persisted flag — survives screen close/reopen.
const _tilesVersion = 'v2_kadikoy';

Future<bool> isIstanbulDownloaded() async {
  final prefs = await SharedPreferences.getInstance();
  final ok = prefs.getBool('istanbul_tiles_ok') ?? false;
  final ver = prefs.getString('istanbul_tiles_version') ?? '';
  return ok && ver == _tilesVersion;
}

Future<void> _markIstanbulDownloaded() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('istanbul_tiles_ok', true);
  await prefs.setString('istanbul_tiles_version', _tilesVersion);
}

// ── DEBUG: Kadıköy-only bbox for emulator testing ─────────────────────────
// Full Istanbul: minLat=40.80 maxLat=41.35 minLon=28.45 maxLon=29.55 zoom 10-14
const _minLat = 40.960, _maxLat = 41.020;
const _minLon = 29.000, _maxLon = 29.060;
const _minZoom = 10, _maxZoom = 15;

int _lonToX(double lon, int z) => ((lon + 180) / 360 * (1 << z)).floor();
int _latToY(double lat, int z) {
  final r = lat * math.pi / 180;
  return ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * (1 << z)).floor();
}

List<(int, int, int)> _istanbulTiles() {
  final tiles = <(int, int, int)>[];
  for (int z = _minZoom; z <= _maxZoom; z++) {
    for (int x = _lonToX(_minLon, z); x <= _lonToX(_maxLon, z); x++) {
      for (int y = _latToY(_maxLat, z); y <= _latToY(_minLat, z); y++) {
        tiles.add((z, x, y));
      }
    }
  }
  return tiles;
}

/// Test download of a single central Istanbul tile to verify connectivity & permissions.
/// Returns HTTP status code (200 = success) or -1 if file I/O failed.
Future<int> testDownloadOneTile(String cacheDir) async {
  try {
    final z = 12;
    final x = _lonToX(29.0, z);
    final y = _latToY(41.0, z);
    final file = File('$cacheDir/$z/$x/$y.png');

    final client = HttpClient()..userAgent = 'meshapp-prototype/1.0';
    try {
      final req = await client
          .getUrl(Uri.parse('https://tile.openstreetmap.org/$z/$x/$y.png'))
          .timeout(const Duration(seconds: 15));
      final res = await req.close().timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        await file.parent.create(recursive: true);
        final bytes = await res.fold<List<int>>([], (b, c) => b..addAll(c));
        await file.writeAsBytes(bytes);
        return 200;
      }
      return res.statusCode;
    } finally {
      client.close();
    }
  } catch (e) {
    return -1; // I/O or network error
  }
}

/// Returns number of tiles actually written to disk.
/// Caller should check this > 0 before treating download as successful.
Future<int> downloadIstanbul(
  String cacheDir,
  void Function(double progress, int total) onProgress,
) async {
  final tiles = _istanbulTiles();
  final client = HttpClient()..userAgent = 'meshapp-prototype/1.0';
  int written = 0;

  try {
    for (int i = 0; i < tiles.length; i++) {
      final (z, x, y) = tiles[i];
      final file = File('$cacheDir/$z/$x/$y.png');

      if (file.existsSync()) {
        written++; // Already on disk — counts as success.
      } else {
        try {
          final req = await client
              .getUrl(Uri.parse('https://tile.openstreetmap.org/$z/$x/$y.png'))
              .timeout(const Duration(seconds: 10));
          final res = await req.close().timeout(const Duration(seconds: 10));
          if (res.statusCode == 200) {
            await file.parent.create(recursive: true);
            final bytes = await res.fold<List<int>>([], (b, c) => b..addAll(c));
            await file.writeAsBytes(bytes);
            written++;
          }
          await Future.delayed(const Duration(milliseconds: 80));
        } catch (_) {
          // Skip failed tile — network unavailable or server error.
        }
      }

      onProgress((i + 1) / tiles.length, tiles.length);
    }
  } finally {
    client.close();
  }

  // Persist success only when most tiles are on disk (>80% threshold).
  if (written >= tiles.length * 0.8) {
    await _markIstanbulDownloaded();
  }

  return written;
}
