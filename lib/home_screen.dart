import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'map_screen.dart';
import 'mesh_service.dart';

// ── Palette ──────────────────────────────────────────────────────────────────

const _bg = Color(0xFFF0F4FF);
const _surface = Colors.white;
const _primary = Color(0xFF4F46E5);   // indigo
const _onPrimary = Colors.white;
const _textDark = Color(0xFF1E1B4B);
const _textMid = Color(0xFF6B7280);
const _textLight = Color(0xFF9CA3AF);

const _colorSOS = Color(0xFFDC2626);
const _colorDamage = Color(0xFFEA580C);
const _colorBlock = Color(0xFFC2410C);
const _colorResource = Color(0xFF0284C7);
const _colorSafeZone = Color(0xFF059669);
const _colorMessage = Color(0xFF7C3AED);

// ── Screen ───────────────────────────────────────────────────────────────────

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

  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();

    // Load history — include messages this time.
    _packets.addAll(
      _mesh.storedPackets
          .where((p) => p.type != MeshPacket.typeLocation)
          .toList()
          .reversed, // stored packets come newest-first; we display oldest-first
    );

    _packetSub = _mesh.packetStream.listen((packet) {
      if (!mounted || packet.type == MeshPacket.typeLocation) return;
      setState(() {
        final idx = _packets.indexWhere((p) => p.id == packet.id);
        if (idx != -1) {
          _packets[idx] = packet;
        } else {
          _packets.add(packet); // append so newest is at bottom
        }
      });
      _scrollToBottom();
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
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();
    _mesh.sendPacket(jsonEncode({'text': text}));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _StatusBanner(
            deviceId: _mesh.deviceId,
            peers: _peers,
            onReconnect: _mesh.restart,
          ),
          Expanded(child: _buildFeed()),
          _ChatInput(controller: _msgCtrl, onSend: _sendMessage),
        ],
      ),
    );
  }

  AppBar _buildAppBar() => AppBar(
    backgroundColor: _surface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shadowColor: Colors.black12,
    scrolledUnderElevation: 2,
    title: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.hub_rounded, color: _onPrimary, size: 18),
        ),
        const SizedBox(width: 10),
        const Text(
          'MeshNet',
          style: TextStyle(
            color: _textDark,
            fontWeight: FontWeight.w700,
            fontSize: 19,
            letterSpacing: -0.3,
          ),
        ),
      ],
    ),
    actions: [
      IconButton(
        icon: const Icon(Icons.map_rounded, color: _primary),
        tooltip: 'Harita',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MapScreen()),
        ),
      ),
      const SizedBox(width: 4),
    ],
  );

  Widget _buildFeed() {
    if (_packets.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wifi_tethering_rounded,
                  color: _primary, size: 36),
            ),
            const SizedBox(height: 16),
            const Text(
              'Ağ bağlantısı aranıyor…',
              style: TextStyle(
                color: _textDark,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Mesaj göndermek için alttaki alanı kullanın.',
              style: TextStyle(color: _textMid, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      itemCount: _packets.length,
      itemBuilder: (ctx, i) {
        final p = _packets[i];
        if (p.type == MeshPacket.typeMessage) {
          return _MessageBubble(
            packet: p,
            isOwn: p.senderId == _mesh.deviceId,
          );
        }
        return _IncidentCard(packet: p);
      },
    );
  }
}

