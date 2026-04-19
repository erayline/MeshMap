import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

// ─── Binary min-heap (A* open set) ───────────────────────────────────────────

class _MinHeap {
  final _d = <_ANode>[];

  void add(_ANode v) {
    _d.add(v);
    _up(_d.length - 1);
  }

  _ANode removeFirst() {
    final top = _d.first;
    final last = _d.removeLast();
    if (_d.isNotEmpty) {
      _d[0] = last;
      _down(0);
    }
    return top;
  }

  bool get isNotEmpty => _d.isNotEmpty;

  void _up(int i) {
    while (i > 0) {
      final p = (i - 1) ~/ 2;
      if (_d[p].f <= _d[i].f) break;
      final t = _d[p]; _d[p] = _d[i]; _d[i] = t;
      i = p;
    }
  }

  void _down(int i) {
    final n = _d.length;
    while (true) {
      int s = i;
      final l = 2 * i + 1, r = 2 * i + 2;
      if (l < n && _d[l].f < _d[s].f) { s = l; }
      if (r < n && _d[r].f < _d[s].f) { s = r; }
      if (s == i) break;
      final t = _d[s]; _d[s] = _d[i]; _d[i] = t;
      i = s;
    }
  }
}

// ─── Constants ────────────────────────────────────────────────────────────────

const int kGridW = 32;
const int kGridH = 72;
const double kCellPx = 14.0; // px per grid cell

// ─── Models ───────────────────────────────────────────────────────────────────

enum CellType { empty, road, building }

class Building {
  final int yearBuilt;
  final int heightFloors;
  final double danger;

  const Building({
    required this.yearBuilt,
    required this.heightFloors,
    required this.danger,
  });

  // age 65%, height 35%
  static double computeDanger(int year, int floors) {
    final age = ((2024 - year) / 74.0).clamp(0.0, 1.0);
    final ht = (floors / 20.0).clamp(0.0, 1.0);
    return (age * 0.65 + ht * 0.35).clamp(0.0, 1.0);
  }
}

class GridCell {
  final CellType type;
  final Building? building;
  double roadDanger = 0.0;

  GridCell._({required this.type, this.building});

  factory GridCell.empty() => GridCell._(type: CellType.empty);
  factory GridCell.road() => GridCell._(type: CellType.road);
  factory GridCell.building(Building b) =>
      GridCell._(type: CellType.building, building: b);
}

class SafeZone {
  final math.Point<int> pos;
  final String name;
  const SafeZone({required this.pos, required this.name});
}

enum PathDangerLevel { safe, moderate, dangerous }

class PathCell {
  final math.Point<int> pos;
  final PathDangerLevel danger;
  const PathCell({required this.pos, required this.danger});
}

// ─── Grid Generation ──────────────────────────────────────────────────────────

List<List<GridCell>> buildGrid() {
  final rng = math.Random(42);
  final grid = List.generate(kGridH, (_) => List.generate(kGridW, (_) => GridCell.empty()));
  _placeRoads(grid);
  _placeBuildings(grid, rng);
  _computeRoadDanger(grid);
  return grid;
}

void _placeRoads(List<List<GridCell>> grid) {
  // ── Primary horizontal arteries ──────────────────────────────────────────
  for (final r in [0, 10, 20, 30, 40, 50, 60, 71]) {
    final row = r.clamp(0, kGridH - 1);
    for (int c = 0; c < kGridW; c++) { grid[row][c] = GridCell.road(); }
  }

  // ── Primary vertical arteries ─────────────────────────────────────────────
  for (final c in [0, 8, 16, 24, 31]) {
    final col = c.clamp(0, kGridW - 1);
    for (int r = 0; r < kGridH; r++) { grid[r][col] = GridCell.road(); }
  }

  // ── Secondary horizontal segments (~70% kept, avoids monotony) ───────────
  const hSec = [5, 15, 25, 35, 45, 55, 65];
  const hSpans = [(0, 8), (8, 16), (16, 24), (24, 31)];
  for (final row in hSec) {
    for (int si = 0; si < hSpans.length; si++) {
      if ((row * 7 + si * 3) % 10 < 3) { continue; }
      final (fc, tc) = hSpans[si];
      for (int c = fc; c <= tc.clamp(0, kGridW - 1); c++) {
        grid[row][c] = GridCell.road();
      }
    }
  }

  // ── Secondary vertical segments (~60% kept) ───────────────────────────────
  const vSec = [4, 12, 20, 28];
  const vSpans = [(0,10),(10,20),(20,30),(30,40),(40,50),(50,60),(60,71)];
  for (final col in vSec) {
    if (col >= kGridW) { continue; }
    for (int si = 0; si < vSpans.length; si++) {
      if ((vSpans[si].$1 * 11 + col * 5) % 10 < 4) { continue; }
      final (fr, tr) = vSpans[si];
      for (int r = fr; r <= tr.clamp(0, kGridH - 1); r++) {
        grid[r][col] = GridCell.road();
      }
    }
  }

  // ── Elliptical ring road — old city centre loop ───────────────────────────
  // Centre (col=16, row=36), semi-axes rx=8, ry=10
  _rasterizeEllipse(grid, cx: 16, cy: 36, rx: 8, ry: 10);
}

