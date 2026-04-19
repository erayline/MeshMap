import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'user_service.dart';

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
  final String senderName; // display name, travels with packet across hops
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
    this.senderName = '',
  });

  int get hops => 10 - ttl;

  Map<String, dynamic> toJson() => {
    'id': id,
    'senderId': senderId,
    if (senderName.isNotEmpty) 'senderName': senderName,
    'payload': payload,
    'ttl': ttl,
    'timestamp': timestamp,
    'type': type,
  };

  factory MeshPacket.fromJson(Map<String, dynamic> j) => MeshPacket(
    id: j['id'] as String,
    senderId: j['senderId'] as String,
    senderName: (j['senderName'] as String?) ?? '',
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

  // Ghost endpoint detection: evict if no payload received within this window.
  // Location beacons every 30s, so 90s = 3 missed beacons before declaring dead.
  static const Duration _staleThreshold = Duration(seconds: 90);
  static const Duration _cleanupInterval = Duration(seconds: 45);

  late String deviceId;
  String _displayName = '';

  final Set<String> _connectedEndpoints = {};
  final Set<String> _seenIds = {};
  final Set<String> _pendingConnections = {};
  final Map<String, int> _endpointLastSeen = {};

  // Maps deviceId → display name, populated from HELLO packets (used for packets).
  final Map<String, String> _peerNames = {};
  // Maps endpointId → display name (used for the peers UI list).
  final Map<String, String> _endpointNames = {};

  Timer? _cleanupTimer;

  // Stats
  int messagesReceived = 0;
  int packetsRelayed = 0;
  int totalConnections = 0;
  DateTime? sessionStart;

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
  Map<String, String> get peerNames => Map.unmodifiable(_peerNames);
  Map<String, String> get endpointNames => Map.unmodifiable(_endpointNames);
  int get connectedPeerCount => _connectedEndpoints.length;

  // ── Initialization ───────────────────────────────────────────────────────

  Future<void> init() async {
    await UserService().load();
    _displayName = UserService().displayName;

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

  void setDisplayName(String name) => _displayName = name;

  // ── Networking ───────────────────────────────────────────────────────────

  Future<void> start() async {
    _cleanupTimer?.cancel();
    sessionStart = DateTime.now();

    // Clear state FIRST so stopAllEndpoints onDisconnected callbacks are no-ops.
    _connectedEndpoints.clear();
    _pendingConnections.clear();
    _endpointLastSeen.clear();
    _peerNames.clear();
    _endpointNames.clear();
    _peersController.add({});

    // Tear down stale Nearby Connections session from previous run / hot-restart.
    try { await Nearby().stopAllEndpoints(); } catch (_) {}
    try { await Nearby().stopAdvertising(); } catch (_) {}
    try { await Nearby().stopDiscovery(); } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 500));

    await _startAdvertising();
    await _startDiscovery();

    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) => _evictStaleEndpoints());
  }

  Future<void> stop() async {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;

    try { await Nearby().stopAllEndpoints(); } catch (_) {}
    try { await Nearby().stopAdvertising(); } catch (_) {}
    try { await Nearby().stopDiscovery(); } catch (_) {}

    _connectedEndpoints.clear();
    _pendingConnections.clear();
    _endpointLastSeen.clear();
    _peersController.add({});
  }

  Future<void> restart() => stop().then((_) => start());

  Future<void> _startAdvertising() async {
    // Advertised name encodes our deviceId so peers can extract it before HELLO.
    final advertisedName = 'ml2|$deviceId';
    try {
      await Nearby().startAdvertising(
        advertisedName,
        Strategy.P2P_CLUSTER,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: _serviceId,
      );
    } catch (_) {
      await Future.delayed(const Duration(seconds: 1));
      try {
        await Nearby().startAdvertising(
          advertisedName,
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
    final advertisedName = 'ml2|$deviceId';
    try {
      await Nearby().startDiscovery(
        advertisedName,
        Strategy.P2P_CLUSTER,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: (_) {},
        serviceId: _serviceId,
      );
    } catch (_) {
      await Future.delayed(const Duration(seconds: 1));
      try {
        await Nearby().startDiscovery(
          advertisedName,
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
    if (_connectedEndpoints.contains(endpointId)) return;
    if (_pendingConnections.contains(endpointId)) return;
    _pendingConnections.add(endpointId);
    try {
      await Nearby().requestConnection(
        'ml2|$deviceId',
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
    Nearby()
        .acceptConnection(
          endpointId,
          onPayLoadRecieved: (senderEndpointId, payload) {
            _endpointLastSeen[senderEndpointId] =
                DateTime.now().millisecondsSinceEpoch;

            if (payload.type == PayloadType.BYTES && payload.bytes != null) {
              try {
                final raw = utf8.decode(payload.bytes!);
                final parsed = jsonDecode(raw) as Map<String, dynamic>;

                // HELLO handshake — not a regular packet, don't relay.
                if (parsed['kind'] == 'hello') {
                  final sid = (parsed['sid'] as String?) ?? '';
                  final name = (parsed['name'] as String?) ?? '';
                  if (name.isNotEmpty) {
                    if (sid.isNotEmpty) _peerNames[sid] = name;
                    // Also key by endpointId so the peers UI can look up names.
                    _endpointNames[senderEndpointId] = name;
                    _peersController.add(Set.from(_connectedEndpoints));
                  }
                  return;
                }

                final packet = MeshPacket.fromJson(parsed);
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
      _endpointLastSeen[endpointId] = DateTime.now().millisecondsSinceEpoch;
      totalConnections++;
      _peersController.add(Set.from(_connectedEndpoints));
      // Send HELLO so peer learns our display name.
      _sendHello(endpointId);
    }
  }

  void _onDisconnected(String endpointId) {
    _connectedEndpoints.remove(endpointId);
    _pendingConnections.remove(endpointId);
    _endpointLastSeen.remove(endpointId);
    _endpointNames.remove(endpointId);
    _peersController.add(Set.from(_connectedEndpoints));
    // Do NOT restart discovery here — already running continuously.
  }

  // Evicts peers whose onDisconnected never fired (GMS bug on some devices).
  void _evictStaleEndpoints() {
    final cutoff =
        DateTime.now().millisecondsSinceEpoch - _staleThreshold.inMilliseconds;
    bool changed = false;
    for (final id in List<String>.from(_connectedEndpoints)) {
      if ((_endpointLastSeen[id] ?? 0) < cutoff) {
        Nearby().disconnectFromEndpoint(id);
        _connectedEndpoints.remove(id);
        _endpointLastSeen.remove(id);
        changed = true;
      }
    }
    if (changed) _peersController.add(Set.from(_connectedEndpoints));
  }

  void _sendHello(String endpointId) {
    final hello = jsonEncode({'kind': 'hello', 'sid': deviceId, 'name': _displayName});
    final bytes = Uint8List.fromList(utf8.encode(hello));
    Nearby().sendBytesPayload(endpointId, bytes);
  }

  // ── Packet handling ──────────────────────────────────────────────────────

  void _handleIncoming(MeshPacket packet) {
    if (_seenIds.contains(packet.id)) return;
    if (packet.ttl <= 0) return;

    _seenIds.add(packet.id);
    _box.put(packet.id, packet.toJsonString());
    messagesReceived++;

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
      senderName: packet.senderName,
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
      // sendBytesPayload always returns success even for dead endpoints —
      // ghost cleanup is handled by _evictStaleEndpoints() instead.
      Nearby().sendBytesPayload(id, bytes);
      packetsRelayed++;
    }
  }

  // ── Public API ───────────────────────────────────────────────────────────

  Future<void> sendPacket(String payload, {String type = MeshPacket.typeMessage}) async {
    final packet = MeshPacket(
      id: const Uuid().v4(),
      senderId: deviceId,
      senderName: _displayName,
      payload: payload,
      ttl: _initialTtl,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      type: type,
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
      senderName: _displayName,
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
      senderName: _displayName,
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
      senderName: _displayName,
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
      senderName: _displayName,
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
      senderName: _displayName,
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
      senderName: _displayName,
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
    _cleanupTimer?.cancel();
    Nearby().stopAdvertising();
    Nearby().stopDiscovery();
    Nearby().stopAllEndpoints();
    _packetController.close();
    _peersController.close();
  }
}
