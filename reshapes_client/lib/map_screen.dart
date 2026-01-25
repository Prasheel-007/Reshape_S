import 'dart:convert';
import 'package:flutter/foundation.dart'; // For kDebugMode
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  LatLng _center = const LatLng(17.4435, 78.3772); // Default: HITEC City

  // Data Storage
  List<List<int>> _grid = [];
  bool _isLoading = false;

  // 🎛️ LAYERS: The "Toggle" System
  bool _showSimulationLayer = true;

  // --- 1. GET GPS LOCATION ---
  Future<void> _getMyLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location services are disabled.')));
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _center = LatLng(position.latitude, position.longitude);
    });
    _mapController.move(_center, 16.0);

    // Auto-fetch data when location is found
    _fetchRealWorldChunk();
  }

  // --- 2. CONNECT TO PYTHON BACKEND ---
  Future<void> _fetchRealWorldChunk() async {
    setState(() => _isLoading = true);

    try {
      // 🧠 SMART URL SWITCHER
      // Use 10.0.2.2 for Android Emulator, localhost for Windows/Web
      String serverUrl = "http://127.0.0.1:5000";
      if (defaultTargetPlatform == TargetPlatform.android && !kIsWeb) {
        // Note: If using physical device via USB, use 'adb reverse' or your PC's local IP
      }

      final url = Uri.parse('$serverUrl/api/v2/get_chunk?lat=${_center.latitude}&lon=${_center.longitude}');
      print("🔌 Calling V2 Engine: $url");

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          List<dynamic> rawGrid = data['grid'];
          _grid = rawGrid.map((row) => List<int>.from(row)).toList();
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Real World Data Loaded!')));
      } else {
        print("❌ Server Error: ${response.statusCode}");
      }
    } catch (e) {
      print("Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connection Failed: $e')));
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("V2: Real World Engine"),
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
        actions: [
          // 🎛️ TOGGLE BUTTON: Show/Hide the Simulation Grid
          IconButton(
            icon: Icon(_showSimulationLayer ? Icons.layers : Icons.layers_clear),
            tooltip: "Toggle Simulation Layer",
            onPressed: () {
              setState(() {
                _showSimulationLayer = !_showSimulationLayer;
              });
            },
          )
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: _center, initialZoom: 16.0),
            children: [
              // LAYER 1: The Real Map (OpenStreetMap)
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.reshapel.reshapes_client',
              ),

              // LAYER 2: The Simulation Overlay (Custom Painter)
              // Only draws if the toggle is ON
              if (_showSimulationLayer && _grid.isNotEmpty)
                MobileLayerTransformer( // Ensures it scales when you pinch-zoom
                  child: CustomPaint(
                    painter: GridOverlayPainter(
                      grid: _grid,
                      center: _center,
                      zoom: _mapController.camera.zoom,
                    ),
                  ),
                ),

              // LAYER 3: User Location Pin
              MarkerLayer(
                markers: [
                  Marker(
                    point: _center,
                    width: 80, height: 80,
                    child: const Icon(Icons.location_on, color: Colors.blue, size: 40),
                  ),
                ],
              ),
            ],
          ),

          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _getMyLocation,
        child: const Icon(Icons.my_location),
      ),
    );
  }
}

// 🎨 THE PAINTER: High-Performance Drawing Engine
class GridOverlayPainter extends CustomPainter {
  final List<List<int>> grid;
  final LatLng center;
  final double zoom;

  GridOverlayPainter({required this.grid, required this.center, required this.zoom});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Setup Paints (The Colors)
    final Paint paintRoad = Paint()..color = Colors.grey.withOpacity(0.6)..style = PaintingStyle.fill;
    final Paint paintWater = Paint()..color = Colors.blue.withOpacity(0.5)..style = PaintingStyle.fill;
    final Paint paintPark = Paint()..color = Colors.green.withOpacity(0.5)..style = PaintingStyle.fill;
    final Paint paintBuilding = Paint()..color = Colors.brown.withOpacity(0.6)..style = PaintingStyle.fill;
    final Paint paintFactory = Paint()..color = Colors.red.withOpacity(0.6)..style = PaintingStyle.fill;

    // 2. Calculate Scale (How big is a grid cell on screen?)
    // This is a rough estimation. In a full physics engine, we use projection math.
    // For now, we center the grid on the screen.
    double tileSize = 5.0 * (zoom / 15.0); // Dynamic sizing based on zoom
    double gridWidth = grid.length * tileSize;
    double gridHeight = grid[0].length * tileSize;

    // Start drawing from the center of the screen
    double startX = (size.width - gridWidth) / 2;
    double startY = (size.height - gridHeight) / 2;

    for (int x = 0; x < grid.length; x++) {
      for (int y = 0; y < grid[x].length; y++) {
        int type = grid[x][y];
        if (type == 0) continue; // Empty space

        Paint targetPaint = paintRoad;
        if (type == 1) targetPaint = paintRoad;     // Road
        if (type == 2) targetPaint = paintBuilding; // House
        if (type == 3) targetPaint = paintFactory;  // Factory
        if (type == 4) targetPaint = paintPark;     // Park
        if (type == 7) targetPaint = paintWater;    // Water

        // Draw the Rectangle
        canvas.drawRect(
          Rect.fromLTWH(startX + (x * tileSize), startY + (y * tileSize), tileSize, tileSize),
          targetPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true; // Always repaint when data changes
  }
}