// ── Status banner ─────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.deviceId,
    required this.peers,
    required this.onReconnect,
  });

  final String deviceId;
  final Set<String> peers;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final connected = peers.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Device chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.smartphone_rounded,
                    size: 13, color: _primary),
                const SizedBox(width: 5),
                Text(
                  deviceId,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _primary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Peer status chip
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: connected
                    ? const Color(0xFFECFDF5)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: connected
                      ? const Color(0xFF6EE7B7)
                      : Colors.grey.shade300,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: connected
                          ? const Color(0xFF10B981)
                          : Colors.grey.shade400,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      connected
                          ? '${peers.length} cihaz bağlı'
                          : 'Taranıyor…',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: connected
                            ? const Color(0xFF065F46)
                            : Colors.grey.shade600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Reconnect button
          GestureDetector(
            onTap: onReconnect,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.refresh_rounded,
                  size: 18, color: _textMid),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.packet, required this.isOwn});

  final MeshPacket packet;
  final bool isOwn;

  @override
  Widget build(BuildContext context) {
    final data = jsonDecode(packet.payload) as Map<String, dynamic>;
    final text = (data['text'] as String?) ?? packet.payload;
    final time = DateTime.fromMillisecondsSinceEpoch(packet.timestamp);
    final timeStr =
        '${time.hour}:${time.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment:
            isOwn ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isOwn) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: _colorMessage.withValues(alpha: 0.15),
              child: Text(
                packet.senderId.substring(0, 1),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _colorMessage,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.70,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isOwn ? _primary : _surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isOwn ? 18 : 4),
                  bottomRight: Radius.circular(isOwn ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: isOwn
                    ? null
                    : Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: isOwn
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (!isOwn) ...[
                    Text(
                      packet.senderId,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _colorMessage,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                  ],
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 15,
                      color: isOwn ? _onPrimary : _textDark,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 10,
                      color: isOwn
                          ? _onPrimary.withValues(alpha: 0.6)
                          : _textLight,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isOwn) const SizedBox(width: 6),
        ],
      ),
    );
  }
}

// ── Incident card ─────────────────────────────────────────────────────────────

class _IncidentCard extends StatelessWidget {
  const _IncidentCard({required this.packet});
  final MeshPacket packet;

  @override
  Widget build(BuildContext context) {
    final data = jsonDecode(packet.payload) as Map<String, dynamic>;
    final note = (data['note'] as String?) ?? '';
    final time = DateTime.fromMillisecondsSinceEpoch(packet.timestamp);
    final timeStr =
        '${time.hour}:${time.minute.toString().padLeft(2, '0')}';

    final (label, icon, accent) = switch (packet.type) {
      MeshPacket.typeSOS => (
        'YARDIM ÇAĞRISI',
        Icons.sos_rounded,
        _colorSOS,
      ),
      MeshPacket.typeDamage => (
        'HASAR BİLDİRİMİ',
        Icons.warning_rounded,
        _colorDamage,
      ),
      MeshPacket.typeRoadBlock => (
        'YOL KAPALI',
        Icons.do_not_disturb_on_rounded,
        _colorBlock,
      ),
      MeshPacket.typeResource => (
        'KAYNAK',
        Icons.inventory_2_rounded,
        _colorResource,
      ),
      MeshPacket.typeSafeZone => (
        'GÜVENLİ BÖLGE',
        Icons.verified_user_rounded,
        _colorSafeZone,
      ),
      _ => ('BİLGİ', Icons.info_rounded, _textMid),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Colored left accent bar
              Container(width: 4, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header row
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Icon(icon, color: accent, size: 16),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            label,
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            timeStr,
                            style: const TextStyle(
                              color: _textLight,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Text(
                          note,
                          style: const TextStyle(
                            color: _textDark,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      // Footer
                      Row(
                        children: [
                          Icon(Icons.person_outline_rounded,
                              size: 12, color: _textLight),
                          const SizedBox(width: 3),
                          Text(
                            packet.senderId,
                            style: const TextStyle(
                              color: _textLight,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${packet.hops} sekme',
                              style: const TextStyle(
                                  fontSize: 9, color: _textLight),
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const MapScreen()),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.location_on_rounded,
                                    size: 13, color: accent),
                                const SizedBox(width: 3),
                                Text(
                                  'Haritada gör',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Chat input ────────────────────────────────────────────────────────────────

class _ChatInput extends StatelessWidget {
  const _ChatInput({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 10,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: const TextStyle(color: _textDark, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Ağa mesaj gönder…',
                hintStyle: const TextStyle(color: _textLight, fontSize: 14),
                filled: true,
                fillColor: _bg,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: _primary, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _primary.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(Icons.send_rounded,
                  color: _onPrimary, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
