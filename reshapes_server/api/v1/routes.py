from flask import Blueprint, jsonify, request
import random

# Create the Blueprint
v1 = Blueprint('v1', __name__)

# --- V1 CONSTANTS ---
GRID_SIZE = 20  
GRASS = 0
ROAD_V = 1   
HOUSE = 2
FACTORY = 3
PARK = 4
ROAD_H = 5   
ROAD_X = 6   

# --- V1 LOGIC ---
def generate_random_city():
    grid = [[GRASS for _ in range(GRID_SIZE)] for _ in range(GRID_SIZE)]
    
    # Simple Roads
    block_size = random.randint(4, 6)
    for c in range(2, GRID_SIZE, block_size):
        for r in range(GRID_SIZE):
            grid[r][c] = ROAD_V

    for r in range(2, GRID_SIZE, block_size):
        for c in range(GRID_SIZE):
            if grid[r][c] == ROAD_V:
                grid[r][c] = ROAD_X 
            else:
                grid[r][c] = ROAD_H

    # Simple Zoning
    for r in range(GRID_SIZE):
        for c in range(GRID_SIZE):
            if grid[r][c] != GRASS: continue
            dist = abs(r - GRID_SIZE//2) + abs(c - GRID_SIZE//2)
            roll = random.random()
            
            if dist < 8: 
                if roll < 0.3: grid[r][c] = FACTORY
                elif roll < 0.8: grid[r][c] = HOUSE
            else:
                if roll < 0.1: grid[r][c] = FACTORY 
                elif roll < 0.5: grid[r][c] = HOUSE
                elif roll < 0.8: grid[r][c] = PARK
    return grid

def calculate_metrics(grid):
    pollution = 0
    sustainability = 50 
    budget_used = 0
    houses = []
    factories = []
    parks = []

    for r in range(len(grid)):
        for c in range(len(grid[r])):
            tile = grid[r][c]
            if tile == HOUSE: houses.append((r,c))
            elif tile == FACTORY: factories.append((r,c))
            elif tile == PARK: parks.append((r,c))

            if tile == ROAD_V or tile == ROAD_H: budget_used += 10
            elif tile == HOUSE: budget_used += 50
            elif tile == FACTORY: budget_used += 200
            elif tile == PARK: budget_used += 100

    for f in factories:
        pollution += 100 
        for h in houses:
            if (abs(f[0]-h[0]) + abs(f[1]-h[1])) < 5:
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

# --- V1 ROUTES ---
# Notice: No '/api' here because app.py handles that part
@v1.route('/generate_random', methods=['GET'])
def get_random_world():
    grid = generate_random_city()
    return jsonify({"grid": grid})

@v1.route('/calculate_score', methods=['POST'])
def get_score():
    data = request.get_json()
    metrics = calculate_metrics(data.get('grid', []))
    return jsonify(metrics)