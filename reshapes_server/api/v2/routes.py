from PIL import Image
import io
from sklearn.neighbors import KNeighborsClassifier
import numpy as np
from flask import Blueprint, jsonify, request
import requests
import math

v2 = Blueprint('v2', __name__)

# --- V2 CONFIGURATION ---
GRID_SIZE = 60  
TILE_METERS = 10 

# 🏢 CATEGORIES
EMPTY, ROAD, HOUSE, FACTORY, PARK, COMMERCIAL = 0, 1, 2, 3, 4, 5

OVERPASS_ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",      
    "https://overpass.kumi.systems/api/interpreter", 
    "https://lz4.overpass-api.de/api/interpreter"    
]

def get_osm_data(lat, lon):
    radius = (GRID_SIZE * TILE_METERS) / 1.5 
    headers = {'User-Agent': 'ReshapeS_CityPlanner/3.3'}
    
    query = f"""
    [out:json][timeout:25];
    (
      way(around:{radius},{lat},{lon})["highway"~"primary|secondary|tertiary|residential"];
      way(around:{radius},{lat},{lon})["building"];
      way(around:{radius},{lat},{lon})["landuse"~"industrial|commercial|residential|forest"];
      way(around:{radius},{lat},{lon})["leisure"~"park|nature_reserve"];
      way(around:{radius},{lat},{lon})["natural"~"water|wood"];
      way(around:{radius},{lat},{lon})["power"~"plant|generator"];
      
      node(around:{radius},{lat},{lon})["amenity"~"hospital|school|college|university|bank|clinic"];
      node(around:{radius},{lat},{lon})["shop"];
      node(around:{radius},{lat},{lon})["office"];
      node(around:{radius},{lat},{lon})["power"~"plant|generator"];
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
        except Exception as e:
            print(f"❌ Server {endpoint} failed: {e}")
            
    return None

# --- EXACT MATH FOR POLYGONS & PINS ---
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
                grid[x][y] = tile_type

def interpolate_line(p1, p2, grid, tile_type):
    x1, y1 = int(p1[0]), int(p1[1])
    x2, y2 = int(p2[0]), int(p2[1])
    dx, dy = abs(x2 - x1), abs(y2 - y1)
    sx, sy = (1 if x1 < x2 else -1), (1 if y1 < y2 else -1)
    err = dx - dy
    
    while True:
        if 0 <= x1 < GRID_SIZE and 0 <= y1 < GRID_SIZE:
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
    
    house_count = 0
    factory_count = 0
    park_count = 0
    road_tiles = 0
    commercial_count = 0
    
    for r in range(GRID_SIZE):
        for c in range(GRID_SIZE):
            tile = grid[r][c]
            if tile == HOUSE: house_count += 1
            elif tile == FACTORY: factory_count += 1
            elif tile == COMMERCIAL: commercial_count += 1
            elif tile == PARK: park_count += 1
            elif tile == ROAD: road_tiles += 1
            
    # 🧠 NEW MATH: Commercial makes money, but pollutes way less than Heavy Industry!
    pollution += (factory_count * 20)  
    pollution += (commercial_count * 5) 
    pollution += (road_tiles * 2)      
    pollution = max(0, pollution - (park_count * 10))
    
    sustainability -= (pollution / 30) 
    sustainability += (park_count * 0.8)
    
    if house_count > 0 and factory_count > (house_count * 2):
        sustainability -= 15 
        
    final_score = max(0, min(100, int(sustainability)))
    
    # 100% Accurate Math: What percentage of this map is nature?
    total_blocks = GRID_SIZE * GRID_SIZE
    green_coverage = round((park_count / total_blocks) * 100, 1) if total_blocks > 0 else 0
    
    return {
        "score": final_score,
        "metrics": {
            "pollution": int(pollution),
            "green_coverage": green_coverage, 
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
        return jsonify({"grid": grid, "status": "offline", "score": 0, "metrics": {"pollution":0, "green_coverage":0, "population":0}})

    lat_dist = 111000
    lon_dist = 111000 * math.cos(math.radians(lat))
    total_m = GRID_SIZE * TILE_METERS
    
    min_lat = lat - (total_m / lat_dist) / 2
    min_lon = lon - (total_m / lon_dist) / 2
    lat_scale = GRID_SIZE / (total_m / lat_dist)
    lon_scale = GRID_SIZE / (total_m / lon_dist)

    nodes = {n['id']: (n['lat'], n['lon']) for n in data['elements'] if n['type'] == 'node'}
    
    parks = []
    zones = []
    buildings = []
    roads = []
    
    for el in data['elements']:
        tags = el.get('tags', {})
        t_type = EMPTY
        
        # 🧠 INTELLIGENT TAG PARSER
        if 'landuse' in tags:
            lu = tags['landuse']
            if lu == 'industrial': t_type = FACTORY 
            elif lu == 'commercial': t_type = COMMERCIAL 
            elif lu in ['forest', 'grass', 'meadow']: t_type = PARK 
            elif lu == 'residential': t_type = HOUSE 
            
        if t_type == EMPTY:
            if 'power' in tags: t_type = FACTORY
            elif 'office' in tags or 'shop' in tags or 'amenity' in tags: t_type = COMMERCIAL
            elif 'leisure' in tags or 'natural' in tags: t_type = PARK
            elif 'building' in tags: t_type = HOUSE
            elif 'highway' in tags: t_type = ROAD

        if t_type == EMPTY: continue
        
        # 📍 SMART PIN ENGINE: Inflate single points into blocks!
        if el['type'] == 'node':
            cx, cy = latlon_to_grid_exact(el['lat'], el['lon'], min_lat, min_lon, lat_scale, lon_scale)
            poly_points = [
                (cx-1, cy-1), (cx+1, cy-1), (cx+1, cy+1), (cx-1, cy+1)
            ]
            if t_type == PARK: parks.append((poly_points, t_type))
            else: buildings.append((poly_points, t_type))
            continue
            
        if 'nodes' in el:
            way_nodes = [nodes[nid] for nid in el['nodes'] if nid in nodes]
            poly_points = [latlon_to_grid_exact(p[0], p[1], min_lat, min_lon, lat_scale, lon_scale) for p in way_nodes]

            is_closed_polygon = len(poly_points) > 2 and poly_points[0] == poly_points[-1]
            
            if t_type == ROAD or not is_closed_polygon: roads.append((poly_points, t_type))
            elif t_type == PARK: parks.append((poly_points, t_type))
            elif 'building' in tags: buildings.append((poly_points, t_type))
            else: zones.append((poly_points, t_type))

    # DRAW IN THE CORRECT ORDER
    for poly, t in parks: fill_polygon(poly, grid, t)
    for poly, t in zones: fill_polygon(poly, grid, t)
    for poly, t in buildings: fill_polygon(poly, grid, t)
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

# Helper function: Downloads and stitches 3x3 Esri satellite tiles for perfect alignment
def get_esri_tile(lat, lon, zoom=17):
    import math
    from PIL import Image
    import io

    # 1. Math to find the Center Tile
    lat_rad = math.radians(lat)
    n = 2.0 ** zoom
    x_exact = (lon + 180.0) / 360.0 * n
    y_exact = (1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n
    
    xtile = int(x_exact)
    ytile = int(y_exact)
    
    # Pixel offset of the center coordinate WITHIN the center tile
    px_x = int((x_exact - xtile) * 256)
    px_y = int((y_exact - ytile) * 256)

    # 2. Fetch a 3x3 Grid of Tiles
    stitched_img = Image.new('RGB', (256 * 3, 256 * 3))
    
    headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}
    
    for dy in [-1, 0, 1]:
        for dx in [-1, 0, 1]:
            cur_x = xtile + dx
            cur_y = ytile + dy
            url = f"https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{zoom}/{cur_y}/{cur_x}"
            try:
                response = requests.get(url, headers=headers, timeout=5)
                if response.status_code == 200:
                    img = Image.open(io.BytesIO(response.content)).convert('RGB')
                    
                    # Paste into the 3x3 grid
                    paste_x = (dx + 1) * 256
                    paste_y = (dy + 1) * 256
                    stitched_img.paste(img, (paste_x, paste_y))
            except Exception as e:
                print(f"Failed to fetch tile {cur_x},{cur_y}: {e}")

    # 3. Crop a perfectly centered 600x600 px area around the user's coordinate
    # Zoom level 17 is roughly ~1.19 meters per pixel at the equator.
    # To get a 600m view, 600px is a solid approximation.
    crop_size = 600
    half_crop = crop_size // 2
    
    # Calculate exact center pixel in the 3x3 stitched image
    center_px_x = 256 + px_x  # 256 is the offset of the middle tile
    center_px_y = 256 + px_y
    
    left = center_px_x - half_crop
    top = center_px_y - half_crop
    right = center_px_x + half_crop
    bottom = center_px_y + half_crop
    
    cropped_img = stitched_img.crop((left, top, right, bottom))
    
    # Resize to exact grid resolution needed by the AI (4 pixels per 10m block = 240x240)
    final_img = cropped_img.resize((GRID_SIZE * 4, GRID_SIZE * 4), Image.Resampling.LANCZOS)
    return final_img

@v2.route('/run_ai_survey', methods=['POST'])
def run_ai_survey():
    try:
        data = request.json
        grid = data.get('grid', [])
        lat = data.get('lat') 
        lon = data.get('lon')
        
        if not grid or not lat or not lon:
            return jsonify({"status": "error", "message": "Missing map data or GPS coordinates"})

        grid_array = np.array(grid)
        rows, cols = grid_array.shape
        
        # 1. VISION ENGINE: Download the high-detail image FIRST
        img = get_esri_tile(lat, lon, zoom=17)
        if not img:
             return jsonify({"status": "error", "message": "AI could not fetch satellite feed."})
        
        pixels = np.array(img)
        
        # 2. FEATURE EXTRACTION & ML TRAINING
        X_train = [] 
        y_train = [] 
        
        cell_features = {} 
        
        for r in range(rows):
            for c in range(cols):
                block = pixels[r*4:(r+1)*4, c*4:(c+1)*4]
                
                avg_R = np.mean(block[:,:,0])
                avg_G = np.mean(block[:,:,1])
                avg_B = np.mean(block[:,:,2])
                variance = np.var(block) # Texture
                
                # 🔪 NEW: Sobel Edge Detection (Approximation for speed)
                # Helps distinguish between flat grey road and structured grey building roofs
                gray_block = np.mean(block, axis=2)
                dx = np.abs(np.diff(gray_block, axis=1, append=gray_block[:, -1:]))
                dy = np.abs(np.diff(gray_block, axis=0, append=gray_block[-1:, :]))
                edge_intensity = np.mean(dx) + np.mean(dy)
                
                features = [avg_R, avg_G, avg_B, variance, edge_intensity]
                cell_features[(r, c)] = features
                
                val = grid_array[r][c]
                
                # 🔥 FIX 1: Don't let the AI learn from empty dirt!
                if val in [HOUSE, FACTORY, COMMERCIAL]:
                    # Only train on buildings if they actually have high texture (roofs/edges)
                    if variance > 80: 
                        X_train.append(features)
                        y_train.append(val)
                elif val in [PARK, ROAD]:
                    X_train.append(features)
                    y_train.append(val)
        
        knn = None
        if len(X_train) > 10: 
            knn = KNeighborsClassifier(n_neighbors=5, weights='distance')
            knn.fit(X_train, y_train)
        
        filled_count = 0
        
        # 3. SMART PREDICTION: Fill the empty gaps
        for r in range(rows):
            for c in range(cols):
                if grid_array[r][c] == EMPTY:
                    feats = cell_features[(r, c)]
                    avg_R, avg_G, avg_B, variance, edge_intensity = feats
                    
                    # Rule A: Absolute Nature Check (Very Green)
                    if avg_G > avg_R + 5 and avg_G > avg_B + 5:
                        grid_array[r][c] = PARK
                        filled_count += 1
                        continue
                        
                    # Rule B: The "Dirt/Road Catcher"
                    # If it is flat (low edges) and brownish/grey, leave it empty or make it road
                    if edge_intensity < 15 and variance < 80:
                        continue # Leave it empty!
                        
                    # Rule C: Machine Learning Prediction (KNN)
                    if knn:
                        predicted_type = knn.predict([feats])[0]
                        
                        if predicted_type in [HOUSE, FACTORY, COMMERCIAL, PARK]:
                            # Only trust building predictions if there are actually edges (roofs/structures)
                            if predicted_type != PARK and edge_intensity > 20:
                                grid_array[r][c] = int(predicted_type)
                                filled_count += 1
                            elif predicted_type == PARK:
                                grid_array[r][c] = int(predicted_type)
                                filled_count += 1
                    else:
                        # Fallback heuristic if not enough training data
                        if edge_intensity > 30 and variance > 100 and abs(avg_R - avg_B) < 30:
                            grid_array[r][c] = HOUSE
                            filled_count += 1

        analysis = calculate_real_metrics(grid_array.tolist())

        return jsonify({
            "status": "success",
            "filled_blocks": filled_count,
            "grid": grid_array.tolist(),
            "score": analysis['score'],
            "metrics": analysis['metrics']
        })

    except Exception as e:
        print(f"AI Vision Error: {str(e)}")
        return jsonify({"status": "error", "message": str(e)})