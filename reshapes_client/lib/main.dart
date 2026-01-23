import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart'; // REQUIRED for Platform checks
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const ReshapeApp());
}

// ==========================================
// 1. THEME ENGINE (Restored)
// ==========================================
class AppThemes {
  static final ThemeData architect = ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF5F5F7),
    cardColor: Colors.white,
    dividerColor: Colors.grey.shade300,
    primaryColor: const Color(0xFF2C3E50),
    iconTheme: const IconThemeData(color: Color(0xFF2C3E50)),
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF2C3E50),
      secondary: Color(0xFF27AE60),
    ),
    fontFamily: 'Roboto',
  );

  static final ThemeData cyber = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Colors.black,
    cardColor: const Color(0xFF121212),
    dividerColor: Colors.greenAccent.withOpacity(0.3),
    primaryColor: Colors.greenAccent,
    iconTheme: const IconThemeData(color: Colors.greenAccent),
    colorScheme: const ColorScheme.dark(
      primary: Colors.greenAccent,
      secondary: Colors.purpleAccent,
      surface: Color(0xFF1E1E1E),
    ),
    textTheme: const TextTheme(bodyMedium: TextStyle(fontFamily: 'Courier')),
  );

  static final ThemeData zen = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF2D3436),
    cardColor: const Color(0xFF353B48),
    dividerColor: Colors.white12,
    primaryColor: const Color(0xFF55EFC4),
    iconTheme: const IconThemeData(color: Color(0xFF55EFC4)),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFFA3C6C0),
      secondary: Color(0xFFE0C097),
    ),
  );
}

// ==========================================
// 2. APP ROOT
// ==========================================
class ReshapeApp extends StatefulWidget {
  const ReshapeApp({super.key});

  @override
  State<ReshapeApp> createState() => _ReshapeAppState();
}

class _ReshapeAppState extends State<ReshapeApp> {
  ThemeData _currentTheme = AppThemes.architect;

  void _changeTheme(ThemeData theme) {
    setState(() {
      _currentTheme = theme;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reshape_S',
      debugShowCheckedModeBanner: false,
      theme: _currentTheme,
      home: SplashScreen(onThemeChanged: _changeTheme),
    );
  }
}

// ==========================================
// 3. SPLASH SCREEN (Restored)
// ==========================================
class SplashScreen extends StatefulWidget {
  final Function(ThemeData) onThemeChanged;
  const SplashScreen({super.key, required this.onThemeChanged});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 4), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen(onThemeChanged: widget.onThemeChanged)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.greenAccent.withOpacity(0.15),
                      blurRadius: 60,
                      spreadRadius: 10
                  )
                ],
              ),
              child: Image.asset(
                'assets/images/Reshape_S.png',
                width: 140,
                height: 140,
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              "RESHAPE_S",
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 15),
            Text(
              "Reshape the Future. Sustain the World.",
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 60),
            const CircularProgressIndicator(color: Colors.white12, strokeWidth: 2),
            const SizedBox(height: 20),
            const Text("Initializing Neural Engine...", style: TextStyle(color: Colors.white24, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 4. HOME SCREEN (Restored)
// ==========================================
class HomeScreen extends StatelessWidget {
  final Function(ThemeData) onThemeChanged;
  const HomeScreen({super.key, required this.onThemeChanged});

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    bool isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF1e1e1e), const Color(0xFF000000)]
                : [const Color(0xFFFFFFFF), const Color(0xFFE0EAFC)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: theme.primaryColor.withOpacity(0.2), blurRadius: 30)],
                ),
                child: Image.asset(
                  'assets/images/Reshape_S.png',
                  width: 120,
                  height: 120,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "Welcome Architect",
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w300,
                    color: theme.colorScheme.primary
                ),
              ),
              const SizedBox(height: 40),
              _buildMenuButton(context, "START SIMULATION", Icons.play_arrow, () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const SimulationScreen()));
              }),
              _buildMenuButton(context, "VISUAL THEME", Icons.palette, () {
                _showThemePicker(context);
              }),
              _buildMenuButton(context, "SYSTEM ARCHITECTURE", Icons.memory, () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const SystemInfoScreen()));
              }),
              const Spacer(),
              Text("v1.0.0 • Distinction Build", style: TextStyle(color: theme.disabledColor)),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showThemePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: 320,
          child: Column(
            children: [
              const Text("Select Interface Style", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.architecture, color: Colors.blueGrey),
                title: const Text("The Architect"),
                subtitle: const Text("Clean, precise, daylight optimized."),
                onTap: () {
                  onThemeChanged(AppThemes.architect);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.terminal, color: Colors.greenAccent),
                title: const Text("The Coder"),
                subtitle: const Text("High contrast, neon, dark mode."),
                onTap: () {
                  onThemeChanged(AppThemes.cyber);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.spa, color: Color(0xFF55EFC4)),
                title: const Text("The Naturalist"),
                subtitle: const Text("Earthy tones, calming, organic."),
                onTap: () {
                  onThemeChanged(AppThemes.zen);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMenuButton(BuildContext context, String text, IconData icon, VoidCallback onTap) {
    var theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SizedBox(
        width: 280,
        height: 55,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.cardColor,
            foregroundColor: theme.colorScheme.primary,
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            side: BorderSide(color: theme.dividerColor),
          ),
          icon: Icon(icon),
          label: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
          onPressed: onTap,
        ),
      ),
    );
  }
}