void _rasterizeEllipse(
  List<List<GridCell>> grid, {
  required int cx, required int cy,
  required int rx, required int ry,
}) {
  for (int dy = -ry; dy <= ry; dy++) {
    final row = cy + dy;
    if (row < 0 || row >= kGridH) { continue; }
    final t = 1.0 - (dy / ry) * (dy / ry);
    if (t < 0) { continue; }
    final xOff = rx * math.sqrt(t);
    for (final x in [(cx - xOff).round(), (cx + xOff).round()]) {
      grid[row][x.clamp(0, kGridW - 1)] = GridCell.road();
    }
  }
  for (int dx = -rx; dx <= rx; dx++) {
    final col = cx + dx;
    if (col < 0 || col >= kGridW) { continue; }
    final t = 1.0 - (dx / rx) * (dx / rx);
    if (t < 0) { continue; }
    final yOff = ry * math.sqrt(t);
    for (final y in [(cy - yOff).round(), (cy + yOff).round()]) {
      grid[y.clamp(0, kGridH - 1)][col] = GridCell.road();
    }
  }
}

// ── Multi-cell building generation ───────────────────────────────────────────
// Each building is a rectangle of up to 5×4 cells sharing one Building object.
// Reference equality (identical building instance) is used to draw block borders.

void _placeBuildings(List<List<GridCell>> grid, math.Random rng) {
  final claimed = List.generate(kGridH, (_) => List.filled(kGridW, false));

  for (int row = 0; row < kGridH; row++) {
    for (int col = 0; col < kGridW; col++) {
      if (grid[row][col].type != CellType.empty || claimed[row][col]) { continue; }

      // ── How wide can we go from this cell? ────────────────────────────────
      int maxW = 0;
      while (col + maxW < kGridW &&
             grid[row][col + maxW].type == CellType.empty &&
             !claimed[row][col + maxW]) {
        maxW++;
      }
      if (maxW == 0) { continue; }

      // Desired dims: wider/taller toward centre (old dense blocks), smaller on outskirts
      final dist = math.sqrt(
        math.pow(col + maxW / 2.0 - kGridW / 2, 2) +
        math.pow(row - kGridH / 2.0, 2),
      );
      final maxDesiredW = dist < 12 ? 5 : dist < 22 ? 4 : 3;
      final maxDesiredH = dist < 12 ? 4 : dist < 22 ? 3 : 2;

      final w = math.min(maxW, 1 + rng.nextInt(maxDesiredW));
      final desiredH = 1 + rng.nextInt(maxDesiredH);

      // ── How tall can we go with that width? ───────────────────────────────
      int h = 0;
      for (int dr = 0; dr < desiredH; dr++) {
        final r = row + dr;
        if (r >= kGridH) { break; }
        bool ok = true;
        for (int dc = 0; dc < w; dc++) {
          if (grid[r][col + dc].type != CellType.empty || claimed[r][col + dc]) {
            ok = false;
            break;
          }
        }
        if (!ok) { break; }
        h++;
      }
      if (h == 0) { continue; }

      // ── Claim cells ───────────────────────────────────────────────────────
      final cx = col + w / 2.0;
      final cy = row + h / 2.0;
      final d = math.sqrt(
        math.pow(cx - kGridW / 2, 2) + math.pow(cy - kGridH / 2, 2),
      );

      // Building probability (denser near centre)
      final prob = d < 10 ? 0.92 : d < 22 ? 0.82 : 0.65;
      if (rng.nextDouble() > prob) {
        // Open space / plaza — claim to avoid re-scan
        for (int dr = 0; dr < h; dr++) {
          for (int dc = 0; dc < w; dc++) {
            claimed[row + dr][col + dc] = true;
          }
        }
        continue;
      }

      int minY, maxY, minF, maxF;
      if (d < 10) {
        minY = 1950; maxY = 1988; minF = 5; maxF = 20;
      } else if (d < 22) {
        minY = 1965; maxY = 2005; minF = 2; maxF = 12;
      } else {
        minY = 1980; maxY = 2020; minF = 1; maxF = 5;
      }

      final year = minY + rng.nextInt(maxY - minY + 1);
      final floors = minF + rng.nextInt(maxF - minF + 1);
      // One shared Building object → reference equality identifies block in painter
      final building = Building(
        yearBuilt: year,
        heightFloors: floors,
        danger: Building.computeDanger(year, floors),
      );

      for (int dr = 0; dr < h; dr++) {
        for (int dc = 0; dc < w; dc++) {
          grid[row + dr][col + dc] = GridCell.building(building);
          claimed[row + dr][col + dc] = true;
        }
      }
    }
  }
}

