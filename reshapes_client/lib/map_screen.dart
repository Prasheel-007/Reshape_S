import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:math' as math;

enum MapMode { satellite, heatmap, zoning }
enum MapStyle { dataView, blueprint, reference, satelliteMap }

class LocationResult {
  final String displayName;
  final double lat;
  final double lon;

  LocationResult({required this.displayName, required this.lat, required this.lon});
}

class MapScreen extends StatefulWidget {
  final String visualTheme;
  const MapScreen({super.key, this.visualTheme = "The Coder"});

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
  MapMode _currentMode = MapMode.zoning;
  bool _isConstructionMode = false;

  late MapStyle _currentStyle;
  bool _showSatelliteLabels = true; // 🏷️ NEW: Satellite Labels Toggle

  int _score = 0;
  Map<String, dynamic> _metrics = {"pollution": 0, "budget": 0};
  bool _hasData = false;

  final Set<math.Point<int>> _selectedCells = {};
  double _rotation = 0.0;
  String _selectionInfo = "Select a sector to analyze";

  bool _showUI = true;
  bool _isSearchExpanded = false;

  String _activeMenu = "";
  bool _isHudExpanded = true;
  bool _isLegendExpanded = true;
  String _hoveredItemDesc = "";

  @override
  void initState() {
    super.initState();
    if (widget.visualTheme == "The Architect") _currentStyle = MapStyle.blueprint;
    else if (widget.visualTheme == "The Naturalist") _currentStyle = MapStyle.reference;
    else _currentStyle = MapStyle.dataView;
  }

  void _toggleMenu(String menu) {
    setState(() {
      if (_activeMenu == menu) {
        _activeMenu = "";
        _hoveredItemDesc = "";
      } else {
        _activeMenu = menu;
        _hoveredItemDesc = "";
      }
    });
  }

