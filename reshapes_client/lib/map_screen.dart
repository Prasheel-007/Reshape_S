import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'; // For mouse buttons
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:math' as math;

enum MapMode { satellite, cyberpunk, industrial }

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  LatLng _myLocation = const LatLng(17.4435, 78.3772);

  List<List<int>> _grid = [];
  LatLng? _gridOrigin;
  bool _isLoading = false;

  bool _showSimulationLayer = true;
  MapMode _currentMode = MapMode.satellite;
  bool _isConstructionMode = false;

  int _score = 0;
  Map<String, dynamic> _metrics = {"pollution": 0, "budget": 0};
  bool _hasData = false;

  // 🖱️ MULTI-SELECTION STATE (The Fix)
  // Instead of one point, we store a SET of points.
  final Set<math.Point<int>> _selectedCells = {};

  double _rotation = 0.0;

  Future<void> _getMyLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _myLocation = LatLng(position.latitude, position.longitude);
    });
    _mapController.move(_myLocation, 17.0);
    Future.delayed(const Duration(milliseconds: 500), () {
      _fetchRealWorldChunk(_myLocation);
    });
  }

  Future<void> _fetchRealWorldChunk(LatLng targetCenter) async {
    setState(() => _isLoading = true);
    _selectedCells.clear(); // Clear selection on reload

    try {
      String serverUrl = "http://127.0.0.1:5000";
      if (defaultTargetPlatform == TargetPlatform.android && !kIsWeb) {
        // serverUrl = "http://10.0.2.2:5000";
      }

      final url = Uri.parse('$serverUrl/api/v2/get_chunk?lat=${targetCenter.latitude}&lon=${targetCenter.longitude}');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            List<dynamic> rawGrid = data['grid'];
            _grid = rawGrid.map((row) => List<int>.from(row)).toList();
            _gridOrigin = targetCenter;
            _updateMetrics(data['score'], data['metrics']);
            _showSimulationLayer = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Map Loaded.')));
        }
      }
    } catch (e) {
      print("Error: $e");
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _updateMetrics(int score, Map<String, dynamic> metrics) {
    setState(() {
      _score = score;
      _metrics = metrics;
      _hasData = true;
    });
  }

  // 🖱️ MOUSE INPUT HANDLER (Left vs Right Click)
  void _handlePointerInput(PointerEvent event) {
    if (_grid.isEmpty || _gridOrigin == null || !_isConstructionMode) return;

    // Convert Screen Pixels -> LatLng -> Grid Index
    final LatLng? point = _mapController.camera.pointToLatLng(math.Point(event.localPosition.dx, event.localPosition.dy));
    if (point == null) return;

    double tileMeters = 10.0;
    int gridSize = 60;
    double totalMeters = gridSize * tileMeters;

    double latDegrees = totalMeters / 111000;
    double startLat = _gridOrigin!.latitude - (latDegrees / 2);
    double stepLat = latDegrees / gridSize;

    double lonDegrees = totalMeters / (111000 * math.cos(_gridOrigin!.latitude * math.pi / 180));
    double startLon = _gridOrigin!.longitude - (lonDegrees / 2);
    double stepLon = lonDegrees / gridSize;

    int x = ((point.latitude - startLat) / stepLat).floor();
    int y = ((point.longitude - startLon) / stepLon).floor();

    if (x >= 0 && x < gridSize && y >= 0 && y < gridSize) {
      setState(() {
        var gridPoint = math.Point(x, y);

        // 🖱️ CHECK BUTTONS
        // kPrimaryButton = Left Click (Select)
        // kSecondaryButton = Right Click (Deselect)
        if (event.buttons == kPrimaryButton) {
          _selectedCells.add(gridPoint);
        } else if (event.buttons == kSecondaryButton) {
          _selectedCells.remove(gridPoint);
        }
      });
    }
  }

  void _modifyGrid(int newType) {
    if (_selectedCells.isEmpty) return;

    setState(() {
      // Loop through ALL selected cells
      for (var cell in _selectedCells) {
        int r = cell.x;
        int c = cell.y;
        if (r >= 0 && r < _grid.length && c >= 0 && c < _grid[0].length) {
          _grid[r][c] = newType;
        }
      }

      // Refresh Grid
      _grid = List.from(_grid);

      // Clear selection after building?
      // User might want to build multiple things, but usually clearing is safer to avoid accidents.
      _selectedCells.clear();

      // Update Scores (Simulated)
      if (newType == 4) { // Park
        _score = (_score + 5).clamp(0, 100);
        _metrics['pollution'] = (_metrics['pollution'] - 50).clamp(0, 99999);
      } else if (newType == 1) { // Road
        _score = (_score - 2).clamp(0, 100);
      } else if (newType == 0) { // Demolish
        _score = (_score + 1).clamp(0, 100);
      }
    });
  }

  void _rotateMap(double degrees) {
    setState(() {
      _rotation = (_rotation + degrees) % 360;
    });
    _mapController.rotate(_rotation);
  }

  @override
  Widget build(BuildContext context) {
    Color appBarColor = Colors.blueGrey[900]!;
    Color accentColor = Colors.white;
    if (_currentMode == MapMode.cyberpunk) {
      appBarColor = Colors.black;
      accentColor = Colors.cyanAccent;
    } else if (_currentMode == MapMode.industrial) {
      appBarColor = Colors.brown[900]!;
      accentColor = Colors.orangeAccent;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_getModeTitle()),
        backgroundColor: appBarColor,
        foregroundColor: accentColor,
        actions: [
          IconButton(
            icon: Icon(_showSimulationLayer ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _showSimulationLayer = !_showSimulationLayer),
          ),
          IconButton(
            icon: Icon(_isConstructionMode ? Icons.build : Icons.build_outlined),
            color: _isConstructionMode ? accentColor : Colors.grey,
            onPressed: () {
              setState(() {
                _isConstructionMode = !_isConstructionMode;
                _selectedCells.clear(); // Clear on toggle
              });
            },
          ),
          PopupMenuButton<MapMode>(
            icon: const Icon(Icons.layers),
            onSelected: (MapMode item) => setState(() => _currentMode = item),
            itemBuilder: (BuildContext context) => <PopupMenuEntry<MapMode>>[
              const PopupMenuItem(value: MapMode.satellite, child: Text('Satellite (Reality)')),
              const PopupMenuItem(value: MapMode.cyberpunk, child: Text('Cyberpunk (Builder)')),
              const PopupMenuItem(value: MapMode.industrial, child: Text('Industrial (Heatmap)')),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _myLocation,
              initialZoom: 17.0,
              interactionOptions: InteractionOptions(
                flags: _isConstructionMode ? InteractiveFlag.none : InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: _currentMode == MapMode.satellite
                    ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
                    : 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.reshapel.reshapes_client',
              ),

              if (_showSimulationLayer && _grid.isNotEmpty && _gridOrigin != null)
                SizedBox.expand(
                  child: CustomPaint(
                    painter: City3DPainter(
                      grid: _grid,
                      gridOrigin: _gridOrigin!,
                      camera: _mapController.camera,
                      selectedCells: _selectedCells, // Pass the SET
                      mode: _currentMode,
                      isEditMode: _isConstructionMode,
                      rotation: _rotation,
                    ),
                  ),
                ),
            ],
          ),

          // 🖱️ RAW LISTENER (Captures Right Clicks & Drags)
          if (_isConstructionMode)
            Listener(
              onPointerDown: _handlePointerInput,
              onPointerMove: _handlePointerInput, // Dragging support!
              behavior: HitTestBehavior.translucent,
              child: Container(color: Colors.transparent),
            ),

          if (_hasData && _showSimulationLayer)
            Positioned(top: 20, left: 20, right: 20, child: _buildHUD(accentColor)),

          if (_selectedCells.isNotEmpty && _isConstructionMode)
            Positioned(bottom: 0, left: 0, right: 0, child: _buildCommandDeck(appBarColor, accentColor)),

          Positioned(
            right: 20, bottom: 180,
            child: Column(
              children: [
                FloatingActionButton.small(heroTag: "rot_l", backgroundColor: Colors.black54, child: const Icon(Icons.rotate_left, color: Colors.white), onPressed: () => _rotateMap(-45)),
                const SizedBox(height: 5),
                FloatingActionButton.small(heroTag: "rot_r", backgroundColor: Colors.black54, child: const Icon(Icons.rotate_right, color: Colors.white), onPressed: () => _rotateMap(45)),
                const SizedBox(height: 5),
                FloatingActionButton.small(heroTag: "rot_n", backgroundColor: Colors.black54, child: const Text("N", style: TextStyle(color:Colors.white)), onPressed: () {
                  _rotation = 0; _mapController.rotate(0); setState((){});
                }),
              ],
            ),
          ),

          if (_selectedCells.isEmpty)
            Positioned(
              bottom: 100, right: 20,
              child: FloatingActionButton(
                heroTag: "btn_dl",
                backgroundColor: accentColor,
                foregroundColor: Colors.black,
                child: const Icon(Icons.download),
                onPressed: () => _fetchRealWorldChunk(_mapController.camera.center),
              ),
            ),

          if (_isLoading)
            Container(color: Colors.black54, child: Center(child: CircularProgressIndicator(color: accentColor))),
        ],
      ),
      floatingActionButton: (_selectedCells.isEmpty) ? FloatingActionButton(
        heroTag: "btn_gps",
        backgroundColor: appBarColor,
        foregroundColor: Colors.white,
        onPressed: _getMyLocation,
        child: const Icon(Icons.my_location),
      ) : null,
    );
  }

  String _getModeTitle() {
    switch(_currentMode) {
      case MapMode.satellite: return "V6: Satellite Reality";
      case MapMode.cyberpunk: return "V6: Cyberpunk City";
      case MapMode.industrial: return "V6: Heatmap Analysis";
    }
  }

  Widget _buildHUD(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("SUSTAINABILITY", style: TextStyle(color: color, fontSize: 10)),
            Text("$_score/100", style: TextStyle(color: _score>70?Colors.green:Colors.orange, fontSize: 24, fontWeight: FontWeight.bold)),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text("POLLUTION: ${_metrics['pollution']}", style: const TextStyle(color: Colors.white, fontSize: 12)),
          ]),
        ],
      ),
    );
  }

  Widget _buildCommandDeck(Color bg, Color accent) {
    return Container(
      padding: const EdgeInsets.all(20),
      color: bg,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text("${_selectedCells.length} SECTORS SELECTED", style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          _buildBtn("DEMOLISH", Icons.delete, Colors.red, 0),
          const SizedBox(width:10),
          _buildBtn("PARK", Icons.park, Colors.green, 4),
          const SizedBox(width:10),
          _buildBtn("ROAD", Icons.edit_road, Colors.grey, 1),
          const SizedBox(width:10),
          _buildBtn("HOUSE", Icons.home, Colors.blue, 2),
        ]))
      ]),
    );
  }

  Widget _buildBtn(String l, IconData i, Color c, int t) {
    return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
            backgroundColor: c.withOpacity(0.2),
            foregroundColor: c,
            side: BorderSide(color: c, width: 1)
        ),
        onPressed: () => _modifyGrid(t), icon: Icon(i, size:16), label: Text(l)
    );
  }
}

