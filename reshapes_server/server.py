from flask import Flask, jsonify, request
from flask_cors import CORS
import random

app = Flask(__name__)
CORS(app)  # Allows Flutter to talk to Python

# --- CONFIGURATION ---
GRID_SIZE = 15
# Tile IDs: 
# 0=Grass, 1=Road(V), 2=House, 3=Factory, 4=Park, 5=Road(H), 6=Junction

# --- LOGIC: SMART CITY GENERATOR ---
@app.route('/api/generate_random', methods=['GET'])
def generate_random_world():
    """
    Generates a STRUCTURED city.
    1. Fills map with Grass.
    2. Draws a Road Network with Vertical(1), Horizontal(5), and Junction(6).
    3. Places Buildings only near roads.
    """
    # 1. Start with blank Grass canvas
    grid = [[0 for _ in range(GRID_SIZE)] for _ in range(GRID_SIZE)]
    
    # 2. Draw Roads (The Skeleton)
    mid = GRID_SIZE // 2
    for i in range(GRID_SIZE):
        grid[mid][i] = 5  # ID 5: Horizontal Road
        grid[i][mid] = 1  # ID 1: Vertical Road
    
    # FIX: Place the Intersection at the center
    grid[mid][mid] = 6    # ID 6: The Junction
        
    # 3. Place Buildings (The Flesh)
    for x in range(GRID_SIZE):
        for y in range(GRID_SIZE):
            # Skip if this tile is already a road
            if grid[x][y] in [1, 5, 6]:
                continue
                
            # Check neighbors
            is_near_road = False
            neighbors = []
            if x > 0: neighbors.append(grid[x-1][y])
            if x < GRID_SIZE-1: neighbors.append(grid[x+1][y])
            if y > 0: neighbors.append(grid[x][y-1])
            if y < GRID_SIZE-1: neighbors.append(grid[x][y+1])
            
            for n in neighbors:
                if n in [1, 5, 6]: # If near ANY road piece
                    is_near_road = True
                    break
            
            # DECISION: Only build if near a road
            if is_near_road:
                roll = random.randint(1, 100)
                if roll < 50:    # 50% chance of House
                    grid[x][y] = 2 
                elif roll < 65:  # 15% chance of Factory
                    grid[x][y] = 3
                elif roll < 80:  # 15% chance of Park
                    grid[x][y] = 4
                # Remaining 20% stays Grass

    print("✅ Smart City Generated with Junctions")
    return jsonify({
        "status": "success",
        "grid": grid,
        "message": "Structured City Generated"
    })

# --- LOGIC: SCORING ENGINE ---
@app.route('/api/calculate_score', methods=['POST'])
def calculate_score():
    data = request.json
    grid = data.get('grid', [])
    
    pollution = 0
    happiness = 50
    budget = 100000
    
    for row in grid:
        for tile_id in row:
            if tile_id == 2: # House
                pollution += 1
                happiness += 2
                budget += 500 
            elif tile_id == 3: # Factory
                pollution += 15
                happiness -= 10
                budget += 2000 
            elif tile_id == 4: # Park
                pollution -= 5
                happiness += 10
                budget -= 200 

    score = 100 - pollution + (happiness * 0.5)
    final_score = max(0, min(100, int(score)))

    return jsonify({
        "score": final_score,
        "metrics": {
            "pollution": pollution,
            "happiness": happiness,
            "budget": budget
        }
    })

if __name__ == '__main__':
    print("🚀 Reshape_S Brain is Active on Port 5000...")
    app.run(host='0.0.0.0', port=5000, debug=True)