  // 🤖 NEW: Mock function to trigger the AI Computer Vision (Backend connection next!)
  Future<void> _runAIAutoFill() async {
    if (_grid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No data to analyze! Sync a map first.')));
      return;
    }

    setState(() {
      _activeMenu = "";
      _isLoading = true;
    });

    try {
      // SMART SWITCH: Automatically uses Localhost for debugging, and Vercel for Release!
      String serverUrl = kDebugMode ? "http://127.0.0.1:5000" : "https://reshape-s.vercel.app";
      if (kDebugMode && defaultTargetPlatform == TargetPlatform.android && !kIsWeb) {
        serverUrl = "http://10.0.2.2:5000"; // UNCOMMENTED: Android Emulator needs this local IP
      }

      final url = Uri.parse('$serverUrl/api/v2/run_ai_survey');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "grid": _grid,
          "lat": _gridOrigin!.latitude,
          "lon": _gridOrigin!.longitude
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'success') {
          setState(() {
            List<dynamic> rawGrid = data['grid'] ?? [];
            _grid = rawGrid.map((row) => List<int>.from(row ?? [])).toList();

            int safeScore = (data['score'] as int?) ?? _score;
            Map<String, dynamic> safeMetrics = data['metrics'] ?? _metrics;
            _updateMetrics(safeScore, safeMetrics);
          });

          int filled = data['filled_blocks'] ?? 0;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('🤖 AI Survey Complete: Zoned $filled missing blocks!'),
            backgroundColor: Colors.purple,
          ));
        } else if (data['status'] == 'insufficient_data') {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('AI Needs more context. Not enough existing buildings to learn from.'),
            backgroundColor: Colors.orange,
          ));
        }
      }
    } catch (e) {
      print("AI Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AI Engine Offline: $e')));
    }

    setState(() => _isLoading = false);
  }

  Future<List<LocationResult>> _getSearchSuggestions(String query) async {
    if (query.trim().length < 3) return [];
    try {
      final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=5');
      final response = await http.get(url, headers: {'User-Agent': 'ReshapeS_CityPlanner/1.0'});

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((item) => LocationResult(
          displayName: item['display_name'],
          lat: double.parse(item['lat']),
          lon: double.parse(item['lon']),
        )).toList();
      }
    } catch (e) {
      print("Search Error: $e");
    }
    return [];
  }

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
    _selectedCells.clear();

    try {
      // SMART SWITCH: Automatically uses Localhost for debugging, and Vercel for Release!
      String serverUrl = kDebugMode ? "http://127.0.0.1:5000" : "https://reshape-s.vercel.app";
      if (kDebugMode && defaultTargetPlatform == TargetPlatform.android && !kIsWeb) {
        serverUrl = "http://10.0.2.2:5000"; // Android Emulator needs this local IP
      }

      final url = Uri.parse('$serverUrl/api/v2/get_chunk?lat=${targetCenter.latitude}&lon=${targetCenter.longitude}');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            int safeScore = (data['score'] as int?) ?? 0;
            Map<String, dynamic> safeMetrics = data['metrics'] ?? {"pollution": 0, "budget": 0};

            List<dynamic> rawGrid = data['grid'] ?? [];
            if (rawGrid.isEmpty) {
              _grid = [];
            } else {
              _grid = rawGrid.map((row) => List<int>.from(row ?? [])).toList();
            }

            _gridOrigin = targetCenter;
            _updateMetrics(safeScore, safeMetrics);
            _showSimulationLayer = true;
            _hasData = true;
          });
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

  void _handlePointerInput(PointerEvent event) {
    if (_grid.isEmpty || _gridOrigin == null || !_isConstructionMode) return;

    final LatLng? point = _mapController.camera.pointToLatLng(math.Point(event.localPosition.dx, event.localPosition.dy));
    if (point == null) return;

    int gridRows = _grid.length;
    int gridCols = _grid.isNotEmpty ? _grid[0].length : 0;
    if (gridRows == 0 || gridCols == 0) return;

    double tileMeters = 10.0;
    double latDegrees = (gridRows * tileMeters) / 111000;
    // Fix: Match the exact backend mathematical approach for consistency
    double lonDegrees = (gridCols * tileMeters) / (111000 * math.cos(math.pi * _gridOrigin!.latitude / 180));
    
    double startLat = _gridOrigin!.latitude - (latDegrees / 2);
    double stepLat = latDegrees / gridRows;

    double startLon = _gridOrigin!.longitude - (lonDegrees / 2);
    double stepLon = lonDegrees / gridCols;

    int x = ((point.latitude - startLat) / stepLat).floor();
    int y = ((point.longitude - startLon) / stepLon).floor();

    if (x >= 0 && x < gridRows && y >= 0 && y < gridCols) {
      setState(() {
        var gridPoint = math.Point(x, y);
        if (event.buttons == kPrimaryButton) {
          _selectedCells.add(gridPoint);
        } else if (event.buttons == kSecondaryButton) {
          _selectedCells.remove(gridPoint);
        }
        _updateSelectionInfo();
      });
    }
  }

  void _updateSelectionInfo() {
    if (_selectedCells.isEmpty) {
      _selectionInfo = "Select a sector to analyze";
      return;
    }

    var first = _selectedCells.first;
    if (first.x < 0 || first.x >= _grid.length || first.y < 0 || first.y >= _grid[0].length) {
      _selectedCells.clear();
      return;
    }

    int count = _selectedCells.length;
    int type = _grid[first.x][first.y];

    String typeName = "Empty Land";
    if (type == 1) typeName = "Infrastructure";
    else if (type == 2) typeName = "Residential";
    else if (type == 3) typeName = "Industrial";
    else if (type == 4) typeName = "Green Belt";
    else if (type == 5) typeName = "Commercial / IT";

    if (count > 20 && type == 2) typeName = "High-Density Residential";
    if (count > 50 && type == 3) typeName = "Heavy Industry Complex";
    if (count > 40 && type == 5) typeName = "Tech Park / Hub";

    _selectionInfo = "$typeName\nSelected Area: ${count * 100} sq.m";
  }

  void _modifyGrid(int newType) {
    if (_selectedCells.isEmpty) return;

    setState(() {
      for (var cell in _selectedCells) {
        int r = cell.x;
        int c = cell.y;
        if (r >= 0 && r < _grid.length && c >= 0 && c < _grid[0].length) {
          _grid[r][c] = newType;
        }
      }
      _grid = List.from(_grid);
      _selectedCells.clear();
      _updateSelectionInfo();
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
    bool isDark = _currentStyle == MapStyle.dataView || _currentStyle == MapStyle.satelliteMap;
    Color panelColor = isDark ? Colors.black.withOpacity(0.7) : Colors.white.withOpacity(0.8);
    Color fgColor = isDark ? Colors.white : Colors.black87;
    Color accentColor = isDark ? Colors.cyanAccent : Colors.blueAccent;

    String mapUrl = 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
    if (_currentStyle == MapStyle.blueprint) {
      mapUrl = 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';
    } else if (_currentStyle == MapStyle.reference) {
      mapUrl = 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';
    } else if (_currentStyle == MapStyle.satelliteMap) {
      mapUrl = 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _myLocation,
              initialZoom: 17.0,
              onTap: (tapPos, latLng) {
                if (_activeMenu.isNotEmpty) setState(() => _activeMenu = "");
              },
              interactionOptions: InteractionOptions(
                flags: _isConstructionMode ? InteractiveFlag.none : InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: mapUrl,
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.reshapel.reshapes_client',
              ),

              // 🏷️ NEW: Transparent Text Labels Layer for Satellite!
              if (_currentStyle == MapStyle.satelliteMap && _showSatelliteLabels)
                TileLayer(
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager_only_labels/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],

                ),

              if (_showSimulationLayer && _grid.isNotEmpty && _gridOrigin != null)
                SizedBox.expand(
                  child: CustomPaint(
                    painter: IntelligentGridPainter(
                      grid: _grid,
                      gridOrigin: _gridOrigin!,
                      camera: _mapController.camera,
                      selectedCells: _selectedCells,
                      mode: _currentMode,
                      isEditMode: _isConstructionMode,
                      theme: _currentStyle,
                    ),
                  ),
                ),
            ],
          ),

          if (_isConstructionMode)
            Listener(
              onPointerDown: _handlePointerInput,
              onPointerMove: _handlePointerInput,
              behavior: HitTestBehavior.translucent,
              child: Container(color: Colors.transparent),
            ),

          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: 20,
            child: FloatingActionButton.small(
              heroTag: "zen_btn",
              backgroundColor: panelColor,
              foregroundColor: accentColor,
              onPressed: () {
                setState(() {
                  _showUI = !_showUI;
                  _activeMenu = "";
                });
              },
              child: Icon(_showUI ? Icons.visibility_off : Icons.visibility),
            ),
          ),

          if (_showUI) ...[

            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 20,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(
                      color: panelColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.withOpacity(0.3)),
                    ),
                    child: IconButton(
                      icon: Icon(Icons.arrow_back, color: fgColor),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildAnimatedSearchBar(panelColor, fgColor, accentColor, isDark),
                ],
              ),
            ),

            if (_hasData)
              Positioned(
                top: MediaQuery.of(context).padding.top + 70,
                right: 20,
                child: _buildCollapsibleHUD(panelColor, fgColor, accentColor),
              ),

            if (_hasData && _showSimulationLayer)
              Positioned(
                  top: MediaQuery.of(context).padding.top + 270, // Pushed down to prevent overlap!
                  right: 20,
                  child: _buildCollapsibleLegend(panelColor, fgColor, accentColor)
              ),

            Positioned(
              top: MediaQuery.of(context).padding.top + 100,
              left: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: panelColor,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dockButton(Icons.palette_outlined, "Map Style", () => _toggleMenu("theme"), _activeMenu == "theme" ? accentColor : fgColor),
                    _dockButton(Icons.layers, "Data Overlay", () => _toggleMenu("layer"), _activeMenu == "layer" ? accentColor : fgColor),

                    // 🤖 NEW: AI Auto-Fill Button in the main dock!
                    if (_hasData)
                      _dockButton(Icons.auto_awesome, "AI Survey", _runAIAutoFill, Colors.purpleAccent),

                    _dockButton(
                        _isConstructionMode ? Icons.build : Icons.build_outlined, "Edit Mode",
                            () {
                          _toggleMenu("");
                          setState(() { _isConstructionMode = !_isConstructionMode; _selectedCells.clear(); _updateSelectionInfo(); });
                        },
                        _isConstructionMode ? accentColor : fgColor
                    ),
                  ],
                ),
              ),
            ),

            if (_activeMenu == "theme")
              _buildHoverGlassMenu(
                  topOffset: MediaQuery.of(context).padding.top + 100,
                  isDark: isDark, fg: fgColor, accent: accentColor,
                  title: "Map Styles",
                  items: [
                    _hoverMenuItem("Data View", Icons.dark_mode, null, _currentStyle == MapStyle.dataView, fgColor, accentColor,
                        "High-contrast neon design.", () => setState(() { _currentStyle = MapStyle.dataView; _activeMenu = ""; })),

                    _hoverMenuItem("Blueprint", Icons.architecture, null, _currentStyle == MapStyle.blueprint, fgColor, accentColor,
                        "Clean, architectural aesthetic.", () => setState(() { _currentStyle = MapStyle.blueprint; _activeMenu = ""; })),

                    _hoverMenuItem("Reference", Icons.map, null, _currentStyle == MapStyle.reference, fgColor, accentColor,
                        "Detailed geographical map.", () => setState(() { _currentStyle = MapStyle.reference; _activeMenu = ""; })),

                    _hoverMenuItem("Satellite", Icons.satellite_alt, null, _currentStyle == MapStyle.satelliteMap, fgColor, accentColor,
                        "Real-world imagery.", () => setState(() { _currentStyle = MapStyle.satelliteMap; _activeMenu = ""; })),

                    // 🏷️ SATELLITE LABEL TOGGLE (Only shows when Satellite is active)
                    if (_currentStyle == MapStyle.satelliteMap)
                      _hoverMenuItem(
                          _showSatelliteLabels ? "Hide Labels" : "Show Labels",
                          _showSatelliteLabels ? Icons.label_off : Icons.label,
                          null, false, fgColor, Colors.orangeAccent,
                          "Toggles street names and landmarks over the satellite photo.",
                              () => setState(() { _showSatelliteLabels = !_showSatelliteLabels; _activeMenu = ""; })
                      ),
                  ]
              ),

            if (_activeMenu == "layer")
              _buildHoverGlassMenu(
                  topOffset: MediaQuery.of(context).padding.top + 145,
                  isDark: isDark, fg: fgColor, accent: accentColor,
                  title: "Data Layers",
                  items: [
                    _hoverMenuItem("Reality Glass", Icons.search, null, _currentMode == MapMode.satellite && _showSimulationLayer, fgColor, accentColor,
                        "Wireframe overlay.", () => setState(() { _currentMode = MapMode.satellite; _showSimulationLayer = true; _activeMenu = ""; })),

                    _hoverMenuItem("Zoning Map", Icons.business, null, _currentMode == MapMode.zoning && _showSimulationLayer, fgColor, accentColor,
                        "Land allocation blocks.", () => setState(() { _currentMode = MapMode.zoning; _showSimulationLayer = true; _activeMenu = ""; })),

                    _hoverMenuItem("Pollution Data", Icons.thermostat, null, _currentMode == MapMode.heatmap && _showSimulationLayer, fgColor, accentColor,
                        "Air quality heatmap.", () => setState(() { _currentMode = MapMode.heatmap; _showSimulationLayer = true; _activeMenu = ""; })),

                    _hoverMenuItem("Grid Off", Icons.grid_off, null, !_showSimulationLayer, Colors.grey, Colors.redAccent,
                        "Hides the data overlay entirely.", () => setState(() { _showSimulationLayer = false; _activeMenu = ""; })),
                  ]
              ),

            Positioned(
              bottom: 120,
              right: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: panelColor,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dockButton(Icons.rotate_left, "Rot L", () => _rotateMap(-45), fgColor),
                    _dockButton(Icons.rotate_right, "Rot R", () => _rotateMap(45), fgColor),
                    _dockButton(Icons.navigation, "North", () { _rotation = 0; _mapController.rotate(0); setState((){}); }, fgColor),
                    if (!_isConstructionMode) _dockButton(Icons.my_location, "GPS", () { _toggleMenu(""); _getMyLocation(); }, fgColor),
                    if (!_isConstructionMode) _dockButton(Icons.download, "Sync", () { _toggleMenu(""); _fetchRealWorldChunk(_mapController.camera.center); }, accentColor),
                  ],
                ),
              ),
            ),

            if (_isConstructionMode)
              Positioned(
                  bottom: 20, left: 20, right: 20,
                  child: _buildInspectorPanel(panelColor, fgColor, accentColor)
              ),
          ],

          if (_isLoading)
            Container(color: Colors.black54, child: Center(child: CircularProgressIndicator(color: accentColor))),
        ],
      ),
    );
  }



  Widget _buildCollapsibleHUD(Color bg, Color fg, Color accent) {
    // Calculate total zoned area (each block is 10x10 meters = 100 sq meters)
    int zonedBlocks = 0;
    for (var row in _grid) {
      for (var cell in row) {
        if (cell != 0) zonedBlocks++;
      }
    }
    int totalAreaSqm = zonedBlocks * 100;

    // Safely grab the metrics Python sent us
    int population = _metrics["population"] ?? 0;
    // Use dynamic to safely handle both int and double from Python
    dynamic rawGreen = _metrics["green_coverage"] ?? 0;
    String greenCoverage = rawGreen.toString();
    int pollution = _metrics["pollution"] ?? 0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: _isHudExpanded ? 220 : 50,
      height: _isHudExpanded ? 190 : 50,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(_isHudExpanded ? 15 : 25),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 5, offset: Offset(0, 3))],
      ),
      child: _isHudExpanded
          ? Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(15.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("CITY METRICS", style: TextStyle(color: fg.withOpacity(0.5), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                const SizedBox(height: 5),

                // The Main Score
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Sustainability", style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.bold)),
                    Text("$_score/100", style: TextStyle(color: _score > 50 ? Colors.green : Colors.orange, fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                Divider(color: Colors.grey.withOpacity(0.3)),

                // Detailed Breakdown
                _metricRow(Icons.people, "Population", "$population", Colors.blueAccent, fg),
                _metricRow(Icons.nature, "Green Coverage", "$greenCoverage%", Colors.green, fg),
                _metricRow(Icons.cloud, "Pollution Index", "$pollution AQI", pollution > 50 ? Colors.redAccent : Colors.grey, fg),
                _metricRow(Icons.square_foot, "Zoned Area", "$totalAreaSqm m²", Colors.cyan, fg),
              ],
            ),
          ),
          Positioned(
            top: 5, right: 5,
            child: IconButton(
              icon: Icon(Icons.close_fullscreen, color: fg, size: 14),
              onPressed: () => setState(() => _isHudExpanded = false),
            ),
          )
        ],
      )
          : IconButton(
        icon: Icon(Icons.analytics_outlined, color: accent),
        tooltip: "Open Scoreboard",
        onPressed: () => setState(() => _isHudExpanded = true),
      ),
    );
  }

  // Helper widget for the HUD rows
  Widget _metricRow(IconData icon, String label, String value, Color iconColor, Color fg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: iconColor),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: fg.withOpacity(0.8), fontSize: 11)),
            ],
          ),
          Text(value, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildCollapsibleLegend(Color bg, Color fg, Color accent) {
    List<Widget> items = [];
    if (_currentMode == MapMode.zoning) {
      items = [
        _legendItem(Colors.amber, "Residential", fg),
        _legendItem(Colors.cyan, "Commercial", fg),
        _legendItem(Colors.purple, "Industrial", fg),
        _legendItem(Colors.green, "Nature", fg),
        _legendItem(Colors.grey, "Roads", fg),
      ];
    } else if (_currentMode == MapMode.heatmap) {
      items = [
        _legendItem(Colors.redAccent, "Polluted", fg),
        _legendItem(Colors.green, "Clean", fg),
      ];
    } else {
      items = [_legendItem(accent.withOpacity(0.5), "Structures", fg)];
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: _isLegendExpanded ? 130 : 50,
      height: _isLegendExpanded ? (items.length * 20.0) + 30 : 50,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(_isLegendExpanded ? 15 : 25),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 5, offset: Offset(0, 3))],
      ),
      child: _isLegendExpanded
          ? Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 15, left: 15, bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: items),
          ),
          Positioned(
            top: -5, right: -5,
            child: IconButton(
              icon: Icon(Icons.close_fullscreen, color: fg, size: 12),
              onPressed: () => setState(() => _isLegendExpanded = false),
            ),
          )
        ],
      )
          : IconButton(
        icon: Icon(Icons.list, color: fg),
        tooltip: "Show Legend",
        onPressed: () => setState(() => _isLegendExpanded = true),
      ),
    );
  }

  Widget _legendItem(Color c, String text, Color fg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: fg, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildHoverGlassMenu({required double topOffset, required bool isDark, required Color fg, required Color accent, required String title, required List<Widget> items}) {
    Color glassBg = isDark ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.7);
    Color borderColor = isDark ? Colors.white30 : Colors.black26;

    return Positioned(
      top: topOffset,
      left: 80,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: 280,
            decoration: BoxDecoration(
              color: glassBg,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 15, top: 12, bottom: 8),
                  child: Text(title.toUpperCase(), style: TextStyle(color: fg.withOpacity(0.5), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                ),
                ...items,
                if (_hoveredItemDesc.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black45 : Colors.white54,
                      border: Border(top: BorderSide(color: borderColor)),
                    ),
                    child: Text(
                      _hoveredItemDesc,
                      style: TextStyle(color: fg, fontSize: 11, height: 1.4, fontStyle: FontStyle.italic),
                    ),
                  )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hoverMenuItem(String title, IconData icon, dynamic value, bool isSelected, Color fg, Color accent, String description, VoidCallback onTap) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredItemDesc = description),
      onExit: (_) => setState(() => _hoveredItemDesc = ""),
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: isSelected ? accent.withOpacity(0.2) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: isSelected ? accent : fg, size: 20),
              const SizedBox(width: 15),
              Expanded(child: Text(title, style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 13))),
              if (isSelected) Icon(Icons.check, color: accent, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dockButton(IconData icon, String tooltip, VoidCallback onTap, Color iconColor) {
    return IconButton(
      icon: Icon(icon, color: iconColor, size: 22),
      tooltip: tooltip,
      onPressed: onTap,
    );
  }

  Widget _buildAnimatedSearchBar(Color bg, Color fg, Color accent, bool isDark) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: _isSearchExpanded ? MediaQuery.of(context).size.width * 0.5 : 50,
      height: 50,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: _isSearchExpanded
          ? Row(
        children: [
          const SizedBox(width: 15),
          Expanded(
            child: Autocomplete<LocationResult>(
              optionsBuilder: (TextEditingValue textEditingValue) async {
                if (textEditingValue.text.isEmpty) return const Iterable<LocationResult>.empty();
                return await _getSearchSuggestions(textEditingValue.text);
              },
              displayStringForOption: (LocationResult option) => option.displayName,
              onSelected: (LocationResult selection) {
                setState(() {
                  _myLocation = LatLng(selection.lat, selection.lon);
                  _isLoading = true;
                  _isSearchExpanded = false;
                });
                _mapController.move(_myLocation, 17.0);
                _fetchRealWorldChunk(_myLocation);
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: TextStyle(color: fg, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: "Search location...",
                    hintStyle: TextStyle(color: fg.withOpacity(0.5), fontSize: 14),
                    border: InputBorder.none,
                  ),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    color: isDark ? Colors.blueGrey[900] : Colors.white,
                    elevation: 4,
                    child: SizedBox(
                      height: 200,
                      width: MediaQuery.of(context).size.width * 0.5,
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final option = options.elementAt(index);
                          return ListTile(
                            leading: Icon(Icons.location_on, color: accent, size: 16),
                            title: Text(option.displayName.split(',')[0], style: TextStyle(color: fg, fontSize: 12)),
                            onTap: () => onSelected(option),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: fg, size: 20),
            onPressed: () => setState(() => _isSearchExpanded = false),
          ),
        ],
      )
          : IconButton(
        icon: Icon(Icons.search, color: fg),
        onPressed: () {
          setState(() {
            _isSearchExpanded = true;
            _activeMenu = "";
          });
        },
      ),
    );
  }

  Widget _buildInspectorPanel(Color bg, Color fg, Color accent) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: [
            Icon(Icons.precision_manufacturing, color: accent, size: 16),
            const SizedBox(width: 8),
            Text(_selectionInfo, style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          _buildBtn("DEMOLISH", Icons.delete, Colors.red, 0),
          const SizedBox(width:8),
          _buildBtn("FOREST", Icons.park, Colors.green, 4),
          const SizedBox(width:8),
          _buildBtn("ROAD", Icons.edit_road, Colors.grey, 1),
          const SizedBox(width:8),
          _buildBtn("HOUSE", Icons.home, Colors.blue, 2),
          const SizedBox(width:8),
          _buildBtn("FACTORY", Icons.factory, Colors.purple, 3),
          const SizedBox(width:8),
          _buildBtn("COMMERCIAL", Icons.business_center, Colors.cyan, 5),
        ]))
      ]),
    );
  }

  Widget _buildBtn(String l, IconData i, Color c, int t) {
    return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.withOpacity(0.15),
          foregroundColor: c,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: () => _modifyGrid(t), icon: Icon(i, size:14), label: Text(l, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))
    );
  }
}

