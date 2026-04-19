import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Bump this whenever the query or graph format changes.
// map_screen shows the download button if stored version != this.
const routingDataVersion = 'v4_geom';

enum RouteMode { walking, car }

// ── Highway type codes stored on every edge ───────────────────────────────────
// 0  footway | pedestrian | path | steps        (foot-only)
// 1  living_street | service | cycleway         (shared slow)
// 2  residential                                (neighbourhood)
// 3  tertiary | unclassified                    (general)
// 4  secondary | primary                        (main road)
// 5  trunk | motorway                           (highway)

int _typeCode(String hw) => switch (hw) {
      'footway' || 'pedestrian' || 'path' || 'steps' => 0,
      'living_street' || 'service' || 'cycleway' => 1,
      'residential' => 2,
      'tertiary' || 'unclassified' => 3,
      'secondary' || 'primary' => 4,
      'trunk' || 'motorway' => 5,
      _ => 3,
    };

bool _edgeAllowed(int typeCode, RouteMode mode) {
  if (mode == RouteMode.walking) return typeCode <= 4; // skip motorway/trunk
  return typeCode >= 2; // skip foot-only & shared-slow for cars
}

// Cost multiplier per type per mode (lower = preferred)
double _edgeCost(double distM, int typeCode, RouteMode mode) {
  if (mode == RouteMode.walking) {
    const m = [0.8, 0.9, 1.0, 1.0, 1.2, 99999.0];
    return distM * m[typeCode.clamp(0, 5)];
  } else {
    const m = [99999.0, 99999.0, 1.2, 1.0, 0.85, 0.75];
    return distM * m[typeCode.clamp(0, 5)];
  }
}

// ── Graph node ────────────────────────────────────────────────────────────────

class _Node {
  final String id;
  final double lat, lng;
  // (neighborId, typeCode)
  final List<(String, int)> edges = [];

  _Node(this.id, this.lat, this.lng);

  double distTo(double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat - lat2) * math.pi / 180;
    final dLng = (lng - lng2) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}

// Priority queue entry for A*
class _PQEntry implements Comparable<_PQEntry> {
  final String id;
  final double f;
  const _PQEntry(this.id, this.f);
  @override
  int compareTo(_PQEntry other) => f.compareTo(other.f);
}

// ── Service ───────────────────────────────────────────────────────────────────

class RoutingService {
  static final RoutingService _instance = RoutingService._internal();
  factory RoutingService() => _instance;
  RoutingService._internal();

  final Map<String, _Node> _nodes = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;
  int get nodeCount => _nodes.length;

  // ── Initialization ───────────────────────────────────────────────────────

  Future<void> init() async {
    if (await isRoutingDataDownloaded()) await _load();
  }

  Future<bool> isRoutingDataDownloaded() async {
    final prefs = await SharedPreferences.getInstance();
    final ok = prefs.getBool('routing_data_ok') ?? false;
    final version = prefs.getString('routing_data_version') ?? '';
    return ok && version == routingDataVersion;
  }

  Future<void> _load() async {
    final f = File('${await _dir()}/routing_graph.json');
    if (!f.existsSync()) return;
    try {
      final data = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final nodeMap = data['nodes'] as Map<String, dynamic>;
      final edgeMap = data['edges'] as Map<String, dynamic>;

      _nodes.clear();
      for (final e in nodeMap.entries) {
        final pos = e.value as List;
        _nodes[e.key] = _Node(e.key, (pos[0] as num).toDouble(), (pos[1] as num).toDouble());
      }

      for (final e in edgeMap.entries) {
        final node = _nodes[e.key];
        if (node == null) continue;
        for (final item in (e.value as List)) {
          if (item is List && item.length == 2) {
            // v3 format: [neighborId, typeCode]
            node.edges.add((item[0] as String, (item[1] as num).toInt()));
          } else if (item is String) {
            // v1/v2 legacy fallback
            node.edges.add((item, 3));
          }
        }
      }
      _loaded = true;
    } catch (_) {}
  }

  Future<String> _dir() async =>
      (await getApplicationDocumentsDirectory()).path;

  // ── Download ─────────────────────────────────────────────────────────────

  // Stable node key from coordinates (5 decimal places ≈ 1 m resolution).
  // Two ways meeting at the same physical point get the same key → proper intersections.
  static String _coordKey(double lat, double lng) =>
      '${(lat * 100000).round()}_${(lng * 100000).round()}';

