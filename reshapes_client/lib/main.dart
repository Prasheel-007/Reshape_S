import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const ReshapeApp());
}

class ReshapeApp extends StatelessWidget {
  const ReshapeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reshape_S',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E1E), // Professional Dark Grey
        appBarTheme: const AppBarTheme(backgroundColor: Colors.black),
      ),
      home: const SimulationScreen(),
    );
  }
}

class SimulationScreen extends StatefulWidget {
  const SimulationScreen({super.key});

  @override
  State<SimulationScreen> createState() => _SimulationScreenState();
}

class _SimulationScreenState extends State<SimulationScreen> {
  // 0=Grass, 1=Road, 2=House, 3=Factory, 4=Park
  List<List<int>> grid = [];
  bool isLoading = false;

  // Dashboard Metrics
  int score = 0;
  int pollution = 0;
  int budget = 0;

  @override
  void initState() {
    super.initState();
    _fetchRandomWorld(); // Auto-load random world on startup
  }

  // --- API CONNECTION ---
  Future<void> _fetchRandomWorld() async {
    setState(() => isLoading = true);
    try {
      // 10.0.2.2 is for Android Emulator. Use 127.0.0.1 for Windows.
      // We use a helper to switch automatically.
      String url = _getBackendUrl('/api/generate_random');

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Convert API list to integers
        List<dynamic> rawGrid = data['grid'];
        setState(() {
          grid = rawGrid.map((row) => List<int>.from(row)).toList();
        });
        _updateScore(); // Calculate score for the new world
      }
    } catch (e) {
      print("❌ Connection Error: $e");
      _showError("Could not connect to Reshape Brain.\nIs server.py running?");
    }
    setState(() => isLoading = false);
  }

  Future<void> _updateScore() async {
    try {
      String url = _getBackendUrl('/api/calculate_score');
      final response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"grid": grid}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          score = data['score'];
          pollution = data['metrics']['pollution'];
          budget = data['metrics']['budget'];
        });
      }
    } catch (e) {
      print("Score Error: $e");
    }
  }

  String _getBackendUrl(String endpoint) {
    // Helper to switch between Android Emulator and Windows Localhost
    // If you are running on Windows, 'localhost' is fine.
    // If Android Emulator, use '10.0.2.2'.
    // For now, let's assume Windows desktop as primary.
    return 'http://127.0.0.1:5000$endpoint';
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  // --- ENGINE: ISOMETRIC RENDERER ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Reshape_S: Simulation View"),
        actions: [
          IconButton(
            icon: const Icon(Icons.casino, color: Colors.blueAccent),
            onPressed: _fetchRandomWorld,
            tooltip: "Generate Random Preset",
          )
        ],
      ),
      body: Row(
        children: [
          // 1. THE VIEWPORT (Map)
          Expanded(
            flex: 3,
            child: grid.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : InteractiveViewer(
              boundaryMargin: const EdgeInsets.all(800),
              minScale: 0.1,
              maxScale: 4.0,
              child: Center(
                child: SizedBox(
                  width: 1000,
                  height: 1000,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: _buildIsometricLayer(),
                  ),
                ),
              ),
            ),
          ),

          // 2. THE DASHBOARD (Right Panel)
          Expanded(
            flex: 1,
            child: Container(
              color: const Color(0xFF252526),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("METRICS", style: TextStyle(color: Colors.grey, letterSpacing: 1.5)),
                  const SizedBox(height: 20),
                  _buildStatCard("Sustainability", "$score/100", getScoreColor(score)),
                  _buildStatCard("Budget", "\$$budget", Colors.greenAccent),
                  _buildStatCard("Pollution", "$pollution ppm", Colors.orangeAccent),

                  const Spacer(),
                  const Divider(color: Colors.grey),
                  const Text("AI LOG:", style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 10),
                  Text(
                    "World generated successfully.\nGrid Size: 15x15\nAnalysis complete.",
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Color getScoreColor(int s) {
    if (s > 75) return Colors.green;
    if (s > 40) return Colors.orange;
    return Colors.red;
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          Text(value, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // --- THE MATH: 2D Grid -> 3D Isometric View ---
  List<Widget> _buildIsometricLayer() {
    List<Widget> tiles = [];

    // Config for your assets (Adjust these if your images are different sizes)
    double tileWidth = 64;
    double tileHeight = 32; // The "floor" height

    for (int x = 0; x < grid.length; x++) {
      for (int y = 0; y < grid[x].length; y++) {

        // ISOMETRIC FORMULA
        // This converts grid coordinates (x,y) into pixel coordinates (screenX, screenY)
        double screenX = (x - y) * (tileWidth / 2);
        double screenY = (x + y) * (tileHeight / 2);

        int type = grid[x][y];

        // Add the Tile Widget
        tiles.add(Positioned(
          left: screenX + 450, // Center offset
          top: screenY,
          child: _getAssetTile(type, tileWidth),
        ));
      }
    }
    // Sort logic to ensure front buildings hide back buildings
    // (In this simple loop, drawing order naturally handles basic occlusion,
    // but reversing helps with certain viewing angles)
    return tiles;
  }

  Widget _getAssetTile(int type, double width) {
    String image = "grass.png"; // Default
    if (type == 1) image = "road.png";
    if (type == 2) image = "house.png";
    if (type == 3) image = "factory.png";
    if (type == 4) image = "park.png";

    return Image.asset(
      'assets/images/$image',
      width: width,
      fit: BoxFit.contain,
    );
  }
}