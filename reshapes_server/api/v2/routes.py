from flask import Blueprint, jsonify, request
import requests
import math

v2 = Blueprint('v2', __name__)

# --- V2 CONFIGURATION ---
GRID_SIZE = 60  
TILE_METERS = 10 
EMPTY, ROAD, HOUSE, FACTORY, PARK, WATER = 0, 1, 2, 3, 4, 7

# --- HELPER: FETCH REAL MAP DATA ---
def get_osm_data(lat, lon):
    overpass_url = "https://overpass-api.de/api/interpreter"
    radius = (GRID_SIZE * TILE_METERS) / 1.5 
    headers = {'User-Agent': 'ReshapeS_Project/2.0'}
    
    query = f"""
    [out:json];
    (
      way(around:{radius},{lat},{lon})["highway"];
      way(around:{radius},{lat},{lon})["building"];
      way(around:{radius},{lat},{lon})["leisure"="park"];
      way(around:{radius},{lat},{lon})["natural"="water"];
    );
    (._;>;);
    out body;
    """
    try:
        response = requests.get(overpass_url, params={'data': query}, headers=headers)
        return response.json() if response.status_code == 200 else None
    except:
        return None

# --- HELPER: MATH (GPS -> GRID) ---
def latlon_to_grid(lat, lon, min_lat, min_lon, lat_scale, lon_scale):
    x = int((lat - min_lat) * lat_scale)
    y = int((lon - min_lon) * lon_scale)
    if 0 <= x < GRID_SIZE and 0 <= y < GRID_SIZE: return x, y
    return None

def interpolate_line(p1, p2, grid, tile_type):
    x1, y1 = p1
    x2, y2 = p2
    dx, dy = abs(x2 - x1), abs(y2 - y1)
    sx, sy = (1 if x1 < x2 else -1), (1 if y1 < y2 else -1)
    err = dx - dy
    
    while True:
        if 0 <= x1 < GRID_SIZE and 0 <= y1 < GRID_SIZE: grid[x1][y1] = tile_type
        if x1 == x2 and y1 == y2: break
        e2 = 2 * err
        if e2 > -dy:
            err -= dy
            x1 += sx
        if e2 < dx:
            err += dx
            y1 += sy

# --- THE MAIN API ENDPOINT ---
@v2.route('/get_chunk', methods=['GET'])
def get_real_chunk():
    # 1. Get Coordinates (Default: HITEC City)
    lat = float(request.args.get('lat', 17.4435))
    lon = float(request.args.get('lon', 78.3772))
    
    # 2. Prepare Data
    grid = [[EMPTY for _ in range(GRID_SIZE)] for _ in range(GRID_SIZE)]
    data = get_osm_data(lat, lon)
    
    if not data: return jsonify({"grid": grid, "status": "offline"})

    # 3. Setup Math Projections
    lat_dist = 111000
    lon_dist = 111000 * math.cos(math.radians(lat))
    total_m = GRID_SIZE * TILE_METERS
    
    min_lat = lat - (total_m / lat_dist) / 2
    min_lon = lon - (total_m / lon_dist) / 2
    lat_scale = GRID_SIZE / (total_m / lat_dist)
    lon_scale = GRID_SIZE / (total_m / lon_dist)

    # 4. Fill Grid
    nodes = {n['id']: (n['lat'], n['lon']) for n in data['elements'] if n['type'] == 'node'}
    
    for el in data['elements']:
        if el['type'] != 'way': continue
        tags = el.get('tags', {})
        
        t_type = EMPTY
        if 'highway' in tags: t_type = ROAD
        elif 'building' in tags: t_type = HOUSE
        elif 'leisure' in tags: t_type = PARK
        elif 'natural' in tags: t_type = WATER
        
        if t_type == EMPTY: continue
        
        if 'nodes' in el:
            way_nodes = [nodes[nid] for nid in el['nodes'] if nid in nodes]
            for i in range(len(way_nodes) - 1):
                p1_gps, p2_gps = way_nodes[i], way_nodes[i+1]
                p1 = latlon_to_grid(p1_gps[0], p1_gps[1], min_lat, min_lon, lat_scale, lon_scale)
                p2 = latlon_to_grid(p2_gps[0], p2_gps[1], min_lat, min_lon, lat_scale, lon_scale)
                if p1 and p2: interpolate_line(p1, p2, grid, t_type)

    return jsonify({"grid": grid, "center": [lat, lon]})