// ==========================================
// 5. SYSTEM INFO SCREEN (Restored)
// ==========================================
class SystemInfoScreen extends StatelessWidget {
  const SystemInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("System Architecture", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: theme.iconTheme,
        titleTextStyle: TextStyle(color: theme.textTheme.bodyMedium?.color, fontSize: 20),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildInfoCard(
            theme,
            "Project Philosophy",
            "Reshape_S is a simulation environment designed to optimize urban sustainability through algorithmic logic.",
            Icons.lightbulb_outline,
          ),
          const SizedBox(height: 20),
          Text("TECHNICAL STACK", style: TextStyle(color: theme.disabledColor, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          _buildTechRow(theme, "Frontend Engine", "Flutter (Dart)", "Isometric Rendering Layer"),
          _buildTechRow(theme, "Backend Logic", "Python (Flask)", "Heuristic Optimization"),
          _buildTechRow(theme, "Data Protocol", "REST API", "JSON Grid Serialization"),
          const SizedBox(height: 20),
          Text("ALGORITHMIC LOGIC", style: TextStyle(color: theme.disabledColor, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          _buildInfoCard(
            theme,
            "Procedural Generation (PCG)",
            "The city layout uses a 'Cellular Zoning' algorithm. It divides the world into arterial blocks and assigns density zones.",
            Icons.grid_4x4,
          ),
          const SizedBox(height: 10),
          _buildInfoCard(
            theme,
            "Heuristic Scoring Engine",
            "Real-time evaluation of city performance. The Python backend calculates 'Pollution Vectors' based on Manhattan Distance.",
            Icons.functions,
          ),
          const SizedBox(height: 40),
          Center(
            child: Text(
                "Reshape_S v1.0.0",
                style: TextStyle(color: theme.disabledColor, fontSize: 12)
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme, String title, String content, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: theme.dividerColor),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.secondary),
              const SizedBox(width: 10),
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
            ],
          ),
          const SizedBox(height: 10),
          Text(content, style: TextStyle(fontSize: 14, height: 1.5, color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8))),
        ],
      ),
    );
  }

  Widget _buildTechRow(ThemeData theme, String label, String value, String sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: theme.disabledColor)),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: theme.textTheme.bodyMedium?.color)),
            ],
          ),
          Text(sub, style: TextStyle(fontSize: 12, color: theme.colorScheme.secondary)),
        ],
      ),
    );
  }
}

// ==========================================
// 6. SIMULATION SCREEN (Logic Preserved, UI Restored)
// ==========================================
class SimulationScreen extends StatefulWidget {
  const SimulationScreen({super.key});

  @override
  State<SimulationScreen> createState() => _SimulationScreenState();
}

class _SimulationScreenState extends State<SimulationScreen> {
  List<List<int>> grid = [];
  bool isLoading = false;
  int score = 0;
  int pollution = 0;
  int budget = 0;
  bool isMetricsVisible = true; // Restored UI state

  @override
  void initState() {
    super.initState();
    _fetchRandomWorld();
  }

