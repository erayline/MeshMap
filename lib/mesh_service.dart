import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class MeshPacket {
  static const String typeMessage = 'msg';
  static const String typeLocation = 'loc';
  static const String typeDamage = 'damage';
  static const String typeSOS = 'sos';
  static const String typeRoadBlock = 'block';
  static const String typeResource = 'resource';
  static const String typeSafeZone = 'safezone';

  final String id;
  final String senderId;
  final String payload;
  final int ttl;
  final int timestamp;
  final String type;

  const MeshPacket({
    required this.id,
    required this.senderId,
    required this.payload,
    required this.ttl,
    required this.timestamp,
    this.type = typeMessage,
  });

  int get hops => 10 - ttl;

  Map<String, dynamic> toJson() => {
    'id': id,
    'senderId': senderId,
    'payload': payload,
    'ttl': ttl,
    'timestamp': timestamp,
    'type': type,
  };

  factory MeshPacket.fromJson(Map<String, dynamic> j) => MeshPacket(
    id: j['id'] as String,
    senderId: j['senderId'] as String,
    payload: j['payload'] as String,
    ttl: j['ttl'] as int,
    timestamp: j['timestamp'] as int,
    type: (j['type'] as String?) ?? typeMessage,
  );

  String toJsonString() => jsonEncode(toJson());

  static MeshPacket fromJsonString(String s) =>
      MeshPacket.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

class MeshService {
  static final MeshService _instance = MeshService._internal();
  factory MeshService() => _instance;
  MeshService._internal();

  static const String _boxName = 'mesh_packets';
  static const int _initialTtl = 10;
  static const String _serviceId = 'com.example.meshapp.nearby';

  late String deviceId;

  final Set<String> _connectedEndpoints = {};
  final Set<String> _seenIds = {};
  // Guards against duplicate requestConnection calls for the same endpoint.
  final Set<String> _pendingConnections = {};

  final Map<String, MeshPacket> latestLocations = {};
  final Map<String, MeshPacket> latestDamage = {};
  final Map<String, MeshPacket> latestSOS = {};
  final Map<String, MeshPacket> latestRoadBlocks = {};
  final Map<String, MeshPacket> latestResources = {};
  final Map<String, MeshPacket> latestSafeZones = {};

  final _packetController = StreamController<MeshPacket>.broadcast();
  final _peersController = StreamController<Set<String>>.broadcast();

  late Box<String> _box;

  Stream<MeshPacket> get packetStream => _packetController.stream;
  Stream<Set<String>> get peersStream => _peersController.stream;
  Set<String> get connectedEndpoints => Set.unmodifiable(_connectedEndpoints);

  // ── Initialization ───────────────────────────────────────────────────────

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    deviceId = prefs.getString('device_id') ?? _newDeviceId();
    await prefs.setString('device_id', deviceId);
    _box = await Hive.openBox<String>(_boxName);
  }

  String _newDeviceId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    return List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // ── Networking ───────────────────────────────────────────────────────────

  Future<void> start() async {
    // Tear down any stale session from a previous run or hot-restart before
    // starting fresh. Skipping this step is the #1 cause of "stopped working"
    // bugs — startAdvertising/startDiscovery throw if already running, and
    // those errors were previously swallowed silently.
    try { await Nearby().stopAllEndpoints(); } catch (_) {}
    try { await Nearby().stopAdvertising(); } catch (_) {}
    try { await Nearby().stopDiscovery(); } catch (_) {}
    _connectedEndpoints.clear();
    _pendingConnections.clear();
    _peersController.add({});

    // Let the platform layer finish winding down before we restart.
    await Future.delayed(const Duration(milliseconds: 500));

    await _startAdvertising();
    await _startDiscovery();
  }

  Future<void> stop() async {
    try { await Nearby().stopAllEndpoints(); } catch (_) {}
    try { await Nearby().stopAdvertising(); } catch (_) {}
    try { await Nearby().stopDiscovery(); } catch (_) {}
    _connectedEndpoints.clear();
    _pendingConnections.clear();
    _peersController.add({});
  }

  Future<void> restart() => stop().then((_) => start());

  Future<void> _startAdvertising() async {
    try {
      await Nearby().startAdvertising(
        deviceId,
        Strategy.P2P_CLUSTER,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: _serviceId,
      );
    } catch (_) {
      // May fail if platform takes longer to wind down — retry once.
      await Future.delayed(const Duration(seconds: 1));
      try {
        await Nearby().startAdvertising(
          deviceId,
          Strategy.P2P_CLUSTER,
          onConnectionInitiated: _onConnectionInitiated,
          onConnectionResult: _onConnectionResult,
          onDisconnected: _onDisconnected,
          serviceId: _serviceId,
        );
      } catch (_) {}
    }
  }

  Future<void> _startDiscovery() async {
    try {
      await Nearby().startDiscovery(
        deviceId,
        Strategy.P2P_CLUSTER,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: (_) {},
        serviceId: _serviceId,
      );
    } catch (_) {
      await Future.delayed(const Duration(seconds: 1));
      try {
        await Nearby().startDiscovery(
          deviceId,
          Strategy.P2P_CLUSTER,
          onEndpointFound: _onEndpointFound,
          onEndpointLost: (_) {},
          serviceId: _serviceId,
        );
      } catch (_) {}
    }
  }

  // ── Connection callbacks ─────────────────────────────────────────────────

  Future<void> _onEndpointFound(
    String endpointId,
    String name,
    String serviceId,
  ) async {
    // Skip if already connected or a connection attempt is already in-flight.
    if (_connectedEndpoints.contains(endpointId)) return;
    if (_pendingConnections.contains(endpointId)) return;
    _pendingConnections.add(endpointId);
    try {
      await Nearby().requestConnection(
        deviceId,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (_) {
      _pendingConnections.remove(endpointId);
    }
  }

  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    // acceptConnection returns Future<bool>. We must not drop the future —
    // silent failures here mean packets are never received.
    Nearby()
        .acceptConnection(
          endpointId,
          onPayLoadRecieved: (id, payload) {
            if (payload.type == PayloadType.BYTES && payload.bytes != null) {
              try {
                final packet = MeshPacket.fromJsonString(
                  utf8.decode(payload.bytes!),
                );
                _handleIncoming(packet);
              } catch (_) {}
            }
          },
          onPayloadTransferUpdate: (_, _) {},
        )
        .catchError((_) => false);
  }

  void _onConnectionResult(String endpointId, Status status) {
    _pendingConnections.remove(endpointId);
    if (status == Status.CONNECTED) {
      _connectedEndpoints.add(endpointId);
      _peersController.add(Set.from(_connectedEndpoints));
    }
  }

  void _onDisconnected(String endpointId) {
    _connectedEndpoints.remove(endpointId);
    _pendingConnections.remove(endpointId);
    _peersController.add(Set.from(_connectedEndpoints));
    // Restart discovery so we can find and reconnect to the lost peer (or new ones).
    _startDiscovery();
  }

  // ── Packet handling ──────────────────────────────────────────────────────

  void _handleIncoming(MeshPacket packet) {
    if (_seenIds.contains(packet.id)) return;
    if (packet.ttl <= 0) return;

    _seenIds.add(packet.id);
    _box.put(packet.id, packet.toJsonString());
    if (packet.type == MeshPacket.typeLocation) {
      latestLocations[packet.senderId] = packet;
    } else if (packet.type == MeshPacket.typeDamage) {
      latestDamage[packet.id] = packet;
    } else if (packet.type == MeshPacket.typeSOS) {
      latestSOS[packet.id] = packet;
    } else if (packet.type == MeshPacket.typeRoadBlock) {
      latestRoadBlocks[packet.id] = packet;
    } else if (packet.type == MeshPacket.typeResource) {
      latestResources[packet.id] = packet;
    } else if (packet.type == MeshPacket.typeSafeZone) {
      latestSafeZones[packet.id] = packet;
    }
    _packetController.add(packet);

    final forwarded = MeshPacket(
      id: packet.id,
      senderId: packet.senderId,
      payload: packet.payload,
      ttl: packet.ttl - 1,
      timestamp: packet.timestamp,
      type: packet.type,
    );
    Future.delayed(
      const Duration(milliseconds: 500),
      () => _broadcast(forwarded),
    );
  }

  void _broadcast(MeshPacket packet) {
    if (packet.ttl <= 0 || _connectedEndpoints.isEmpty) return;
    final bytes = Uint8List.fromList(utf8.encode(packet.toJsonString()));
    for (final id in List<String>.from(_connectedEndpoints)) {
      Nearby().sendBytesPayload(id, bytes).catchError((_) {
        _connectedEndpoints.remove(id);
        _peersController.add(Set.from(_connectedEndpoints));
      });
    }
  }

  // ── Public API ───────────────────────────────────────────────────────────

  Future<void> sendPacket(String payload) async {
    final packet = MeshPacket(
      id: const Uuid().v4(),
      senderId: deviceId,
      payload: payload,
      ttl: _initialTtl,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    _seenIds.add(packet.id);
    _box.put(packet.id, packet.toJsonString());
    _packetController.add(packet);
    _broadcast(packet);
  }

  Future<void> sendLocationBeacon(
    double lat,
    double lng, {
    String status = 'safe',
  }) async {
    final packet = MeshPacket(
      id: const Uuid().v4(),
      senderId: deviceId,
      payload: jsonEncode({'lat': lat, 'lng': lng, 'status': status}),
      ttl: _initialTtl,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      type: MeshPacket.typeLocation,
    );
    _seenIds.add(packet.id);
    _box.put(packet.id, packet.toJsonString());
    latestLocations[deviceId] = packet;
    _packetController.add(packet);
    _broadcast(packet);
  }

  Future<void> sendDamageMarker(double lat, double lng, String note) async {
    final packet = MeshPacket(
      id: const Uuid().v4(),
      senderId: deviceId,
      payload: jsonEncode({'lat': lat, 'lng': lng, 'note': note}),
      ttl: _initialTtl,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      type: MeshPacket.typeDamage,
    );
    _seenIds.add(packet.id);
    _box.put(packet.id, packet.toJsonString());
    latestDamage[packet.id] = packet;
    _packetController.add(packet);
    _broadcast(packet);
  }

  Future<String> sendSOS(double lat, double lng, String note) async {
    final packet = MeshPacket(
      id: const Uuid().v4(),
      senderId: deviceId,
      payload: jsonEncode({'lat': lat, 'lng': lng, 'note': note}),
      ttl: _initialTtl,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      type: MeshPacket.typeSOS,
    );
    _seenIds.add(packet.id);
    _box.put(packet.id, packet.toJsonString());
    latestSOS[packet.id] = packet;
    _packetController.add(packet);
    _broadcast(packet);
    return packet.id;
  }

  Future<String> sendRoadBlock(double lat, double lng, String note) async {
    final packet = MeshPacket(
      id: const Uuid().v4(),
      senderId: deviceId,
      payload: jsonEncode({'lat': lat, 'lng': lng, 'note': note}),
      ttl: _initialTtl,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      type: MeshPacket.typeRoadBlock,
    );
    _seenIds.add(packet.id);
    _box.put(packet.id, packet.toJsonString());
    latestRoadBlocks[packet.id] = packet;
    _packetController.add(packet);
    _broadcast(packet);
    return packet.id;
  }

  Future<String> sendResource(
    double lat,
    double lng,
    String resType,
    String note,
  ) async {
    final packet = MeshPacket(
      id: const Uuid().v4(),
      senderId: deviceId,
      payload: jsonEncode({
        'lat': lat,
        'lng': lng,
        'type': resType,
        'note': note,
      }),
      ttl: _initialTtl,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      type: MeshPacket.typeResource,
    );
    _seenIds.add(packet.id);
    _box.put(packet.id, packet.toJsonString());
    latestResources[packet.id] = packet;
    _packetController.add(packet);
    _broadcast(packet);
    return packet.id;
  }

  Future<String> sendSafeZone(double lat, double lng, String note) async {
    final packet = MeshPacket(
      id: const Uuid().v4(),
      senderId: deviceId,
      payload: jsonEncode({'lat': lat, 'lng': lng, 'note': note}),
      ttl: _initialTtl,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      type: MeshPacket.typeSafeZone,
    );
    _seenIds.add(packet.id);
    _box.put(packet.id, packet.toJsonString());
    latestSafeZones[packet.id] = packet;
    _packetController.add(packet);
    _broadcast(packet);
    return packet.id;
  }

  List<MeshPacket> get storedPackets =>
      _box.values.map(MeshPacket.fromJsonString).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  void dispose() {
    Nearby().stopAdvertising();
    Nearby().stopDiscovery();
    Nearby().stopAllEndpoints();
    _packetController.close();
    _peersController.close();
  }
}
