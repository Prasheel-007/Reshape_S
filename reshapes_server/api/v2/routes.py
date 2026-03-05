from flask import Blueprint, jsonify, request
import requests
import math

v2 = Blueprint('v2', __name__)

# --- V2 CONFIGURATION ---
GRID_SIZE = 60  
TILE_METERS = 10 
EMPTY, ROAD, HOUSE, FACTORY, PARK = 0, 1, 2, 3, 4

OVERPASS_ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",      
    "https://overpass.kumi.systems/api/interpreter", 
    "https://lz4.overpass-api.de/api/interpreter"    
]

def get_osm_data(lat, lon):
    radius = (GRID_SIZE * TILE_METERS) / 1.5 
    headers = {'User-Agent': 'ReshapeS_CityPlanner/3.1'}
    
    query = f"""
    [out:json][timeout:25];
    (
      way(around:{radius},{lat},{lon})["highway"~"primary|secondary|tertiary|residential"];
      way(around:{radius},{lat},{lon})["building"];
      way(around:{radius},{lat},{lon})["landuse"~"industrial|commercial|residential|forest"];
      way(around:{radius},{lat},{lon})["leisure"~"park|nature_reserve"];
      way(around:{radius},{lat},{lon})["natural"~"water|wood"];
      way(around:{radius},{lat},{lon})["power"~"plant|generator"];
    );
    (._;>;);
    out body;
    """
    
    for endpoint in OVERPASS_ENDPOINTS:
        try:
            print(f"📡 Trying Overpass Server: {endpoint}...")
            response = requests.get(endpoint, params={'data': query}, headers=headers, timeout=10)
            if response.status_code == 200:
                data = response.json()
                print(f"✅ Success! Found {len(data.get('elements', []))} elements.")
                return data
            elif response.status_code == 429:
                print(f"⚠️ {endpoint} is rate-limiting us.")
        except Exception as e:
            print(f"❌ Server {endpoint} failed.")
            
    print("🚨 ALL SERVERS BUSY. Returning empty data.")
    return None

# --- 📐 EXACT MATH FOR POLYGONS ---
def latlon_to_grid_exact(lat, lon, min_lat, min_lon, lat_scale, lon_scale):
    x = (lat - min_lat) * lat_scale
    y = (lon - min_lon) * lon_scale
    return x, y

def point_in_polygon(x, y, poly):
    inside = False
    n = len(poly)
    p1x, p1y = poly[0]
    for i in range(1, n + 1):
        p2x, p2y = poly[i % n]
        if min(p1y, p2y) < y <= max(p1y, p2y):
            if x <= max(p1x, p2x):
                if p1y != p2y:
                    xints = (y - p1y) * (p2x - p1x) / (p2y - p1y) + p1x
                    if p1x == p2x or x <= xints:
                        inside = not inside
        p1x, p1y = p2x, p2y
    return inside

def fill_polygon(poly, grid, tile_type):
    if not poly or len(poly) < 3: return
    
    min_x = max(0, int(min([p[0] for p in poly])))
    max_x = min(GRID_SIZE - 1, int(max([p[0] for p in poly])))
    min_y = max(0, int(min([p[1] for p in poly])))
    max_y = min(GRID_SIZE - 1, int(max([p[1] for p in poly])))

    for x in range(min_x, max_x + 1):
        for y in range(min_y, max_y + 1):
            if point_in_polygon(x + 0.5, y + 0.5, poly): 
                # Notice we removed the "only paint on EMPTY" rule so background layers work!
                grid[x][y] = tile_type

def interpolate_line(p1, p2, grid, tile_type):
    x1, y1 = int(p1[0]), int(p1[1])
    x2, y2 = int(p2[0]), int(p2[1])
    dx, dy = abs(x2 - x1), abs(y2 - y1)
    sx, sy = (1 if x1 < x2 else -1), (1 if y1 < y2 else -1)
    err = dx - dy
    
    while True:
        if 0 <= x1 < GRID_SIZE and 0 <= y1 < GRID_SIZE:
            # Roads paint over EVERYTHING!
            grid[x1][y1] = tile_type
        if x1 == x2 and y1 == y2: break
        e2 = 2 * err
        if e2 > -dy:
            err -= dy
            x1 += sx
        if e2 < dx:
            err += dx
            y1 += sy

