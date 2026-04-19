import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'grid_map_screen.dart';
import 'mesh_service.dart';
import 'routing_service.dart';
import 'tile_provider.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapController = MapController();
  final _mesh = MeshService();

  // ── Tiles ──────────────────────────────────────────────────────────────────
  String? _cacheDir;
  bool _offline = false;
  bool _downloading = false;
  double _dlProgress = 0;
  int _dlTotal = 0;
  int _tileLayerVersion = 0;
  String? _dlError;

  // ── Location / peers ───────────────────────────────────────────────────────
  LatLng? _myPos;
  String _myStatus = 'safe';
  final Map<String, ({double lat, double lng, String status, int ts})> _peers =
      {};

  // ── Report markers ─────────────────────────────────────────────────────────
  final Map<String, ({double lat, double lng, String note, int ts})> _damages =
      {};
  final Map<String, ({double lat, double lng, String note, int ts})>
  _sosMarkers = {};
  final Map<String, ({double lat, double lng, String note, int ts})>
  _roadBlocks = {};
  final Map<
    String,
    ({double lat, double lng, String resType, String note, int ts})
  >
  _resources = {};
  final Map<String, ({double lat, double lng, String note, int ts})>
  _safeZones = {};

  StreamSubscription<MeshPacket>? _packetSub;

  // ── Route ──────────────────────────────────────────────────────────────────
  LatLng? _destination;
  List<LatLng> _safeRoute = [];
  double? _routeDistanceM;
  bool _routingLoading = false;
  RouteMode _routeMode = RouteMode.walking;

  // ── Downloads ──────────────────────────────────────────────────────────────
  bool _downloadingRouting = false;
  String _routingStatus = '';

  static const _istanbul = LatLng(41.0082, 28.9784);
  static const _staleness = Duration(minutes: 10);

  // ── Init ───────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _cacheDir = await getTileCacheDir();
    if (mounted) setState(() => _offline = false);
    isIstanbulDownloaded().then((ok) {
      if (mounted) setState(() => _offline = ok);
    });

    // Pre-populate peers
    for (final e in _mesh.latestLocations.entries) {
      if (e.key == _mesh.deviceId) continue;
      try {
        final d = jsonDecode(e.value.payload) as Map<String, dynamic>;
        _peers[e.key] = (
          lat: (d['lat'] as num).toDouble(),
          lng: (d['lng'] as num).toDouble(),
          status: (d['status'] as String?) ?? 'unknown',
          ts: e.value.timestamp,
        );
      } catch (_) {}
    }

    // Pre-populate all report types from Hive
    for (final p in _mesh.storedPackets) {
      try {
        final d = jsonDecode(p.payload) as Map<String, dynamic>;
        final lat = (d['lat'] as num).toDouble();
        final lng = (d['lng'] as num).toDouble();
        final note = (d['note'] as String?) ?? '';
        if (p.type == MeshPacket.typeDamage) {
          _damages[p.id] = (lat: lat, lng: lng, note: note, ts: p.timestamp);
        } else if (p.type == MeshPacket.typeSOS) {
          _sosMarkers[p.id] = (lat: lat, lng: lng, note: note, ts: p.timestamp);
        } else if (p.type == MeshPacket.typeRoadBlock) {
          _roadBlocks[p.id] = (lat: lat, lng: lng, note: note, ts: p.timestamp);
        } else if (p.type == MeshPacket.typeResource) {
          _resources[p.id] = (
            lat: lat,
            lng: lng,
            resType: (d['type'] as String?) ?? 'other',
            note: note,
            ts: p.timestamp,
          );
        } else if (p.type == MeshPacket.typeSafeZone) {
          _safeZones[p.id] = (lat: lat, lng: lng, note: note, ts: p.timestamp);
        }
      } catch (_) {}
    }

    _packetSub = _mesh.packetStream.listen(_onPacket);

    // ── DEBUG: hardcoded Kadıköy for emulator testing ─────────────────────
    if (mounted) setState(() => _myPos = const LatLng(40.9900, 29.0233));
  }

  void _onPacket(MeshPacket pkt) {
    if (!mounted) return;
    try {
      final d = jsonDecode(pkt.payload) as Map<String, dynamic>;
      final lat = (d['lat'] as num).toDouble();
      final lng = (d['lng'] as num).toDouble();
      final note = (d['note'] as String?) ?? '';
      setState(() {
        if (pkt.type == MeshPacket.typeLocation) {
          _peers[pkt.senderId] = (
            lat: lat,
            lng: lng,
            status: (d['status'] as String?) ?? 'unknown',
            ts: pkt.timestamp,
          );
        } else if (pkt.type == MeshPacket.typeDamage) {
          _damages[pkt.id] = (
            lat: lat,
            lng: lng,
            note: note,
            ts: pkt.timestamp,
          );
        } else if (pkt.type == MeshPacket.typeSOS) {
          _sosMarkers[pkt.id] = (
            lat: lat,
            lng: lng,
            note: note,
            ts: pkt.timestamp,
          );
        } else if (pkt.type == MeshPacket.typeRoadBlock) {
          _roadBlocks[pkt.id] = (
            lat: lat,
            lng: lng,
            note: note,
            ts: pkt.timestamp,
          );
        } else if (pkt.type == MeshPacket.typeResource) {
          _resources[pkt.id] = (
            lat: lat,
            lng: lng,
            resType: (d['type'] as String?) ?? 'other',
            note: note,
            ts: pkt.timestamp,
          );
        } else if (pkt.type == MeshPacket.typeSafeZone) {
          _safeZones[pkt.id] = (
            lat: lat,
            lng: lng,
            note: note,
            ts: pkt.timestamp,
          );
        }
      });
    } catch (_) {}
  }

  // ── Downloads ──────────────────────────────────────────────────────────────

  Future<void> _downloadRoutingData() async {
    setState(() {
      _downloadingRouting = true;
      _routingStatus = 'Başlıyor…';
    });
    final error = await RoutingService().downloadRoutingData((msg) {
      if (mounted) setState(() => _routingStatus = msg);
    });
    if (!mounted) return;
    setState(() {
      _downloadingRouting = false;
      _routingStatus = error ?? 'Tamamlandı ✓';
    });
  }

  Future<void> _downloadTiles() async {
    setState(() {
      _downloading = true;
      _dlProgress = 0;
      _dlError = null;
    });
    final written = await downloadIstanbul(_cacheDir!, (p, t) {
      if (mounted)
        setState(() {
          _dlProgress = p;
          _dlTotal = t;
        });
    });
    if (!mounted) return;
    if (written == 0) {
      setState(() {
        _downloading = false;
        _dlError = 'No tiles written — check connection.';
      });
    } else {
      setState(() {
        _downloading = false;
        _offline = written >= _dlTotal * 0.8;
        _tileLayerVersion++;
      });
    }
  }

  // ── Marker layers ──────────────────────────────────────────────────────────

  MarkerLayer _peerAndSelfLayer() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final markers = <Marker>[];
    for (final e in _peers.entries) {
      final stale = (now - e.value.ts) > _staleness.inMilliseconds;
      final color = stale
          ? Colors.grey
          : e.value.status == 'safe'
          ? Colors.green
          : e.value.status == 'injured'
          ? Colors.amber
          : Colors.red;
      markers.add(
        Marker(
          point: LatLng(e.value.lat, e.value.lng),
          width: 64,
          height: 52,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on, color: color, size: 28),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  e.key,
                  style: TextStyle(
                    fontSize: 9,
                    color: stale ? Colors.grey.shade400 : Colors.white,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_myPos != null) {
      final dotColor = _myStatus == 'safe'
          ? Colors.blue
          : _myStatus == 'injured'
          ? Colors.amber.shade700
          : Colors.red;
      markers.add(
        Marker(
          point: _myPos!,
          width: 30,
          height: 30,
          child: Container(
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4),
              ],
            ),
            child: Icon(
              _myStatus == 'safe'
                  ? Icons.person
                  : _myStatus == 'injured'
                  ? Icons.personal_injury
                  : Icons.sos,
              color: Colors.white,
              size: 14,
            ),
          ),
        ),
      );
    }
    return MarkerLayer(markers: markers);
  }

  MarkerLayer _damageLayer() => MarkerLayer(
    markers: _damages.entries
        .map(
          (e) => Marker(
            point: LatLng(e.value.lat, e.value.lng),
            width: 150,
            height: 150,
            child: Center(
              // <--- Safe Center Wrapper
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.report, color: Colors.deepOrange, size: 30),
                  if (e.value.note.isNotEmpty) _noteBubble(e.value.note),
                ],
              ),
            ),
          ),
        )
        .toList(),
  );

  MarkerLayer _sosLayer() => MarkerLayer(
    markers: _sosMarkers.entries
        .map(
          (e) => Marker(
            point: LatLng(e.value.lat, e.value.lng),
            width: 150,
            height: 150,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    constraints: const BoxConstraints(
                      maxWidth: 120,
                    ), // <--- STRICT BOUNDARY
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade700,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.5),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sos, color: Colors.white, size: 18),
                        SizedBox(width: 4),
                        // Extirpate the 'Flexible' widget here entirely
                        Text(
                          'YARDIM',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (e.value.note.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    _noteBubble(e.value.note),
                  ],
                ],
              ),
            ),
          ),
        )
        .toList(),
  );

  MarkerLayer _roadBlockLayer() => MarkerLayer(
    markers: _roadBlocks.entries
        .map(
          (e) => Marker(
            point: LatLng(e.value.lat, e.value.lng),
            width: 150,
            height: 150,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF57C00),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.block,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  if (e.value.note.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    _noteBubble(e.value.note),
                  ],
                ],
              ),
            ),
          ),
        )
        .toList(),
  );

  static ({IconData icon, Color color, String label}) _resConf(String type) =>
      switch (type) {
        'water' => (
          icon: Icons.water_drop,
          color: const Color(0xFF1976D2),
          label: 'Su',
        ),
        'food' => (
          icon: Icons.restaurant,
          color: const Color(0xFF388E3C),
          label: 'Yiyecek',
        ),
        'medical' => (
          icon: Icons.medical_services,
          color: const Color(0xFFC62828),
          label: 'Tıbbi',
        ),
        'shelter' => (
          icon: Icons.night_shelter,
          color: const Color(0xFF5D4037),
          label: 'Barınak',
        ),
        _ => (
          icon: Icons.inventory_2,
          color: const Color(0xFF455A64),
          label: 'Kaynak',
        ),
      };

  MarkerLayer _resourceLayer() => MarkerLayer(
    markers: _resources.entries.map((e) {
      final c = _resConf(e.value.resType);
      return Marker(
        point: LatLng(e.value.lat, e.value.lng),
        width: 150,
        height: 150,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: c.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Icon(c.icon, color: Colors.white, size: 18),
              ),
              Container(
                constraints: const BoxConstraints(
                  maxWidth: 80,
                ), // <--- STRICT BOUNDARY
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: c.color.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  c.label,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList(),
  );

  CircleLayer _safeZoneCircleLayer() => CircleLayer(
    circles: _safeZones.values
        .map(
          (z) => CircleMarker(
            point: LatLng(z.lat, z.lng),
            radius: 50,
            useRadiusInMeter: false,
            color: Colors.green.withOpacity(0.12),
            borderColor: Colors.green.withOpacity(0.7),
            borderStrokeWidth: 2,
          ),
        )
        .toList(),
  );

  MarkerLayer _safeZoneMarkerLayer() => MarkerLayer(
    markers: _safeZones.entries
        .map(
          (e) => Marker(
            point: LatLng(e.value.lat, e.value.lng),
            width: 150,
            height: 150,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00796B),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.5),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.verified_user,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  Container(
                    constraints: const BoxConstraints(
                      maxWidth: 100,
                    ), // <--- STRICT BOUNDARY PREVENTS CRASH
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00796B).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      e.value.note.isEmpty ? 'Güvenli Bölge' : e.value.note,
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        )
        .toList(),
  );

  MarkerLayer _destinationLayer() {
    if (_destination == null) return const MarkerLayer(markers: []);
    return MarkerLayer(
      markers: [
        Marker(
          point: _destination!,
          width: 80,
          height: 80,
          child: const Center(
            child: Icon(Icons.location_pin, color: Colors.redAccent, size: 38),
          ),
        ),
      ],
    );
  }

  static Widget _noteBubble(String text) => Container(
    constraints: const BoxConstraints(maxWidth: 80), // <--- STRICT BOUNDARY
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 9, color: Colors.white),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    ),
  );

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _setDestination(LatLng p) => setState(() {
    _destination = p;
    _safeRoute = [];
    _routeDistanceM = null;
  });
  void _clearAll() => setState(() {
    _destination = null;
    _safeRoute = [];
    _routeDistanceM = null;
  });

  ({double lat, double lng, String id})? _closestSafePeer() {
    if (_myPos == null) return null;
    ({double lat, double lng, String id})? best;
    double bestD = double.infinity;
    for (final e in _peers.entries) {
      if (e.value.status != 'safe') continue;
      final d = const Distance().as(
        LengthUnit.Meter,
        _myPos!,
        LatLng(e.value.lat, e.value.lng),
      );
      if (d < bestD) {
        bestD = d;
        best = (lat: e.value.lat, lng: e.value.lng, id: e.key);
      }
    }
    return best;
  }

  ({double lat, double lng})? _closestSafeZone() {
    if (_myPos == null || _safeZones.isEmpty) return null;
    ({double lat, double lng})? best;
    double bestD = double.infinity;
    for (final z in _safeZones.values) {
      final d = const Distance().as(
        LengthUnit.Meter,
        _myPos!,
        LatLng(z.lat, z.lng),
      );
      if (d < bestD) {
        bestD = d;
        best = (lat: z.lat, lng: z.lng);
      }
    }
    return best;
  }

  Future<void> _findEvacuationRoute() async {
    if (_myPos == null) {
      _snackErr('Konumunuz henüz alınamadı.');
      return;
    }

    LatLng? target = _destination;
    if (target == null) {
      final peer = _closestSafePeer();
      if (peer != null) {
        target = LatLng(peer.lat, peer.lng);
      } else {
        final zone = _closestSafeZone();
        if (zone != null) {
          target = LatLng(zone.lat, zone.lng);
        } else {
          _snackErr(
            'Haritaya hedef pin koy (dokun) ya da güvenli bir peer/bölge bekle.',
          );
          return;
        }
      }
    }

    final routing = RoutingService();
    if (!routing.isLoaded) {
      _snackErr(
        'Yol verisi yüklenmemiş — önce "Yol Verisini İndir" butonuna bas.',
      );
      return;
    }

    setState(() {
      _routingLoading = true;
      _safeRoute = [];
      _routeDistanceM = null;
    });

    final dangerPts = _damages.values.map((d) => (d.lat, d.lng)).toList();
    final blockedPts = _roadBlocks.values.map((d) => (d.lat, d.lng)).toList();
    final t = target;
    final coords = await Future(
      () => routing.findRoute(
        _myPos!.latitude,
        _myPos!.longitude,
        t.latitude,
        t.longitude,
        dangerPoints: dangerPts,
        blockedPoints: blockedPts,
        mode: _routeMode,
      ),
    );

    if (!mounted) return;
    if (coords.isEmpty) {
      setState(() => _routingLoading = false);
      _snackErr('Rota bulunamadı — yol verisi bu bölgeyi kapsamıyor olabilir.');
      return;
    }

    double distM = 0;
    for (int i = 1; i < coords.length; i++) {
      distM += const Distance().as(
        LengthUnit.Meter,
        LatLng(coords[i - 1][0], coords[i - 1][1]),
        LatLng(coords[i][0], coords[i][1]),
      );
    }
    setState(() {
      _safeRoute = coords.map((c) => LatLng(c[0], c[1])).toList();
      _routeDistanceM = distM;
      _routingLoading = false;
    });
  }

  void _snackErr(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800),
    );
  }

  // ── Reporting ──────────────────────────────────────────────────────────────

  Future<void> _reportAtLocation(LatLng point) async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _ReportSheet(
        // <--- WE NAMED THIS sheetContext
        point: point,
        onReport: (type, note) async {
          Navigator.pop(sheetContext); // <--- NOW IT ONLY CLOSES THE MENU
          await _sendReport(point, type, note);
        },
      ),
    );
  }

  Future<void> _sendReport(LatLng p, String type, String note) async {
    switch (type) {
      case MeshPacket.typeSOS:
        await _mesh.sendSOS(p.latitude, p.longitude, note);
      case MeshPacket.typeRoadBlock:
        await _mesh.sendRoadBlock(p.latitude, p.longitude, note);
      case 'water' || 'food' || 'medical' || 'shelter':
        await _mesh.sendResource(p.latitude, p.longitude, type, note);
      case MeshPacket.typeSafeZone:
        await _mesh.sendSafeZone(p.latitude, p.longitude, note);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rapor ağa gönderildi ✓'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _updateMyStatus(String status) {
    setState(() => _myStatus = status);
    if (_myPos != null) {
      _mesh.sendLocationBeacon(
        _myPos!.latitude,
        _myPos!.longitude,
        status: status,
      );
    }
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _packetSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  String _fmtCoord(double v) => v.toStringAsFixed(5);
  String _fmtDist(double m) => m >= 1000
      ? '${(m / 1000).toStringAsFixed(2)} km'
      : '${m.toStringAsFixed(0)} m';
  String _fmtWalkTime(double m) {
    final mins = (m / 83.3).round();
    return mins < 60 ? '~$mins dk' : '~${(mins / 60).toStringAsFixed(1)} sa';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final routing = RoutingService();
    final safePeers = _peers.values.where((p) => p.status == 'safe').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('İstanbul · Mesh'),
        backgroundColor: cs.inversePrimary,
        actions: [
          if (_destination != null || _safeRoute.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Temizle',
              onPressed: _clearAll,
            ),
          if (_myPos != null)
            IconButton(
              icon: const Icon(Icons.my_location),
              tooltip: 'Konumuma Git',
              onPressed: () => _mapController.move(_myPos!, 16),
            ),
          IconButton(
            icon: const Icon(Icons.grid_on),
            tooltip: 'Simülasyon Haritası',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GridMapScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── My status bar ─────────────────────────────────────────────────
          Container(
            color: const Color(0xFF1C1C1C),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Text(
                  'Durumum:',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(width: 8),
                _StatusChip(
                  label: '🟢 Güvende',
                  selected: _myStatus == 'safe',
                  color: Colors.green.shade600,
                  onTap: () => _updateMyStatus('safe'),
                ),
                const SizedBox(width: 6),
                _StatusChip(
                  label: '🟡 Yaralı',
                  selected: _myStatus == 'injured',
                  color: Colors.amber.shade700,
                  onTap: () => _updateMyStatus('injured'),
                ),
                const SizedBox(width: 6),
                _StatusChip(
                  label: '🔴 Tehlikede',
                  selected: _myStatus == 'trapped',
                  color: Colors.red.shade700,
                  onTap: () => _updateMyStatus('trapped'),
                ),
              ],
            ),
          ),

          // ── Map ───────────────────────────────────────────────────────────
          Expanded(
            child: Stack(
              children: [
                if (_cacheDir != null)
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _myPos ?? _istanbul,
                      initialZoom: 14,
                      minZoom: 8,
                      maxZoom: 18,
                      onTap: (_, ll) => _setDestination(ll),
                      onLongPress: (_, ll) => _reportAtLocation(ll),
                    ),
                    children: [
                      TileLayer(
                        key: ValueKey(_tileLayerVersion),
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        tileProvider: OfflineTileProvider(_cacheDir!),
                        userAgentPackageName: 'com.example.meshapp',
                      ),
                      _safeZoneCircleLayer(),
                      if (_safeRoute.isNotEmpty)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _safeRoute,
                              color: Colors.green,
                              strokeWidth: 5,
                            ),
                          ],
                        ),
                      _destinationLayer(),
                      _damageLayer(),
                      _roadBlockLayer(),
                      _resourceLayer(),
                      _safeZoneMarkerLayer(),
                      _sosLayer(),
                      _peerAndSelfLayer(),
                    ],
                  )
                else
                  const Center(child: CircularProgressIndicator()),

                // Error banner
                if (_dlError != null)
                  Positioned(
                    top: 8,
                    left: 12,
                    right: 12,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(8),
                      color: cs.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Text(
                          _dlError!,
                          style: TextStyle(
                            color: cs.onErrorContainer,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Hint
                if (_destination == null)
                  Positioned(
                    top: _dlError != null ? 56 : 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          '👆 Dokun → hedef pin   |   👆 Basılı tut → raporla',
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ),
                  ),

                // Route mode toggle
                Positioned(
                  top: _dlError != null ? 56 : (_destination == null ? 44 : 8),
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ModeChip(
                            label: '🚶 Yürüyüş',
                            selected: _routeMode == RouteMode.walking,
                            onTap: () => setState(() {
                              _routeMode = RouteMode.walking;
                              _safeRoute = [];
                              _routeDistanceM = null;
                            }),
                          ),
                          const SizedBox(width: 4),
                          _ModeChip(
                            label: '🚗 Araç',
                            selected: _routeMode == RouteMode.car,
                            onTap: () => setState(() {
                              _routeMode = RouteMode.car;
                              _safeRoute = [];
                              _routeDistanceM = null;
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // FABs
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (!routing.isLoaded)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _downloadingRouting
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade800,
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 220,
                                        ),
                                        child: Text(
                                          _routingStatus,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : FloatingActionButton.extended(
                                  heroTag: 'routing',
                                  onPressed: _downloadRoutingData,
                                  backgroundColor: Colors.orange.shade700,
                                  icon: const Icon(
                                    Icons.route,
                                    color: Colors.white,
                                  ),
                                  label: Text(
                                    _routingStatus.isEmpty
                                        ? 'Yol Verisini İndir'
                                        : _routingStatus,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                        ),
                      if (!_offline)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _downloading
                              ? _TileProgress(
                                  progress: _dlProgress,
                                  total: _dlTotal,
                                )
                              : FloatingActionButton.extended(
                                  heroTag: 'tiles',
                                  onPressed: _downloadTiles,
                                  backgroundColor: Colors.indigo,
                                  icon: const Icon(
                                    Icons.download,
                                    color: Colors.white,
                                  ),
                                  label: const Text(
                                    'Haritayı İndir',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                        ),
                      _routingLoading
                          ? FloatingActionButton.extended(
                              heroTag: 'route_loading',
                              onPressed: null,
                              backgroundColor: Colors.green.shade800,
                              icon: const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                              label: const Text(
                                'Hesaplanıyor…',
                                style: TextStyle(color: Colors.white),
                              ),
                            )
                          : FloatingActionButton.extended(
                              heroTag: 'route',
                              onPressed: _safeRoute.isEmpty
                                  ? _findEvacuationRoute
                                  : _clearAll,
                              backgroundColor: _safeRoute.isEmpty
                                  ? (_destination != null
                                        ? Colors.green.shade700
                                        : Colors.blueGrey)
                                  : Colors.red.shade700,
                              icon: Icon(
                                _safeRoute.isEmpty
                                    ? Icons.directions_walk
                                    : Icons.close,
                                color: Colors.white,
                              ),
                              label: Text(
                                _safeRoute.isEmpty
                                    ? (_destination != null
                                          ? 'Rota Oluştur'
                                          : 'En Yakın Güvenli')
                                    : 'Rotayı Sil',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Stats panel ───────────────────────────────────────────────────
        ],
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _TileProgress extends StatelessWidget {
  const _TileProgress({required this.progress, required this.total});
  final double progress;
  final int total;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(28),
      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(value: progress, strokeWidth: 2.5),
        ),
        const SizedBox(width: 10),
        Text(
          '${(progress * 100).toStringAsFixed(0)}% of $total tiles',
          style: const TextStyle(fontSize: 13),
        ),
      ],
    ),
  );
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: selected ? Colors.black87 : Colors.white70,
        ),
      ),
    ),
  );
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _StatusChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? color : color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: selected ? 0 : 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: selected ? Colors.white : color,
        ),
      ),
    ),
  );
}