void _computeRoadDanger(List<List<GridCell>> grid) {
  for (int row = 0; row < kGridH; row++) {
    for (int col = 0; col < kGridW; col++) {
      if (grid[row][col].type != CellType.road) { continue; }
      double sum = 0;
      int n = 0;
      for (int dr = -1; dr <= 1; dr++) {
        for (int dc = -1; dc <= 1; dc++) {
          final r = row + dr, c = col + dc;
          if (r < 0 || r >= kGridH || c < 0 || c >= kGridW) { continue; }
          final b = grid[r][c].building;
          if (b != null) { sum += b.danger; n++; }
        }
      }
      grid[row][col].roadDanger = n > 0 ? sum / n : 0.0;
    }
  }
}

// ─── Pathfinding ──────────────────────────────────────────────────────────────

math.Point<int>? snapToRoad(List<List<GridCell>> grid, int col, int row) {
  final start = math.Point(col.clamp(0, kGridW - 1), row.clamp(0, kGridH - 1));
  if (grid[start.y][start.x].type == CellType.road) { return start; }

  final queue = Queue<math.Point<int>>()..add(start);
  final seen = <math.Point<int>>{start};

  while (queue.isNotEmpty) {
    final p = queue.removeFirst();
    for (final d in const [
      math.Point(-1, 0), math.Point(1, 0),
      math.Point(0, -1), math.Point(0, 1),
    ]) {
      final np = math.Point(p.x + d.x, p.y + d.y);
      if (seen.contains(np) || np.x < 0 || np.x >= kGridW || np.y < 0 || np.y >= kGridH) {
        continue;
      }
      seen.add(np);
      if (grid[np.y][np.x].type == CellType.road) { return np; }
      queue.add(np);
    }
  }
  return null;
}

class _ANode implements Comparable<_ANode> {
  final math.Point<int> pos;
  final double f;
  const _ANode(this.pos, this.f);
  @override
  int compareTo(_ANode o) => f.compareTo(o.f);
}

// Danger multiplier: aggressively penalises roads near dangerous buildings
// so A* takes longer-but-safer detours around the dangerous city centre.
const _dangerMul = 18.0;

List<math.Point<int>>? aStar(
  List<List<GridCell>> grid,
  math.Point<int> start,
  math.Point<int> goal,
) {
  final pq = _MinHeap();
  final g = <math.Point<int>, double>{start: 0.0};
  final came = <math.Point<int>, math.Point<int>>{};
  final closed = <math.Point<int>>{};

  pq.add(_ANode(start, _h(start, goal)));

  while (pq.isNotEmpty) {
    final cur = pq.removeFirst().pos;
    if (cur == goal) { return _buildPath(came, cur); }
    if (closed.contains(cur)) { continue; }
    closed.add(cur);

    for (final d in const [
      math.Point(-1, 0), math.Point(1, 0),
      math.Point(0, -1), math.Point(0, 1),
    ]) {
      final n = math.Point(cur.x + d.x, cur.y + d.y);
      if (n.x < 0 || n.x >= kGridW || n.y < 0 || n.y >= kGridH) { continue; }
      if (grid[n.y][n.x].type != CellType.road || closed.contains(n)) { continue; }

      final moveCost = 1.0 + grid[n.y][n.x].roadDanger * _dangerMul;
      final ng = (g[cur] ?? double.infinity) + moveCost;
      if (ng < (g[n] ?? double.infinity)) {
        g[n] = ng;
        came[n] = cur;
        pq.add(_ANode(n, ng + _h(n, goal)));
      }
    }
  }
  return null;
}

