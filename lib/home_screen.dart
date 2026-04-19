import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'map_screen.dart';
import 'mesh_service.dart';
import 'user_service.dart';

// ── Palette ──────────────────────────────────────────────────────────────────

const _bg = Color(0xFFF0F4FF);
const _surface = Colors.white;
const _primary = Color(0xFF4F46E5); // indigo
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

// Quick emergency preset messages
const _presets = [
  ('🆘', 'Yardıma ihtiyacım var, acil yardım gönderin!'),
  ('✅', 'Güvendeyim, hareket etmiyorum.'),
  ('💧', 'Su ve yiyeceğe ihtiyacımız var.'),
  ('🏥', 'Tıbbi yardım gerekli, acil!'),
  ('🪨', 'Enkaz altındayım, ses duyabiliyorum.'),
  ('🚩', 'Tahliye noktasına ulaştım.'),
  ('⚠️', 'Bölge güvenli değil, dikkat edin!'),
];

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

    _packets.addAll(
      _mesh.storedPackets
          .where((p) => p.type != MeshPacket.typeLocation)
          .toList()
          .reversed,
    );

    _packetSub = _mesh.packetStream.listen((packet) {
      if (!mounted || packet.type == MeshPacket.typeLocation) return;
      setState(() {
        final idx = _packets.indexWhere((p) => p.id == packet.id);
        if (idx != -1) {
          _packets[idx] = packet;
        } else {
          _packets.add(packet);
        }
      });
      _scrollToBottom();
    });

    _peersSub = _mesh.peersStream.listen((peers) {
      if (!mounted) return;
      setState(() => _peers = peers);
    });

    // Prompt for display name on first launch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !UserService().hasName) {
        _editDisplayName();
      }
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

  Future<void> _editDisplayName() async {
    final ctrl = TextEditingController(text: UserService().displayName);
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: UserService().hasName,
      builder: (ctx) {
        String? errorText;
        return PopScope(
          canPop: UserService().hasName,
          child: StatefulBuilder(
            builder: (context, setS) {
              void submit() {
                final v = ctrl.text.trim();
                if (v.isEmpty) {
                  setS(() => errorText = 'İsim boş olamaz');
                  return;
                }
                Navigator.pop(ctx, v);
              }

              return AlertDialog(
                title: const Text('Görünen Adınız'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Bu isim yakındaki cihazlara gösterilir.'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ctrl,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'İsim',
                        hintText: 'Adınızı girin',
                        errorText: errorText,
                      ),
                      onSubmitted: (_) => submit(),
                    ),
                  ],
                ),
                actions: [
                  if (UserService().hasName)
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('İptal'),
                    ),
                  FilledButton(onPressed: submit, child: const Text('Kaydet')),
                ],
              );
            },
          ),
        );
      },
    );
    ctrl.dispose();
    if (!mounted || name == null || name.isEmpty) return;
    await UserService().saveName(name);
    _mesh.setDisplayName(name);
    setState(() {});
  }

  void _showQuickPresets() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Hızlı Mesajlar',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: _textDark,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Hazır acil durum mesajları',
              style: TextStyle(fontSize: 12, color: _textMid),
            ),
            const SizedBox(height: 10),
            ...List.generate(_presets.length, (i) {
              final (emoji, text) = _presets[i];
              return InkWell(
                onTap: () {
                  Navigator.pop(context);
                  _mesh.sendPacket(jsonEncode({'text': text}));
                },
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                  child: Row(
                    children: [
                      Text(emoji,
                          style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          text,
                          style: const TextStyle(
                            fontSize: 14,
                            color: _textDark,
                            height: 1.3,
                          ),
                        ),
                      ),
                      const Icon(Icons.send_rounded,
                          size: 15, color: _textLight),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _StatusBanner(
            displayName: UserService().displayName,
            deviceId: _mesh.deviceId,
            peers: _peers,
            peerNames: _mesh.peerNames,
            onReconnect: _mesh.restart,
            onEditName: _editDisplayName,
          ),
          Expanded(child: _buildFeed()),
          _ChatInput(
            controller: _msgCtrl,
            onSend: _sendMessage,
            onQuickPresets: _showQuickPresets,
          ),
          _DevStatsBox(mesh: _mesh),
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
          final isOwn = p.senderId == _mesh.deviceId;
          final label = isOwn
              ? (UserService().displayName.isEmpty
                  ? _mesh.deviceId
                  : UserService().displayName)
              : (p.senderName.isNotEmpty
                  ? p.senderName
                  : (_mesh.peerNames[p.senderId] ?? p.senderId));
          return _MessageBubble(
            packet: p,
            isOwn: isOwn,
            senderLabel: label,
          );
        }
        return _IncidentCard(packet: p, peerNames: _mesh.peerNames);
      },
    );
  }
}

