from flask import Flask, jsonify, request
from flask_cors import CORS
import random
import math

app = Flask(__name__)
CORS(app)  # Allow the Flutter app to talk to this server

# --- CONFIGURATION ---
GRID_SIZE = 20  # Bigger map for better simulation

# TILE CODES
GRASS = 0
ROAD_V = 1   # Vertical
HOUSE = 2
FACTORY = 3
PARK = 4
ROAD_H = 5   # Horizontal
ROAD_X = 6   # Junction

# --- ALGORITHMS ---

def generate_smart_road_network():
    """
    Uses a 'Random Walk' algorithm to create a connected city layout.
    Then applies a 'Tile Logic' pass to fix road directions (Horizontal vs Vertical).
    """
    # 1. Start with empty grass grid
    grid = [[GRASS for _ in range(GRID_SIZE)] for _ in range(GRID_SIZE)]
    
    # 2. Procedural Road Generation (Random Walk)
    x, y = GRID_SIZE // 2, GRID_SIZE // 2
    steps = 100  # Length of the road network
    
    for _ in range(steps):
        grid[x][y] = ROAD_V # Temporarily mark as Vertical Road
        
        # Move random direction
        direction = random.choice(['UP', 'DOWN', 'LEFT', 'RIGHT'])
        if direction == 'UP' and x > 1: x -= 1
        elif direction == 'DOWN' and x < GRID_SIZE - 2: x += 1
        elif direction == 'LEFT' and y > 1: y -= 1
        elif direction == 'RIGHT' and y < GRID_SIZE - 2: y += 1

    # 3. Place Buildings (Constraint: Must be near roads)
    for r in range(GRID_SIZE):
        for c in range(GRID_SIZE):
            if grid[r][c] == GRASS:
                # Check neighbors for a road
                has_road_neighbor = False
                for dr, dc in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
                    nr, nc = r + dr, c + dc
                    if 0 <= nr < GRID_SIZE and 0 <= nc < GRID_SIZE:
                        if grid[nr][nc] in [ROAD_V, ROAD_H, ROAD_X]:
                            has_road_neighbor = True
                
                # Probability to spawn buildings if near road
                if has_road_neighbor:
                    roll = random.random()
                    if roll < 0.15: grid[r][c] = HOUSE
                    elif roll < 0.20: grid[r][c] = FACTORY
                    elif roll < 0.25: grid[r][c] = PARK

    # 4. Auto-Tiling Pass (Fix Road Directions)
    # This logic changes a generic "1" road into Horizontal (5) or Junction (6)
    # based on what is around it.
    for r in range(GRID_SIZE):
        for c in range(GRID_SIZE):
            if grid[r][c] == ROAD_V: # Check if it's a road
                
                # Check neighbors (Up, Down, Left, Right)
                u = r > 0 and grid[r-1][c] in [ROAD_V, 5, 6]
                d = r < GRID_SIZE-1 and grid[r+1][c] in [ROAD_V, 5, 6]
                l = c > 0 and grid[r][c-1] in [ROAD_V, 5, 6]
                ri = c < GRID_SIZE-1 and grid[r][c+1] in [ROAD_V, 5, 6]
                
                neighbor_count = sum([u, d, l, ri])

                if neighbor_count >= 3:
                    grid[r][c] = ROAD_X  # Junction
                elif (l or ri) and not (u or d):
                    grid[r][c] = ROAD_H  # Horizontal
                else:
                    grid[r][c] = ROAD_V  # Keep Vertical

    return grid

def calculate_metrics(grid):
    """
    The Heuristic Scoring Engine.
    Calculates Score (0-100), Pollution, and Budget.
    """
    pollution = 0
    sustainability = 50 # Start at neutral
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
            
            # Budget Calculation
            if tile == ROAD_V or tile == ROAD_H: budget_used += 10
            elif tile == HOUSE: budget_used += 50
            elif tile == FACTORY: budget_used += 200
            elif tile == PARK: budget_used += 100

    # 2. Heuristic Rules
    
    # Rule A: Pollution (Factories close to houses is BAD)
    for f in factories:
        pollution += 100 # Base pollution per factory
        for h in houses:
            # Manhattan Distance
            dist = abs(f[0] - h[0]) + abs(f[1] - h[1])
            if dist < 5:
                sustainability -= 5 # Heavy penalty for proximity
    
    # Rule B: Green Energy (Parks increase sustainability)
    sustainability += len(parks) * 5
    
    # Rule C: Housing Demand (Need enough houses)
    if len(houses) < 5: sustainability -= 10
    
    # Clamp Score
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
    grid = generate_smart_road_network()
    return jsonify({"grid": grid})

@app.route('/api/calculate_score', methods=['POST'])
def get_score():
    data = request.get_json()
    grid = data.get('grid', [])
    metrics = calculate_metrics(grid)
    return jsonify(metrics)

# --- VERCEL GUARD (CRITICAL) ---
# This ensures Vercel handles the start process, not this script.
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)