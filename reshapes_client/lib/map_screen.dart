import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:math' as math;

enum MapMode { satellite, holographic }

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

  math.Point<int>? _selectedGridCell;
  int _selectedTileType = 0;

  // --- 1. GET GPS LOCATION ---
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
    _fetchRealWorldChunk(_myLocation);
  }

  // --- 2. FETCH DATA ---
  Future<void> _fetchRealWorldChunk(LatLng targetCenter) async {
    setState(() => _isLoading = true);
    _selectedGridCell = null;

    try {
      String serverUrl = "http://127.0.0.1:5000";
      if (defaultTargetPlatform == TargetPlatform.android && !kIsWeb) {
        // serverUrl = "http://10.0.2.2:5000";
      }

      final url = Uri.parse('$serverUrl/api/v2/get_chunk?lat=${targetCenter.latitude}&lon=${targetCenter.longitude}');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          List<dynamic> rawGrid = data['grid'];
          _grid = rawGrid.map((row) => List<int>.from(row)).toList();
          _gridOrigin = targetCenter;
          _updateMetrics(data['score'], data['metrics']);
          _showSimulationLayer = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Holographic Grid Online')));
      }
    } catch (e) {
      print("Error: $e");
    }
    setState(() => _isLoading = false);
  }

  void _updateMetrics(int score, Map<String, dynamic> metrics) {
    setState(() {
      _score = score;
      _metrics = metrics;
      _hasData = true;
    });
  }

  // --- 3. INTERACTION HANDLER ---
  void _handleTap(TapPosition tapPos, LatLng point) {
    if (_grid.isEmpty || _gridOrigin == null || !_isConstructionMode) return;

    double tileMeters = 10.0;
    int gridSize = 60;
    double totalMeters = gridSize * tileMeters;

    double latDegrees = totalMeters / 111000;
    double lonDegrees = totalMeters / (111000 * math.cos(_gridOrigin!.latitude * math.pi / 180));

    double startLat = _gridOrigin!.latitude - (latDegrees / 2);
    double startLon = _gridOrigin!.longitude - (lonDegrees / 2);

    double stepLat = latDegrees / gridSize;
    double stepLon = lonDegrees / gridSize;

    int x = ((point.latitude - startLat) / stepLat).floor();
    int y = ((point.longitude - startLon) / stepLon).floor();

    if (x >= 0 && x < gridSize && y >= 0 && y < gridSize) {
      setState(() {
        _selectedGridCell = math.Point(x, y);
        _selectedTileType = _grid[x][y];
      });
    } else {
      setState(() => _selectedGridCell = null);
    }
  }

  // --- 4. EXECUTE EDIT ---
  void _modifyGrid(int newType) {
    if (_selectedGridCell == null) return;
    int r = _selectedGridCell!.x;
    int c = _selectedGridCell!.y;

    if (r < 0 || r >= _grid.length || c < 0 || c >= _grid[0].length) return;

    setState(() {
      _grid[r][c] = newType;
      _selectedTileType = newType;
      // Force repaint by creating new reference
      _grid = List.from(_grid);

      if (newType == 4) {
        _score = (_score + 5).clamp(0, 100);
        int p = _metrics['pollution'];
        _metrics['pollution'] = (p - 50).clamp(0, 99999);
      } else if (newType == 1) {
        _score = (_score - 2).clamp(0, 100);
      } else if (newType == 0) {
        _score = (_score + 1).clamp(0, 100);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isHolo = _currentMode == MapMode.holographic;

    return Scaffold(
      appBar: AppBar(
        title: Text(isHolo ? "V2: Holographic" : "V2: Satellite"),
        backgroundColor: isHolo ? Colors.black : Colors.blueGrey[900],
        foregroundColor: isHolo ? Colors.cyanAccent : Colors.white,
        actions: [
          IconButton(
            icon: Icon(_showSimulationLayer ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _showSimulationLayer = !_showSimulationLayer),
          ),
          IconButton(
            icon: Icon(_isConstructionMode ? Icons.build : Icons.build_outlined),
            color: _isConstructionMode ? (isHolo ? Colors.cyanAccent : Colors.orange) : Colors.grey,
            onPressed: () {
              setState(() {
                _isConstructionMode = !_isConstructionMode;
                if (!_isConstructionMode) _selectedGridCell = null;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_isConstructionMode ? "EDIT MODE: Tap grid to build" : "VIEW MODE: Drag map safely"))
              );
            },
          ),
          PopupMenuButton<MapMode>(
            icon: const Icon(Icons.layers),
            onSelected: (MapMode item) => setState(() => _currentMode = item),
            itemBuilder: (BuildContext context) => <PopupMenuEntry<MapMode>>[
              const PopupMenuItem<MapMode>(
                value: MapMode.satellite,
                child: Text('Satellite View'),
              ),
              const PopupMenuItem<MapMode>(
                value: MapMode.holographic,
                child: Text('Holographic View'),
              ),
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
              onTap: _handleTap,
            ),
            children: [
              TileLayer(
                urlTemplate: isHolo
                    ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: isHolo ? const ['a', 'b', 'c', 'd'] : const [],
                userAgentPackageName: 'com.reshapel.reshapes_client',
              ),

              if (_showSimulationLayer && _grid.isNotEmpty && _gridOrigin != null)
              // ✅ VISIBILITY FIX: SIZEDBOX.EXPAND
                SizedBox.expand(
                  child: CustomPaint(
                    painter: DualModePainter(
                      grid: _grid,
                      gridOrigin: _gridOrigin!,
                      camera: _mapController.camera,
                      selectedCell: _selectedGridCell,
                      isHolo: isHolo,
                      isEditMode: _isConstructionMode,
                    ),
                  ),
                ),
            ],
          ),

          if (_hasData && _showSimulationLayer)
            Positioned(
              top: 20, left: 20, right: 20,
              child: _buildHUD(isHolo),
            ),

          if (_selectedGridCell != null && _isConstructionMode)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: _buildCommandDeck(isHolo),
            ),

          if (_selectedGridCell == null)
            Positioned(
              bottom: 100, right: 20,
              child: FloatingActionButton(
                heroTag: "btn_download", // ✅ CRASH FIX
                backgroundColor: isHolo ? Colors.cyanAccent : Colors.orange,
                foregroundColor: Colors.black,
                child: const Icon(Icons.download),
                onPressed: () => _fetchRealWorldChunk(_mapController.camera.center),
              ),
            ),

          if (_isLoading)
            Container(
              color: Colors.black54,
              child: Center(child: CircularProgressIndicator(color: isHolo ? Colors.cyanAccent : Colors.orange)),
            ),
        ],
      ),
      floatingActionButton: (_selectedGridCell == null) ? FloatingActionButton(
        heroTag: "btn_gps", // ✅ CRASH FIX
        backgroundColor: isHolo ? Colors.grey[800] : Colors.blue,
        foregroundColor: Colors.white,
        onPressed: _getMyLocation,
        child: const Icon(Icons.my_location),
      ) : null,
    );
  }

  Widget _buildHUD(bool isHolo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        color: isHolo ? Colors.black.withOpacity(0.8) : Colors.white.withOpacity(0.9),
        border: isHolo ? Border.all(color: Colors.cyanAccent, width: 2) : null,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 10)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("SUSTAINABILITY", style: TextStyle(color: isHolo ? Colors.cyanAccent : Colors.grey, fontSize: 10)),
              Text("$_score/100", style: TextStyle(color: _score > 70 ? Colors.green : Colors.orange, fontSize: 24, fontWeight: FontWeight.bold)),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("POLLUTION: ${_metrics['pollution']}", style: TextStyle(color: isHolo ? Colors.white : Colors.black87, fontSize: 12)),
              Text("BUDGET: \$${_metrics['budget']}", style: TextStyle(color: isHolo ? Colors.white : Colors.black87, fontSize: 12)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildCommandDeck(bool isHolo) {
    Color accent = isHolo ? Colors.cyanAccent : Colors.blue;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isHolo ? Colors.black.withOpacity(0.95) : Colors.white,
        border: Border(top: BorderSide(color: accent, width: 3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.handyman, color: accent, size: 16),
              const SizedBox(width: 10),
              Text("SECTOR [${_selectedGridCell!.x}, ${_selectedGridCell!.y}] READY", style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 15),
          const Text("SELECT OPERATION:", style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildActionButton("DEMOLISH", Icons.delete_outline, Colors.redAccent, 0, isHolo),
                const SizedBox(width: 10),
                _buildActionButton("BUILD PARK", Icons.park, Colors.green, 4, isHolo),
                const SizedBox(width: 10),
                _buildActionButton("SOLAR ROAD", Icons.solar_power, Colors.amber, 1, isHolo),
                const SizedBox(width: 10),
                _buildActionButton("HOUSING", Icons.home, Colors.blue, 2, isHolo),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, int type, bool isHolo) {
    bool isActive = _selectedTileType == type;
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive ? color.withOpacity(0.3) : Colors.transparent,
        foregroundColor: color,
        side: BorderSide(color: color),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: () => _modifyGrid(type),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class DualModePainter extends CustomPainter {
  final List<List<int>> grid;
  final LatLng gridOrigin;
  final MapCamera camera;
  final math.Point<int>? selectedCell;
  final bool isHolo;
  final bool isEditMode;

  DualModePainter({
    required this.grid,
    required this.gridOrigin,
    required this.camera,
    this.selectedCell,
    required this.isHolo,
    required this.isEditMode
  });

  @override
  void paint(Canvas canvas, Size size) {
    double tileMeters = 10.0;
    int gridSize = 60;
    double totalMeters = gridSize * tileMeters;

    double latDegrees = totalMeters / 111000;
    double lonDegrees = totalMeters / (111000 * math.cos(gridOrigin.latitude * math.pi / 180));

    double startLat = gridOrigin.latitude - (latDegrees / 2);
    double startLon = gridOrigin.longitude - (lonDegrees / 2);
    double stepLat = latDegrees / gridSize;
    double stepLon = lonDegrees / gridSize;

    final Paint paintFill = Paint()..style = PaintingStyle.fill;
    final Paint paintBorder = Paint()..style = PaintingStyle.stroke;

    for (int x = 0; x < grid.length; x++) {
      for (int y = 0; y < grid[x].length; y++) {
        int type = grid[x][y];
        bool isSelected = (selectedCell != null && selectedCell!.x == x && selectedCell!.y == y);

        if (type == 0 && !isSelected && !isEditMode) continue;

        double cellLat = startLat + (x * stepLat);
        double cellLon = startLon + (y * stepLon);

        var p1Point = camera.latLngToScreenPoint(LatLng(cellLat, cellLon));
        var p2Point = camera.latLngToScreenPoint(LatLng(cellLat + stepLat, cellLon + stepLon));

        Offset p1 = Offset(p1Point.x.toDouble(), p1Point.y.toDouble());
        Offset p2 = Offset(p2Point.x.toDouble(), p2Point.y.toDouble());

        // Safety bounds check
        if (p1.dx > size.width || p2.dx < 0 || p1.dy > size.height || p2.dy < 0) continue;

        Rect rect = Rect.fromPoints(p1, p2);

        // Selection
        if (isSelected) {
          Color selColor = isHolo ? Colors.cyanAccent : Colors.blue;
          canvas.drawRect(rect, Paint()..color = selColor.withOpacity(0.5));
          canvas.drawRect(rect, Paint()..style=PaintingStyle.stroke..color=selColor..strokeWidth=3);
          continue;
        }

        Color baseColor;
        if (isHolo) {
          switch(type) {
            case 1: baseColor = Colors.white; break;
            case 2: baseColor = Colors.cyanAccent; break;
            case 3: baseColor = Colors.orangeAccent; break;
            case 4: baseColor = Colors.greenAccent; break;
            case 7: baseColor = Colors.blueAccent; break;
            default: baseColor = Colors.grey.withOpacity(0.1);
          }
        } else {
          switch(type) {
            case 1: baseColor = Colors.white70; break;
            case 2: baseColor = Colors.brown; break;
            case 3: baseColor = Colors.red[900]!; break;
            case 4: baseColor = Colors.lightGreenAccent[400]!; break;
            case 7: baseColor = Colors.blue; break;
            default: baseColor = Colors.white.withOpacity(0.1);
          }
        }

        if (isHolo) {
          if (type != 0) {
            canvas.drawRect(rect, paintFill..color = baseColor.withOpacity(0.15));
            canvas.drawRect(rect, paintBorder..color = baseColor.withOpacity(0.9)..strokeWidth = 1.5);
          } else if (isEditMode) {
            canvas.drawRect(rect, paintBorder..color = Colors.white.withOpacity(0.1)..strokeWidth = 0.5);
          }
        } else {
          if (type != 0) {
            canvas.drawRect(rect, paintFill..color = baseColor.withOpacity(0.6));
            // White border for satellite visibility
            canvas.drawRect(rect, paintBorder..color = Colors.white.withOpacity(0.5)..strokeWidth = 0.5);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}