class City3DPainter extends CustomPainter {
  final List<List<int>> grid;
  final LatLng gridOrigin;
  final MapCamera camera;
  final Set<math.Point<int>> selectedCells; // ✅ FIX: Now a Set
  final MapMode mode;
  final bool isEditMode;
  final double rotation;

  City3DPainter({
    required this.grid, required this.gridOrigin, required this.camera,
    required this.selectedCells, required this.mode, required this.isEditMode, required this.rotation
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    try {
      double tileMeters = 10.0;
      int gridSize = 60;
      double totalMeters = gridSize * tileMeters;

      double latDegrees = totalMeters / 111000;
      double lonDegrees = totalMeters / (111000 * math.cos(gridOrigin.latitude * math.pi / 180));
      double startLat = gridOrigin.latitude - (latDegrees / 2);
      double startLon = gridOrigin.longitude - (lonDegrees / 2);
      double stepLat = latDegrees / gridSize;
      double stepLon = lonDegrees / gridSize;

      double extrusionY = -25.0;

      for (int x = 0; x < grid.length; x++) {
        for (int y = 0; y < grid[x].length; y++) {
          int type = grid[x][y];

          if (type == 0 && !isEditMode) continue;

          double cellLat = startLat + (x * stepLat);
          double cellLon = startLon + (y * stepLon);
          var p1 = camera.latLngToScreenPoint(LatLng(cellLat, cellLon));
          var p2 = camera.latLngToScreenPoint(LatLng(cellLat + stepLat, cellLon + stepLon));

          if (!p1.x.isFinite || !p1.y.isFinite || !p2.x.isFinite || !p2.y.isFinite) continue;

          Rect baseRect = Rect.fromPoints(
              Offset(p1.x.toDouble(), p1.y.toDouble()),
              Offset(p2.x.toDouble(), p2.y.toDouble())
          );

          if (baseRect.right < 0 || baseRect.left > size.width || baseRect.bottom < 0 || baseRect.top > size.height) continue;

          // ✅ CHECK SET MEMBERSHIP
          bool isSel = selectedCells.contains(math.Point(x, y));
          _drawBuilding(canvas, baseRect, type, isSel, extrusionY);
        }
      }
    } catch (e) { }
  }

  void _drawBuilding(Canvas canvas, Rect base, int type, bool isSel, double maxH) {
    Color c = Colors.grey;
    double height = 0;

    if (mode == MapMode.cyberpunk) {
      if (type == 0) { c = Colors.white; height = 0; }
      else if (type == 1) { c = Colors.grey[800]!; height=0; }
      else if (type == 2) { c = Colors.cyan; height=0.4; }
      else if (type == 3) { c = Colors.deepOrange; height=1.0; }
      else if (type == 4) { c = Colors.greenAccent; height=0.1; }
    } else if (mode == MapMode.industrial) {
      if (type == 1) { c = Colors.amber.withOpacity(0.3); height=0.0; }
      else if (type == 2) { c = Colors.blueGrey.withOpacity(0.5); height=0.2; }
      else if (type == 3) { c = Colors.redAccent; height=1.2; }
      else if (type == 4) { c = Colors.greenAccent; height=0.2; }
      else { c = Colors.transparent; height=0.0; }
    } else {
      if (type == 0) { c = Colors.white; height = 0; }
      else if (type == 1) { c = Colors.white54; height=0; }
      else if (type == 2) { c = Colors.blue.withOpacity(0.5); height=0.3; }
      else if (type == 3) { c = Colors.red.withOpacity(0.5); height=0.8; }
      else if (type == 4) { c = Colors.green.withOpacity(0.5); height=0.0; }
    }

    if (isSel) { c = Colors.yellow; height = 0.5; }

    if (type == 0) {
      // High visibility selection for empty grids
      Paint wireframe = Paint()..style=PaintingStyle.stroke..color= isSel ? Colors.yellow : Colors.white.withOpacity(0.1)..strokeWidth= isSel ? 2 : 0.5;
      if (isSel) {
        // Fill selected empty grid so you see it
        canvas.drawRect(base, Paint()..color = Colors.yellow.withOpacity(0.3));
      }
      canvas.drawRect(base, wireframe);
      return;
    }

    double hPixels = maxH * height;

    Paint wallPaint = Paint()..style = PaintingStyle.fill..color = c.withOpacity(c.opacity * 0.5);
    Paint topPaint = Paint()..style = PaintingStyle.fill..color = c;
    Paint borderPaint = Paint()..style = PaintingStyle.stroke..color = c.withOpacity(1.0)..strokeWidth = 1.0;

    if (hPixels.abs() > 2) {
      ui.Path wallPath = ui.Path();
      wallPath.moveTo(base.left, base.bottom);
      wallPath.lineTo(base.right, base.bottom);
      wallPath.lineTo(base.right, base.bottom + hPixels);
      wallPath.lineTo(base.left, base.bottom + hPixels);
      wallPath.close();

      Rect roof = Rect.fromLTWH(base.left, base.top + hPixels, base.width, base.height);

      canvas.drawPath(wallPath, wallPaint);
      canvas.drawRect(roof, topPaint);
      canvas.drawRect(roof, borderPaint);

      canvas.drawLine(base.bottomLeft, roof.bottomLeft, borderPaint);
      canvas.drawLine(base.bottomRight, roof.bottomRight, borderPaint);

    } else {
      canvas.drawRect(base, topPaint);
      if (mode != MapMode.satellite) canvas.drawRect(base, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}