double _h(math.Point<int> a, math.Point<int> b) =>
    ((a.x - b.x).abs() + (a.y - b.y).abs()).toDouble();

List<math.Point<int>> _buildPath(
  Map<math.Point<int>, math.Point<int>> came,
  math.Point<int> end,
) {
  final path = <math.Point<int>>[end];
  var cur = end;
  while (came.containsKey(cur)) {
    cur = came[cur]!;
    path.add(cur);
  }
  return path.reversed.toList();
}

List<PathCell> toPathCells(List<math.Point<int>> path, List<List<GridCell>> grid) =>
    path.map((p) {
      final d = grid[p.y][p.x].roadDanger;
      return PathCell(
        pos: p,
        danger: d < 0.3
            ? PathDangerLevel.safe
            : d < 0.58
                ? PathDangerLevel.moderate
                : PathDangerLevel.dangerous,
      );
    }).toList();

// ─── Screen ───────────────────────────────────────────────────────────────────

class GridMapScreen extends StatefulWidget {
  const GridMapScreen({super.key});

  @override
  State<GridMapScreen> createState() => _GridMapScreenState();
}

class _GridMapScreenState extends State<GridMapScreen> {
  late final List<List<GridCell>> _grid;
  late final math.Point<int> _userPos;
  late final List<SafeZone> _safeZones;

  int _targetIdx = 0;
  List<PathCell>? _path;
  bool _hasDanger = false;
  bool _warningVisible = true;

  @override
  void initState() {
    super.initState();
    _grid = buildGrid();

    // User is in the southwest outskirts — newer buildings, low danger.
    // Primary road intersection col=8, row=60.
    _userPos = snapToRoad(_grid, 8, 60) ?? const math.Point(8, 60);

    _safeZones = [
      SafeZone(
        pos: snapToRoad(_grid, 0, 0) ?? const math.Point(0, 0),
        name: 'Kuzey Toplanma Alanı',
      ),
      SafeZone(
        pos: snapToRoad(_grid, 31, 10) ?? const math.Point(31, 10),
        name: 'Doğu Hastane Girişi',
      ),
      SafeZone(
        pos: snapToRoad(_grid, 24, 71) ?? const math.Point(24, 71),
        name: 'Güney İstasyon Parkı',
      ),
    ];

    _computePath();
  }