// ── Status banner ─────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.displayName,
    required this.deviceId,
    required this.peers,
    required this.peerNames,
    required this.onReconnect,
    required this.onEditName,
  });

  final String displayName;
  final String deviceId;
  final Set<String> peers;
  final Map<String, String> peerNames;
  final VoidCallback onReconnect;
  final VoidCallback onEditName;

  @override
  Widget build(BuildContext context) {
    final connected = peers.isNotEmpty;
    final nameLabel = displayName.isNotEmpty ? displayName : deviceId;

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Own name chip — tappable to edit
          GestureDetector(
            onTap: onEditName,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_rounded, size: 13, color: _primary),
                  const SizedBox(width: 5),
                  Text(
                    nameLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit_rounded, size: 10, color: _primary),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Peer status chip
          Expanded(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: connected
                    ? const Color(0xFFECFDF5)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: connected
                      ? const Color(0xFF6EE7B7)
                      : Colors.grey.shade300,
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
                      _peerChipLabel(connected, peers, peerNames),
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

  String _peerChipLabel(
    bool connected,
    Set<String> peers,
    Map<String, String> peerNames,
  ) {
    if (!connected) return 'Taranıyor…';
    // Show names if we have them and count is small enough to fit.
    if (peers.length <= 3) {
      final names = peers
          .map((id) => peerNames.values.isNotEmpty
              ? (peerNames.entries
                      .where((e) => e.key == id)
                      .map((e) => e.value)
                      .firstOrNull ??
                  id.substring(0, 4))
              : id.substring(0, 4))
          .join(', ');
      return names;
    }
    return '${peers.length} cihaz bağlı';
  }
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.packet,
    required this.isOwn,
    required this.senderLabel,
  });

  final MeshPacket packet;
  final bool isOwn;
  final String senderLabel;

  @override
  Widget build(BuildContext context) {
    final data = jsonDecode(packet.payload) as Map<String, dynamic>;
    final text = (data['text'] as String?) ?? packet.payload;
    final time = DateTime.fromMillisecondsSinceEpoch(packet.timestamp);
    final timeStr = '${time.hour}:${time.minute.toString().padLeft(2, '0')}';

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
                senderLabel.isNotEmpty
                    ? senderLabel.substring(0, 1).toUpperCase()
                    : '?',
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                border:
                    isOwn ? null : Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: isOwn
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (!isOwn) ...[
                    Text(
                      senderLabel,
                      style: const TextStyle(
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (packet.hops > 0) ...[
                        Icon(
                          Icons.compare_arrows_rounded,
                          size: 9,
                          color: isOwn
                              ? _onPrimary.withValues(alpha: 0.5)
                              : _textLight,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${packet.hops}',
                          style: TextStyle(
                            fontSize: 9,
                            color: isOwn
                                ? _onPrimary.withValues(alpha: 0.5)
                                : _textLight,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
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
  const _IncidentCard({required this.packet, required this.peerNames});
  final MeshPacket packet;
  final Map<String, String> peerNames;

  @override
  Widget build(BuildContext context) {
    final data = jsonDecode(packet.payload) as Map<String, dynamic>;
    final note = (data['note'] as String?) ?? '';
    final time = DateTime.fromMillisecondsSinceEpoch(packet.timestamp);
    final timeStr = '${time.hour}:${time.minute.toString().padLeft(2, '0')}';

    final (label, icon, accent) = switch (packet.type) {
      MeshPacket.typeSOS => ('YARDIM ÇAĞRISI', Icons.sos_rounded, _colorSOS),
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

    final senderLabel = packet.senderName.isNotEmpty
        ? packet.senderName
        : (peerNames[packet.senderId] ?? packet.senderId);

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
              Container(width: 4, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                                color: _textLight, fontSize: 11),
                          ),
                        ],
                      ),
                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Text(
                          note,
                          style: const TextStyle(
                              color: _textDark, fontSize: 14, height: 1.4),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.person_outline_rounded,
                              size: 12, color: _textLight),
                          const SizedBox(width: 3),
                          Text(
                            senderLabel,
                            style: const TextStyle(
                                color: _textLight,
                                fontSize: 10,
                                fontFamily: 'monospace'),
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
  const _ChatInput({
    required this.controller,
    required this.onSend,
    this.onQuickPresets,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onQuickPresets;

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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          // Quick presets button
          if (onQuickPresets != null)
            GestureDetector(
              onTap: onQuickPresets,
              child: Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: const Icon(Icons.bolt_rounded,
                    color: _primary, size: 20),
              ),
            ),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: const TextStyle(color: _textDark, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Ağa mesaj gönder…',
                hintStyle:
                    const TextStyle(color: _textLight, fontSize: 14),
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
                  borderSide:
                      const BorderSide(color: _primary, width: 1.5),
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
              child:
                  const Icon(Icons.send_rounded, color: _onPrimary, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dev stats box ─────────────────────────────────────────────────────────────

class _DevStatsBox extends StatefulWidget {
  const _DevStatsBox({required this.mesh});
  final MeshService mesh;

  @override
  State<_DevStatsBox> createState() => _DevStatsBoxState();
}

class _DevStatsBoxState extends State<_DevStatsBox> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _uptime() {
    final start = widget.mesh.sessionStart;
    if (start == null) return '—';
    final d = DateTime.now().difference(start);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '${h}h ${m}m ${s}s' : '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mesh;
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.developer_mode_rounded,
              size: 11, color: Color(0xFF475569)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${m.connectedPeerCount} peer  ·  ${m.messagesReceived} rx  ·  ${m.packetsRelayed} relayed  ·  ${m.totalConnections} conn  ·  ${_uptime()}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: Color(0xFF64748B),
                letterSpacing: 0.2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