  Future<String?> downloadRoutingData(void Function(String) onStatus) async {
    try {
      onStatus('Fetching Istanbul road network [0%]…');
      final ways = await _fetchWays(onStatus);
      if (ways.isEmpty) return 'No road data returned by server.';

      final total = ways.length;
      onStatus('Building graph from $total roads [0%]…');

      // Pass 1: collect all node coords from geometry (no reliance on 'nodes' array)
      final nodeCoords = <String, List<double>>{};
      for (int i = 0; i < total; i++) {
        final way = ways[i];
        final geometry = (way['geometry'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        for (final pt in geometry) {
          final lat = (pt['lat'] as num).toDouble();
          final lon = (pt['lon'] as num).toDouble();
          nodeCoords[_coordKey(lat, lon)] = [lat, lon];
        }
        if (i % 500 == 0) {
          onStatus('Building graph from $total roads [${(i / total * 40).round()}%]…');
        }
      }

      if (nodeCoords.isEmpty) return 'No geometry in server response — try again.';

      // Pass 2: create nodes
      _nodes.clear();
      for (final e in nodeCoords.entries) {
        _nodes[e.key] = _Node(e.key, e.value[0], e.value[1]);
      }

      // Pass 3: build typed edges using coord-based keys
      // Map<nodeId, Map<neighborId, typeCode>> — Map deduplicates parallel edges
      final edges = <String, Map<String, int>>{};
      for (int i = 0; i < total; i++) {
        final way = ways[i];
        final hw = (way['tags'] as Map<String, dynamic>?)?['highway'] as String? ?? '';
        final tc = _typeCode(hw);
        final geometry = (way['geometry'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final nodeIds = geometry.map((pt) =>
            _coordKey((pt['lat'] as num).toDouble(), (pt['lon'] as num).toDouble())).toList();
        for (int j = 1; j < nodeIds.length; j++) {
          final a = nodeIds[j - 1], b = nodeIds[j];
          if (a != b && _nodes.containsKey(a) && _nodes.containsKey(b)) {
            edges.putIfAbsent(a, () => {})[b] = tc;
            edges.putIfAbsent(b, () => {})[a] = tc;
          }
        }
        if (i % 500 == 0) {
          onStatus('Building graph from $total roads [${(40 + i / total * 40).round()}%]…');
        }
      }

      // Write typed edges into nodes
      for (final e in edges.entries) {
        for (final ne in e.value.entries) {
          _nodes[e.key]?.edges.add((ne.key, ne.value));
        }
      }

      onStatus('Saving to disk [80%]…');
      final dir = await _dir();
      final graph = {
        'v': routingDataVersion,
        'nodes': _nodes.map((id, n) => MapEntry(id, [n.lat, n.lng])),
        'edges': edges.map(
          (id, neighbors) => MapEntry(
            id,
            neighbors.entries.map((e) => [e.key, e.value]).toList(),
          ),
        ),
      };
      await File('$dir/routing_graph.json').writeAsString(jsonEncode(graph));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('routing_data_ok', true);
      await prefs.setString('routing_data_version', routingDataVersion);
      _loaded = true;
      onStatus('Done ✓ — ${_nodes.length} nodes, ${edges.length} connections.');
      return null;
    } catch (e) {
      return 'Routing download failed: $e';
    }
  }

  // ── Pathfinding (A* with mode-aware cost) ─────────────────────────────────

  List<List<double>> findRoute(
    double startLat,
    double startLng,
    double endLat,
    double endLng, {
    List<(double, double)> dangerPoints = const [],
    List<(double, double)> blockedPoints = const [],
    RouteMode mode = RouteMode.walking,
  }) {
    if (!_loaded || _nodes.isEmpty) return [];

    final startNode = _nearestNode(startLat, startLng, mode);
    final endNode = _nearestNode(endLat, endLng, mode);
    if (startNode == null || endNode == null) return [];

    final gScore = <String, double>{startNode.id: 0};
    final cameFrom = <String, String>{};
    final closed = <String>{};

    final open = SplayTreeSet<_PQEntry>((a, b) {
      final c = a.f.compareTo(b.f);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    open.add(_PQEntry(startNode.id, startNode.distTo(endLat, endLng)));

    while (open.isNotEmpty) {
      final cur = open.first;
      open.remove(cur);

      if (cur.id == endNode.id) return _reconstructPath(cameFrom, cur.id);
      if (closed.contains(cur.id)) continue;
      closed.add(cur.id);

      final curNode = _nodes[cur.id]!;
      final curG = gScore[cur.id]!;

      for (final (neighborId, typeCode) in curNode.edges) {
        if (!_edgeAllowed(typeCode, mode)) continue;
        if (closed.contains(neighborId)) continue;
        final neighbor = _nodes[neighborId];
        if (neighbor == null) continue;

        double moveCost = _edgeCost(
          curNode.distTo(neighbor.lat, neighbor.lng),
          typeCode,
          mode,
        );

        // Danger penalty: +50 000 m if within 200 m of a damage marker
        for (final (dLat, dLng) in dangerPoints) {
          if (neighbor.distTo(dLat, dLng) < 200) {
            moveCost += 50000;
            break;
          }
        }
        // Block penalty: +2 000 000 m within 50 m (effectively impassable)
        for (final (bLat, bLng) in blockedPoints) {
          if (neighbor.distTo(bLat, bLng) < 50) {
            moveCost += 2000000;
            break;
          }
        }

        final tentativeG = curG + moveCost;
        if (tentativeG < (gScore[neighborId] ?? double.infinity)) {
          gScore[neighborId] = tentativeG;
          cameFrom[neighborId] = cur.id;
          open.add(_PQEntry(
            neighborId,
            tentativeG + neighbor.distTo(endLat, endLng),
          ));
        }
      }
    }

    return [];
  }

  _Node? _nearestNode(double lat, double lng, RouteMode mode) {
    _Node? nearest;
    double minDist = double.infinity;
    for (final node in _nodes.values) {
      // Only snap to nodes that have at least one allowed edge for this mode
      if (!node.edges.any((e) => _edgeAllowed(e.$2, mode))) continue;
      final d = node.distTo(lat, lng);
      if (d < minDist) { minDist = d; nearest = node; }
    }
    return minDist < 2000 ? nearest : null;
  }

  List<List<double>> _reconstructPath(Map<String, String> cameFrom, String end) {
    final path = <List<double>>[];
    String? cur = end;
    while (cur != null) {
      final node = _nodes[cur]!;
      path.add([node.lat, node.lng]);
      cur = cameFrom[cur];
    }
    return path.reversed.toList();
  }

  // ── Overpass ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _fetchWays(void Function(String) onStatus) async {
    const mirrors = [
      'https://overpass-api.de/api/interpreter',
      'https://overpass.kumi.systems/api/interpreter',
      'https://lz4.overpass-api.de/api/interpreter',
      'https://z.overpass-api.de/api/interpreter',
      'https://overpass.openstreetmap.ru/api/interpreter',
    ];

    // ── DEBUG: single Kadıköy bbox for emulator testing (low memory) ──────────
    // For production, replace with the full 9-tile Istanbul grid below.
    const bboxes = ['40.960,29.000,41.020,29.060'];
    // Full Istanbul (9 tiles — needs 4 GB+ RAM on emulator):
    // final lats = [40.80, 40.98, 41.16, 41.35];
    // final lons = [28.45, 28.82, 29.18, 29.55];
    // final bboxes = <String>[];
    // for (int r = 0; r < 3; r++) {
    //   for (int c = 0; c < 3; c++) {
    //     bboxes.add('${lats[r]},${lons[c]},${lats[r + 1]},${lons[c + 1]}');
    //   }
    // }
    // ─────────────────────────────────────────────────────────────────────────

    final result = <Map<String, dynamic>>[];

    for (int qi = 0; qi < bboxes.length; qi++) {
      onStatus('Downloading roads part ${qi + 1}/${bboxes.length} [${(qi / bboxes.length * 40).round()}%]…');

      // Walking + car combined query — tags included so we can store typeCode
      final q = '[out:json][timeout:90][bbox:${bboxes[qi]}];'
          r'(way["highway"~"^(footway|pedestrian|path|steps|living_street|'
          r'service|residential|tertiary|unclassified|secondary|primary|trunk|motorway)$"];);'
          'out body geom tags;';

      Exception? lastError;
      bool success = false;

      outer:
      for (final url in mirrors) {
        for (int attempt = 1; attempt <= 2; attempt++) {
          final client = HttpClient();
          try {
            final req = await client
                .postUrl(Uri.parse(url))
                .timeout(const Duration(seconds: 110));
            req.headers.set('Content-Type', 'application/x-www-form-urlencoded');
            req.headers.set('User-Agent', 'meshapp/1.0');
            req.write('data=${Uri.encodeComponent(q)}');
            final res = await req.close().timeout(const Duration(seconds: 110));
            final bytes = await res.fold<List<int>>([], (b, c) => b..addAll(c));
            if (res.statusCode == 200) {
              final body = utf8.decode(bytes);
              if (!body.trimLeft().startsWith('{')) {
                lastError = Exception('$url returned non-JSON');
                break;
              }
              final data = jsonDecode(body) as Map<String, dynamic>;
              result.addAll(
                  (data['elements'] as List?)?.cast<Map<String, dynamic>>() ?? []);
              success = true;
              break outer;
            }
            lastError = Exception('HTTP ${res.statusCode} from $url');
            if (res.statusCode != 504) break;
            if (attempt < 2) await Future.delayed(const Duration(seconds: 5));
          } catch (e) {
            lastError = Exception('$url attempt $attempt: $e');
            if (attempt < 2) await Future.delayed(const Duration(seconds: 3));
          } finally {
            client.close();
          }
        }
        if (success) break;
      }
      if (!success) throw lastError!;
    }

    return result;
  }
}