  void _computePath() {
    final raw = aStar(_grid, _userPos, _safeZones[_targetIdx].pos);
    if (raw == null) {
      setState(() => _path = null);
      return;
    }
    final cells = toPathCells(raw, _grid);
    setState(() {
      _path = cells;
      _hasDanger = cells.any((c) => c.danger == PathDangerLevel.dangerous);
      _warningVisible = _hasDanger;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tahliye Haritası'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Açıklama',
            onPressed: _showLegend,
          ),
        ],
      ),
      body: Column(
        children: [
          _ZoneBar(
            zones: _safeZones,
            selected: _targetIdx,
            onSelect: (i) { setState(() => _targetIdx = i); _computePath(); },
          ),
          if (_hasDanger && _warningVisible)
            _WarningBanner(onDismiss: () => setState(() => _warningVisible = false)),
          Expanded(
            child: InteractiveViewer(
              minScale: 0.35,
              maxScale: 6.0,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Center(
                  child: CustomPaint(
                    size: Size(kGridW * kCellPx, kGridH * kCellPx),
                    painter: _GridPainter(
                      grid: _grid,
                      path: _path,
                      userPos: _userPos,
                      safeZones: _safeZones,
                      targetIdx: _targetIdx,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const _LegendBar(),
        ],
      ),
    );
  }

  void _showLegend() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Harita Açıklaması'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Binalar', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              _LegendRow(color: Color(0xFF2E7D32), label: 'Güvenli bina', sub: '(2000+ inşaat, alçak)'),
              _LegendRow(color: Color(0xFFF9A825), label: 'Orta risk', sub: '(1975-2000 arası)'),
              _LegendRow(color: Color(0xFFE64A19), label: 'Yüksek risk', sub: '(1960-1975, yüksek kat)'),
              _LegendRow(color: Color(0xFFB71C1C), label: 'Çok tehlikeli', sub: '(eski & çok yüksek kat)'),
              Divider(),
              Text('Tahliye Yolu', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              _LegendRow(color: Colors.green, label: 'Güvenli yol', sub: ''),
              _LegendRow(color: Colors.yellow, label: 'Dikkatli ol', sub: ''),
              _LegendRow(color: Colors.red, label: 'Tehlikeli yol (!)', sub: 'riskli binalar yakın'),
              Divider(),
              Text('İşaretler', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              _LegendRow(color: Colors.blue, label: 'Konumunuz', sub: ''),
              _LegendRow(color: Color(0xFF00E676), label: 'Seçili güvenli alan', sub: ''),
              _LegendRow(color: Colors.green, label: 'Diğer güvenli alanlar', sub: ''),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam')),
        ],
      ),
    );
  }
}

// ─── Sub-Widgets ──────────────────────────────────────────────────────────────

class _ZoneBar extends StatelessWidget {
  final List<SafeZone> zones;
  final int selected;
  final void Function(int) onSelect;
  const _ZoneBar({required this.zones, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.grey.shade900,
      child: Row(
        children: [
          const Icon(Icons.shield, color: Colors.green, size: 14),
          const SizedBox(width: 6),
          const Text('Hedef:', style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(zones.length, (i) {
                  final sel = i == selected;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => onSelect(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: sel ? Colors.green : Colors.grey.shade700,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          zones[i].name,
                          style: TextStyle(
                            color: sel ? Colors.black : Colors.white,
                            fontSize: 11,
                            fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final VoidCallback onDismiss;
  const _WarningBanner({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: Colors.red.shade900,
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.yellow, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Uyarı: En güvenli yol bazı riskli bölgelerden geçiyor. '
              'Kırmızı bölgelerde hızlı ilerleyin.',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close, color: Colors.white70, size: 16),
          ),
        ],
      ),
    );
  }
}

class _LegendBar extends StatelessWidget {
  const _LegendBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      color: Colors.grey.shade900,
      child: const Wrap(
        spacing: 10,
        runSpacing: 4,
        children: [
          _LegendDot(color: Color(0xFF2E7D32), label: 'Güvenli bina'),
          _LegendDot(color: Color(0xFFF9A825), label: 'Orta risk'),
          _LegendDot(color: Color(0xFFB71C1C), label: 'Tehlikeli bina'),
          _LegendDot(color: Colors.green, label: 'Yol: güvenli'),
          _LegendDot(color: Colors.yellow, label: 'Yol: dikkat'),
          _LegendDot(color: Colors.red, label: 'Yol: tehlike!'),
          _LegendDot(color: Colors.blue, label: 'Konum'),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 9)),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final String sub;
  const _LegendRow({required this.color, required this.label, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13)),
          if (sub.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(sub, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ],
      ),
    );
  }
}

// ─── Custom Painter ───────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  final List<List<GridCell>> grid;
  final List<PathCell>? path;
  final math.Point<int> userPos;
  final List<SafeZone> safeZones;
  final int targetIdx;

  const _GridPainter({
    required this.grid,
    required this.path,
    required this.userPos,
    required this.safeZones,
    required this.targetIdx,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / kGridW;
    final ch = size.height / kGridH;

    final fill = Paint();

    // ── 1. Fill every cell ───────────────────────────────────────────────────
    for (int row = 0; row < kGridH; row++) {
      for (int col = 0; col < kGridW; col++) {
        final cell = grid[row][col];
        fill.color = switch (cell.type) {
          CellType.empty    => const Color(0xFF1A3A0A), // dark park
          CellType.road     => _roadColor(cell.roadDanger),
          CellType.building => _buildingColor(cell.building!.danger),
        };
        canvas.drawRect(Rect.fromLTWH(col * cw, row * ch, cw, ch), fill);
      }
    }

    // ── 2. Draw building block borders ───────────────────────────────────────
    // A border is drawn on each side of a building cell where the neighbour
    // belongs to a DIFFERENT building (or is road/empty/boundary).
    // Cells sharing the same Building instance form one visible block.
    final border = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke;

    for (int row = 0; row < kGridH; row++) {
      for (int col = 0; col < kGridW; col++) {
        final cell = grid[row][col];
        if (cell.type != CellType.building) { continue; }
        final b = cell.building;
        final x = col * cw, y = row * ch;

        // Left
        if (col == 0 || grid[row][col - 1].building != b) {
          canvas.drawLine(Offset(x, y), Offset(x, y + ch), border);
        }
        // Top
        if (row == 0 || grid[row - 1][col].building != b) {
          canvas.drawLine(Offset(x, y), Offset(x + cw, y), border);
        }
        // Right
        if (col == kGridW - 1 || grid[row][col + 1].building != b) {
          canvas.drawLine(Offset(x + cw, y), Offset(x + cw, y + ch), border);
        }
        // Bottom
        if (row == kGridH - 1 || grid[row + 1][col].building != b) {
          canvas.drawLine(Offset(x, y + ch), Offset(x + cw, y + ch), border);
        }
      }
    }

    // ── 3. Draw evacuation path ──────────────────────────────────────────────
    if (path != null) {
      final pFill = Paint();
      for (final pc in path!) {
        pFill.color = switch (pc.danger) {
          PathDangerLevel.safe      => Colors.green.withValues(alpha: 0.88),
          PathDangerLevel.moderate  => Colors.yellow.withValues(alpha: 0.88),
          PathDangerLevel.dangerous => Colors.red.withValues(alpha: 0.88),
        };
        final x = pc.pos.x * cw, y = pc.pos.y * ch;
        canvas.drawRect(
          Rect.fromLTWH(x + cw * 0.18, y + ch * 0.18, cw * 0.64, ch * 0.64),
          pFill,
        );

        // Warning "!" on dangerous cells (visible at normal zoom)
        if (pc.danger == PathDangerLevel.dangerous && cw >= 6) {
          final tp = TextPainter(
            text: TextSpan(
              text: '!',
              style: TextStyle(
                color: Colors.yellow,
                fontSize: (cw * 0.58).clamp(5.0, 12.0),
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(x + (cw - tp.width) / 2, y + (ch - tp.height) / 2));
        }
      }
    }

    // ── 4. Safe zone markers ──────────────────────────────────────────────────
    final szFill = Paint();
    final cross = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < safeZones.length; i++) {
      final p = safeZones[i].pos;
      final cx = p.x * cw + cw / 2;
      final cy = p.y * ch + ch / 2;
      final r = cw * 1.2;
      szFill.color = i == targetIdx ? const Color(0xFF00E676) : const Color(0xFF388E3C);
      canvas.drawCircle(Offset(cx, cy), r, szFill);
      canvas.drawLine(Offset(cx, cy - r * 0.55), Offset(cx, cy + r * 0.55), cross);
      canvas.drawLine(Offset(cx - r * 0.55, cy), Offset(cx + r * 0.55, cy), cross);
    }

    // ── 5. User position marker ───────────────────────────────────────────────
    final ux = userPos.x * cw + cw / 2;
    final uy = userPos.y * ch + ch / 2;
    final ur = cw * 1.1;
    canvas.drawCircle(Offset(ux, uy), ur, Paint()..color = Colors.blue);
    canvas.drawCircle(
      Offset(ux, uy), ur,
      Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.6,
    );
    canvas.drawCircle(Offset(ux, uy), ur * 0.38, Paint()..color = Colors.white);
  }

  Color _buildingColor(double danger) {
    if (danger < 0.25) { return const Color(0xFF2E7D32); }  // dark green — safe
    if (danger < 0.50) { return const Color(0xFFF9A825); }  // amber — moderate
    if (danger < 0.72) { return const Color(0xFFE64A19); }  // deep orange — high
    return const Color(0xFFB71C1C);                          // dark red — very dangerous
  }

  Color _roadColor(double danger) {
    if (danger < 0.3) { return const Color(0xFF4A5568); }   // slate (safe corridor)
    if (danger < 0.6) { return const Color(0xFF6B5545); }   // warm brown (moderate)
    return const Color(0xFF6B3939);                          // reddish dark (danger)
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.path != path || old.targetIdx != targetIdx;
}