class IntelligentGridPainter extends CustomPainter {
  final List<List<int>> grid;
  final LatLng gridOrigin;
  final MapCamera camera;
  final Set<math.Point<int>> selectedCells;
  final MapMode mode;
  final bool isEditMode;
  final MapStyle theme;

  IntelligentGridPainter({
    required this.grid, required this.gridOrigin, required this.camera,
    required this.selectedCells, required this.mode, required this.isEditMode, required this.theme
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    try {
      double tileMeters = 10.0;
      int gridSize = 60;
      double latDegrees = (gridSize * tileMeters) / 111000;
      double lonDegrees = (gridSize * tileMeters) / (111000 * math.cos(math.pi * gridOrigin.latitude / 180));
      
      double startLat = gridOrigin.latitude - (latDegrees / 2);
      double startLon = gridOrigin.longitude - (lonDegrees / 2);
      double stepLat = latDegrees / gridSize;
      double stepLon = lonDegrees / gridSize;

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

          bool isSel = selectedCells.contains(math.Point(x, y));
          _drawCell(canvas, baseRect, type, isSel);
        }
      }
    } catch (e) { }
  }

  void _drawCell(Canvas canvas, Rect base, int type, bool isSel) {
    Color fillColor = Colors.transparent;
    Color borderColor = Colors.transparent;
    double borderWidth = 0.0;

    // 🌟 DEDICATED SATELLITE STYLING
    if (theme == MapStyle.satelliteMap) {
      if (mode == MapMode.satellite) {
        // Reality Glass: High tech glowing edges, almost empty inside
        if (type != 0) {
          fillColor = Colors.cyanAccent.withOpacity(0.05);
          borderColor = Colors.cyanAccent.withOpacity(0.4);
          borderWidth = 1.0;
        }
      }
      else if (mode == MapMode.zoning) {
        // Zoning: Thin neon outlines so we can see the real buildings inside
        if (type == 1) { fillColor = Colors.white24; } // Roads
        else if (type == 2) { fillColor = Colors.amber.withOpacity(0.2); borderColor = Colors.amber; borderWidth = 1.5; }
        else if (type == 3) { fillColor = Colors.purpleAccent.withOpacity(0.2); borderColor = Colors.purpleAccent; borderWidth = 1.5; }
        else if (type == 4) { fillColor = Colors.greenAccent.withOpacity(0.2); borderColor = Colors.greenAccent; borderWidth = 1.0; }
        else if (type == 5) { fillColor = Colors.cyanAccent.withOpacity(0.2); borderColor = Colors.cyanAccent; borderWidth = 1.5; }
      }
      else if (mode == MapMode.heatmap) {
        // Heatmap: Vibrant gradient-like glowing spots
        if (type == 3) { fillColor = Colors.redAccent.withOpacity(0.6); }
        else if (type == 5 || type == 1 || type == 2) { fillColor = Colors.orangeAccent.withOpacity(0.2); }
        else if (type == 4) { fillColor = Colors.greenAccent.withOpacity(0.4); }
      }
    }
    // 🎨 STANDARD STYLING (For Dark Mode, Blueprint, etc)
    else {
      if (mode == MapMode.satellite) {
        if (type == 4) fillColor = Colors.green.withOpacity(0.15);
        else if (type != 0) fillColor = Colors.cyanAccent.withOpacity(0.15);
      }
      else if (mode == MapMode.zoning) {
        if (type == 1) fillColor = Colors.grey;
        else if (type == 2) fillColor = Colors.amber.withOpacity(0.6);
        else if (type == 3) fillColor = Colors.purple.withOpacity(0.6);
        else if (type == 4) fillColor = Colors.green.withOpacity(0.6);
        else if (type == 5) fillColor = Colors.cyan.withOpacity(0.7);
      }
      else if (mode == MapMode.heatmap) {
        if (type == 3) fillColor = Colors.redAccent.withOpacity(0.7);
        else if (type == 1 || type == 2) fillColor = Colors.orangeAccent.withOpacity(0.3);
        else if (type == 4) fillColor = Colors.greenAccent.withOpacity(0.6);
        else if (type == 5) fillColor = Colors.orangeAccent.withOpacity(0.5);
      }
    }

    if (isSel) {
      fillColor = Colors.white.withOpacity(0.3);
      borderColor = Colors.white;
      borderWidth = 2.0;
    }

    // Paint the fill
    if (fillColor.opacity > 0) {
      canvas.drawRect(base, Paint()..color = fillColor);
    }
    // Paint the borders
    if (borderWidth > 0) {
      canvas.drawRect(base, Paint()..style = PaintingStyle.stroke..color = borderColor..strokeWidth = borderWidth);
    }
    // Edit mode grid lines
    if (isEditMode && !isSel) {
      canvas.drawRect(base, Paint()..style = PaintingStyle.stroke..color = Colors.white24..strokeWidth = 0.5);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