// ── Report bottom sheet ────────────────────────────────────────────────────────

class _ReportSheet extends StatefulWidget {
  final LatLng point;
  final void Function(String type, String note) onReport;
  const _ReportSheet({required this.point, required this.onReport});
  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String? _sel;
  final _noteCtrl = TextEditingController();

  static const _opts = [
    ('sos', Icons.sos, 'Yardım\nGerekiyor', Color(0xFFD32F2F)),
    ('block', Icons.block, 'Yol\nKapalı', Color(0xFFF57C00)),
    ('water', Icons.water_drop, 'Su\nKaynağı', Color(0xFF1976D2)),
    ('food', Icons.restaurant, 'Yiyecek', Color(0xFF388E3C)),
    ('medical', Icons.medical_services, 'İlk\nYardım', Color(0xFFC62828)),
    ('shelter', Icons.night_shelter, 'Barınak', Color(0xFF5D4037)),
    ('safezone', Icons.verified_user, 'Güvenli\nBölge', Color(0xFF00796B)),
  ];

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.location_on, color: Colors.redAccent, size: 16),
              const SizedBox(width: 6),
              Text(
                '${widget.point.latitude.toStringAsFixed(5)}, ${widget.point.longitude.toStringAsFixed(5)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const Spacer(),
              const Text(
                'Burası Raporla',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: _opts.map((opt) {
              final (type, icon, label, color) = opt;
              final sel = _sel == type;
              return GestureDetector(
                onTap: () => setState(() => _sel = type),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    color: sel ? color : color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color, width: sel ? 2 : 1),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: sel ? Colors.white : color, size: 26),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 10,
                          color: sel ? Colors.white : color,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          if (_sel != null) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                hintText: 'Not ekle (isteğe bağlı)…',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.all(10),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => widget.onReport(_sel!, _noteCtrl.text.trim()),
                icon: const Icon(Icons.send),
                label: const Text('Ağa Gönder'),
                style: FilledButton.styleFrom(
                  backgroundColor: _opts.firstWhere((o) => o.$1 == _sel).$4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
