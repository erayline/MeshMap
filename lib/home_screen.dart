import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'map_screen.dart';
import 'mesh_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _mesh = MeshService();
  final _packets = <MeshPacket>[];
  Set<String> _peers = {};

  late final StreamSubscription<MeshPacket> _packetSub;
  late final StreamSubscription<Set<String>> _peersSub;

  @override
  void initState() {
    super.initState();

    // Pre-populate with all report types, excluding raw location beacons
    _packets.addAll(
      _mesh.storedPackets.where(
        (p) =>
            p.type != MeshPacket.typeLocation &&
            p.type != MeshPacket.typeMessage,
      ),
    );

    _packetSub = _mesh.packetStream.listen((packet) {
      if (!mounted || packet.type == MeshPacket.typeLocation) return;
      setState(() {
        // Prevent duplicate cards for the same event ID
        final index = _packets.indexWhere((p) => p.id == packet.id);
        if (index != -1) {
          _packets[index] = packet; // Update existing card
        } else {
          _packets.insert(0, packet); // Add new incident to top
        }
      });
    });

    _peersSub = _mesh.peersStream.listen((peers) {
      if (!mounted) return;
      setState(() => _peers = peers);
    });
  }

  @override
  void dispose() {
    _packetSub.cancel();
    _peersSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFF121212), // Dark mode for better contrast
      appBar: AppBar(
        title: const Text('Acil Durum Akışı'),
        backgroundColor: cs.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.map),
            tooltip: 'Haritaya Git',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MapScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _DeviceInfoBanner(deviceId: _mesh.deviceId, peers: _peers),
          Expanded(child: _buildIncidentFeed(cs)),
        ],
      ),
    );
  }

  Widget _buildIncidentFeed(ColorScheme cs) {
    if (_packets.isEmpty) {
      return const Center(
        child: Text(
          'Henüz bir rapor yok.\nAğdan veri bekleniyor...',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _packets.length,
      itemBuilder: (context, i) => _IncidentCard(packet: _packets[i]),
    );
  }
}

class _IncidentCard extends StatelessWidget {
  final MeshPacket packet;
  const _IncidentCard({required this.packet});

  @override
  Widget build(BuildContext context) {
    final data = jsonDecode(packet.payload) as Map<String, dynamic>;
    final lat = (data['lat'] as num).toDouble();
    final lng = (data['lng'] as num).toDouble();
    final note = (data['note'] as String?) ?? '';
    final time = DateTime.fromMillisecondsSinceEpoch(packet.timestamp);

    // Configuration based on Packet Type
    final (label, icon, color) = switch (packet.type) {
      MeshPacket.typeSOS => ('YARDIM ÇAĞRISI (SOS)', Icons.sos, Colors.red),
      MeshPacket.typeDamage => ('HASAR BİLDİRİMİ', Icons.report, Colors.orange),
      MeshPacket.typeRoadBlock => (
        'YOL KAPALI',
        Icons.block,
        Colors.deepOrange,
      ),
      MeshPacket.typeResource => (
        'KAYNAK BİLDİRİMİ',
        Icons.inventory_2,
        Colors.blue,
      ),
      MeshPacket.typeSafeZone => (
        'GÜVENLİ BÖLGE',
        Icons.verified_user,
        Colors.teal,
      ),
      _ => ('BİLGİ', Icons.info, Colors.grey),
    };

    return Card(
      color: color.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.5), width: 1),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                Text(
                  '${time.hour}:${time.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                note,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Gönderen: ${packet.senderId} • ${packet.hops} sekme',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    // Navigate to Map and center on the incident
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const MapScreen(), // In production, add a lat/lng param to focus
                      ),
                    );
                  },
                  icon: const Icon(Icons.location_on, size: 16),
                  label: const Text(
                    'Haritada Gör',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(foregroundColor: color),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceInfoBanner extends StatelessWidget {
  const _DeviceInfoBanner({required this.deviceId, required this.peers});

  final String deviceId;
  final Set<String> peers;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: cs.primaryContainer.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.devices, size: 16, color: Colors.white70),
              const SizedBox(width: 6),
              Text(
                'ID: ',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
              Text(
                deviceId,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                peers.isEmpty ? Icons.wifi_off : Icons.wifi,
                size: 16,
                color: peers.isEmpty ? Colors.grey : Colors.green,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  peers.isEmpty
                      ? 'Ağ aranıyor (Reklam & Keşif aktif)…'
                      : 'Bağlı Cihazlar (${peers.length}): ${peers.join("  •  ")}',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