def calculate_real_metrics(grid):
    pollution = 0
    sustainability = 50 
    budget_used = 0
    
    house_count = 0
    factory_count = 0
    park_count = 0
    road_tiles = 0
    
    for r in range(GRID_SIZE):
        for c in range(GRID_SIZE):
            tile = grid[r][c]
            if tile == HOUSE: house_count += 1
            elif tile == FACTORY: factory_count += 1
            elif tile == PARK: park_count += 1
            elif tile == ROAD: road_tiles += 1
            
    pollution += (factory_count * 20)  
    pollution += (road_tiles * 2)      
    pollution = max(0, pollution - (park_count * 10))
    
    sustainability -= (pollution / 30) 
    sustainability += (park_count * 0.8)
    if house_count > 0 and factory_count > (house_count * 2):
        sustainability -= 15 
        
    final_score = max(0, min(100, int(sustainability)))
    
    return {
        "score": final_score,
        "metrics": {
            "pollution": int(pollution),
            "budget": (road_tiles * 500) + (house_count * 2000) + (factory_count * 10000),
            "population": house_count * 4 
        }
    }

@v2.route('/get_chunk', methods=['GET'])
def get_real_chunk():
    lat = float(request.args.get('lat', 17.4435))
    lon = float(request.args.get('lon', 78.3772))
    
    grid = [[EMPTY for _ in range(GRID_SIZE)] for _ in range(GRID_SIZE)]
    data = get_osm_data(lat, lon)
    
    if not data: 
        return jsonify({"grid": grid, "status": "offline", "score": 0, "metrics": {"pollution":0, "budget":0}})

    lat_dist = 111000
    lon_dist = 111000 * math.cos(math.radians(lat))
    total_m = GRID_SIZE * TILE_METERS
    
    min_lat = lat - (total_m / lat_dist) / 2
    min_lon = lon - (total_m / lon_dist) / 2
    lat_scale = GRID_SIZE / (total_m / lat_dist)
    lon_scale = GRID_SIZE / (total_m / lon_dist)

    nodes = {n['id']: (n['lat'], n['lon']) for n in data['elements'] if n['type'] == 'node'}
    
    # 🎨 1. CREATE BUCKETS FOR THE LAYERS
    parks = []
    zones = []
    buildings = []
    roads = []
    
    for el in data['elements']:
        if el['type'] != 'way': continue
        tags = el.get('tags', {})
        t_type = EMPTY
        
        # Prioritize Landuse (Zoning)
        if 'landuse' in tags:
            lu = tags['landuse']
            if lu in ['industrial', 'commercial']: t_type = FACTORY 
            elif lu in ['forest', 'grass', 'meadow']: t_type = PARK 
            elif lu == 'residential': t_type = HOUSE 
            
        # Fallback to specific building/nature tags
        if t_type == EMPTY:
            if 'power' in tags: t_type = FACTORY
            elif 'leisure' in tags or 'natural' in tags: t_type = PARK
            elif 'building' in tags: t_type = HOUSE
            elif 'highway' in tags: t_type = ROAD
        
        if t_type == EMPTY: continue
        
        if 'nodes' in el:
            way_nodes = [nodes[nid] for nid in el['nodes'] if nid in nodes]
            poly_points = [latlon_to_grid_exact(p[0], p[1], min_lat, min_lon, lat_scale, lon_scale) for p in way_nodes]

            is_closed_polygon = len(poly_points) > 2 and poly_points[0] == poly_points[-1]
            
            # 🎨 2. SORT SHAPES INTO THE RIGHT BUCKET
            if t_type == ROAD or not is_closed_polygon:
                roads.append((poly_points, t_type))
            elif t_type == PARK:
                parks.append((poly_points, t_type))
            elif 'building' in tags:
                buildings.append((poly_points, t_type))
            else:
                zones.append((poly_points, t_type))

    # 🖌️ 3. DRAW IN THE CORRECT ORDER (Z-Indexing)
    
    # Bottom Layer: Big land zones and parks
    for poly, t in parks: fill_polygon(poly, grid, t)
    for poly, t in zones: fill_polygon(poly, grid, t)
    
    # Middle Layer: Specific buildings on top of zones
    for poly, t in buildings: fill_polygon(poly, grid, t)
    
    # Top Layer: Roads slice through everything
    for lines, t in roads:
        for i in range(len(lines) - 1):
            interpolate_line(lines[i], lines[i+1], grid, t)
    
    analysis = calculate_real_metrics(grid)

    return jsonify({
        "grid": grid, 
        "center": [lat, lon],
        "score": analysis['score'], 
        "metrics": analysis['metrics'] 
    })