  // --- API CALL 1: GENERATE WORLD ---
  Future<void> _fetchRandomWorld() async {
    setState(() => isLoading = true);
    try {
      const String productionUrl = 'https://reshape-s.vercel.app';
      const String localUrl = 'http://127.0.0.1:5000';

      // 🧠 SMART SWITCH LOGIC
      bool useLocal = kDebugMode && defaultTargetPlatform == TargetPlatform.windows;
      final String baseUrl = useLocal ? localUrl : productionUrl;

      // ✅ UPDATED URL: Points to V1 API
      String url = '$baseUrl/api/v1/generate_random';
      print("🔌 Connecting to: $url");

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<dynamic> rawGrid = data['grid'];
        setState(() {
          grid = rawGrid.map((row) => List<int>.from(row)).toList();
        });
        _updateScore();
      } else {
        print("❌ Server Error: ${response.statusCode}");
      }
    } catch (e) {
      print("Error: $e");
    }
    setState(() => isLoading = false);
  }

  // --- API CALL 2: UPDATE SCORE ---
  Future<void> _updateScore() async {
    try {
      const String productionUrl = 'https://reshape-s.vercel.app';
      const String localUrl = 'http://127.0.0.1:5000';

      bool useLocal = kDebugMode && defaultTargetPlatform == TargetPlatform.windows;
      final String baseUrl = useLocal ? localUrl : productionUrl;

      // ✅ UPDATED URL: Points to V1 API
      String url = '$baseUrl/api/v1/calculate_score';

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
    } catch (e) { print(e); }
  }

  void _cycleTile(int x, int y) {
    int current = grid[x][y];
    if (current == 1 || current == 5 || current == 6) return; // Keep road lock

    setState(() {
      if (current == 0) grid[x][y] = 2;
      else if (current == 2) grid[x][y] = 3;
      else if (current == 3) grid[x][y] = 4;
      else if (current == 4) grid[x][y] = 0;
    });
    _updateScore();
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: theme.brightness == Brightness.dark
                ? [const Color(0xFF1e1e1e), const Color(0xFF000000)]
                : [const Color(0xFFFFFFFF), const Color(0xFFE0EAFC)],
          ),
        ),
        child: Stack(
          children: [
            // 1. THE MAP LAYER (Using the working logic)
            Positioned.fill(
              child: grid.isEmpty
                  ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
                  : InteractiveViewer(
                boundaryMargin: const EdgeInsets.all(500),
                minScale: 0.1,
                maxScale: 4.0,
                child: Center(
                  child: SizedBox(
                    width: 1500,
                    height: 1500,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: _buildSimpleLayer(), // <--- USING THE WORKING RENDERER
                    ),
                  ),
                ),
              ),
            ),

            // 2. METRICS PANEL (Restored Polish)
            Positioned(top: 40, right: 20, child: _buildFloatingMetricsPanel(theme)),

            // 3. CONTROL BAR (Restored Polish)
            Positioned(bottom: 30, left: 0, right: 0, child: Center(child: _buildControlBar(theme))),

            // 4. BACK BUTTON
            Positioned(
              top: 40,
              left: 20,
              child: FloatingActionButton.small(
                heroTag: "back_btn",
                backgroundColor: theme.cardColor,
                child: Icon(Icons.arrow_back, color: theme.iconTheme.color),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ THIS IS THE CRITICAL FUNCTION
  List<Widget> _buildSimpleLayer() {
    List<Widget> tiles = [];
    double tileWidth = 64;
    double tileHeight = 32;

    for (int x = 0; x < grid.length; x++) {
      for (int y = 0; y < grid[x].length; y++) {
        double screenX = (x - y) * (tileWidth / 2) + 700; // Center offset
        double screenY = (x + y) * (tileHeight / 2);
        int type = grid[x][y];

        double visualOffset = 0;
        if (type == 2 || type == 3) visualOffset = 12.0;
        else if (type == 4) visualOffset = 6.0;

        tiles.add(Positioned(
          left: screenX,
          top: screenY - visualOffset,
          child: GestureDetector(
            onTap: () => _cycleTile(x, y),
            behavior: HitTestBehavior.translucent,
            child: Image.asset(
              _getImagePath(type),
              width: tileWidth,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
        ));
      }
    }
    return tiles;
  }

  String _getImagePath(int type) {
    if (type == 1) return 'assets/images/road.png';
    if (type == 5) return 'assets/images/road_h.png';
    if (type == 6) return 'assets/images/road_x.png';
    if (type == 2) return 'assets/images/house.png';
    if (type == 3) return 'assets/images/factory.png';
    if (type == 4) return 'assets/images/park.png';
    return 'assets/images/grass.png';
  }

  // --- POLISHED UI COMPONENTS ---

  Widget _buildFloatingMetricsPanel(ThemeData theme) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: isMetricsVisible ? 260 : 55,
      height: isMetricsVisible ? 300 : 55,
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: isMetricsVisible
              ? _buildMaximizedContent(theme)
              : _buildMinimizedContent(theme),
        ),
      ),
    );
  }

  Widget _buildMaximizedContent(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(15),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("CITY METRICS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: theme.hintColor)),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(Icons.close_fullscreen, size: 18, color: theme.disabledColor),
              onPressed: () => setState(() => isMetricsVisible = false),
            ),
          ],
        ),
        Divider(color: theme.dividerColor),
        const SizedBox(height: 5),
        _buildStatRow("Sustainability", "$score/100", _getScoreColor(score)),
        const SizedBox(height: 12),
        _buildStatRow("Budget", "\$$budget", Colors.green),
        const SizedBox(height: 12),
        _buildStatRow("Pollution", "$pollution ppm", Colors.orange),
        const SizedBox(height: 20),
        Text("AI Status: ACTIVE", style: TextStyle(color: theme.colorScheme.primary, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildMinimizedContent(ThemeData theme) {
    return Center(
      child: IconButton(
        icon: Icon(Icons.bar_chart, color: theme.colorScheme.primary),
        onPressed: () => setState(() => isMetricsVisible = true),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildControlBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.9),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: theme.dividerColor),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.casino, color: theme.colorScheme.primary),
            onPressed: _fetchRandomWorld,
            tooltip: "Regenerate World",
          ),
          const SizedBox(width: 20),
          Text("GOD MODE", style: TextStyle(color: theme.disabledColor, letterSpacing: 2, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  Color _getScoreColor(int s) {
    if (s > 75) return Colors.green;
    if (s > 40) return Colors.orange;
    return Colors.red;
  }
}