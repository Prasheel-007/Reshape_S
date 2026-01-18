from flask import Flask, jsonify, request
from flask_cors import CORS
import random

app = Flask(__name__)
CORS(app)

# --- CONFIGURATION ---
GRID_SIZE = 20  

# TILE CODES
GRASS = 0
ROAD_V = 1   # Vertical
HOUSE = 2
FACTORY = 3
PARK = 4
ROAD_H = 5   # Horizontal
ROAD_X = 6   # Junction

# --- ALGORITHMS ---

def generate_real_world_city():
    """
    Generates a 'Zoned City' Layout (SimCity Style).
    1. Creates a grid of Arterial Roads (City Blocks).
    2. Assigns a 'Zone Type' to each block (Residential, Industrial, Nature).
    3. Fills the blocks based on their zone density.
    """
    # 1. Start with Grass
    grid = [[GRASS for _ in range(GRID_SIZE)] for _ in range(GRID_SIZE)]
    
    # 2. CREATE ROAD NETWORK (The Grid)
    # We place roads at regular intervals to create 'City Blocks'
    block_size = random.randint(4, 6) # Blocks are 4-6 tiles wide
    
    # Vertical Roads
    for c in range(2, GRID_SIZE, block_size):
        for r in range(GRID_SIZE):
            grid[r][c] = ROAD_V

    # Horizontal Roads
    for r in range(2, GRID_SIZE, block_size):
        for c in range(GRID_SIZE):
            if grid[r][c] == ROAD_V:
                grid[r][c] = ROAD_X # Create Intersection
            else:
                grid[r][c] = ROAD_H

    # 3. POPULATE ZONES (The Buildings)
    # We iterate through the empty spaces (blocks) and decide what they are.
    
    for r in range(GRID_SIZE):
        for c in range(GRID_SIZE):
            # Skip if it's a road
            if grid[r][c] != GRASS:
                continue
            
            # Determine Zone based on location
            # Center of map = Industrial/Dense
            # Edges of map = Residential/Parks
            
            dist_to_center = abs(r - GRID_SIZE//2) + abs(c - GRID_SIZE//2)
            
            # Roll for type
            roll = random.random()
            
            if dist_to_center < 8: 
                # Inner City (Factories & Dense Housing)
                if roll < 0.3: grid[r][c] = FACTORY
                elif roll < 0.8: grid[r][c] = HOUSE
                else: grid[r][c] = GRASS # Alleyways
            else:
                # Suburbs (Parks & Housing)
                if roll < 0.1: grid[r][c] = FACTORY # Rare factory
                elif roll < 0.5: grid[r][c] = HOUSE
                elif roll < 0.8: grid[r][c] = PARK
                else: grid[r][c] = GRASS # Backyards

    # 4. CLEANUP PASS
    # Ensure no building is trapped without road access (Optional polish)
    # (The grid structure guarantees most have access, so we keep it simple)

    return grid

def calculate_metrics(grid):
    """
    Heuristic Scoring Engine
    """
    pollution = 0
    sustainability = 50 
    budget_used = 0
    
    factories = []
    houses = []
    parks = []
    
    # 1. Scan Grid
    for r in range(len(grid)):
        for c in range(len(grid[r])):
            tile = grid[r][c]
            if tile == HOUSE: houses.append((r, c))
            elif tile == FACTORY: factories.append((r, c))
            elif tile == PARK: parks.append((r, c))
            
            if tile == ROAD_V or tile == ROAD_H: budget_used += 10
            elif tile == HOUSE: budget_used += 50
            elif tile == FACTORY: budget_used += 200
            elif tile == PARK: budget_used += 100

    # 2. Rules
    for f in factories:
        pollution += 100 
        for h in houses:
            dist = abs(f[0] - h[0]) + abs(f[1] - h[1])
            if dist < 5:
                sustainability -= 5 
    
    sustainability += len(parks) * 5
    if len(houses) < 5: sustainability -= 10
    
    final_score = max(0, min(100, int(sustainability)))
    
    return {
        "score": final_score,
        "metrics": {
            "pollution": pollution,
            "budget": budget_used,
            "population": len(houses) * 4
        }
    }

# --- API ENDPOINTS ---

@app.route('/', methods=['GET'])
def home():
    return "Reshape_S AI Brain is Running!"

@app.route('/api/generate_random', methods=['GET'])
def get_random_world():
    # USES THE NEW REALISTIC GENERATOR
    grid = generate_real_world_city()
    return jsonify({"grid": grid})

@app.route('/api/calculate_score', methods=['POST'])
def get_score():
    data = request.get_json()
    grid = data.get('grid', [])
    metrics = calculate_metrics(grid)
    return jsonify(metrics)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)