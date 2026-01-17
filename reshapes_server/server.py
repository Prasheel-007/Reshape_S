from flask import Flask, jsonify, request
from flask_cors import CORS
import random

app = Flask(__name__)
CORS(app)  # Allows your Flutter App (Reshape_S) to talk to this server

# --- CONFIGURATION ---
GRID_SIZE = 15  # 15x15 Grid (Optimal for screen size)
TILE_TYPES = {
    0: "grass",
    1: "road",
    2: "house",
    3: "factory",
    4: "park"
}

# --- LOGIC: THE RANDOM WORLD GENERATOR ---
@app.route('/api/generate_random', methods=['GET'])
def generate_random_world():
    """
    Generates a 'Pre-Built' virtual city so the user can test immediately.
    It uses a weighted random algorithm to make it look realistic 
    (mostly grass, some roads, few factories).
    """
    grid = []
    
    for x in range(GRID_SIZE):
        row = []
        for y in range(GRID_SIZE):
            # Weighted Randomness: 
            # 60% Grass, 20% Roads, 10% Houses, 5% Factories, 5% Parks
            rand_val = random.randint(1, 100)
            
            if rand_val <= 60:
                tile_id = 0 # Grass
            elif rand_val <= 80:
                tile_id = 1 # Road
            elif rand_val <= 90:
                tile_id = 2 # House
            elif rand_val <= 95:
                tile_id = 3 # Factory
            else:
                tile_id = 4 # Park
                
            row.append(tile_id)
        grid.append(row)

    print("✅ Random World Generated for Client")
    return jsonify({
        "status": "success",
        "grid": grid,
        "message": "Virtual Sandbox Generated"
    })

# --- LOGIC: THE SCORING ENGINE ---
@app.route('/api/calculate_score', methods=['POST'])
def calculate_score():
    """
    Analyzes the grid and returns the Sustainability Score.
    """
    data = request.json
    grid = data.get('grid', [])
    
    pollution = 0
    happiness = 50
    budget = 100000
    
    # Analyze every single tile
    for row in grid:
        for tile_id in row:
            if tile_id == 2: # House
                pollution += 1
                happiness += 2
                budget += 500 # Tax income
            elif tile_id == 3: # Factory
                pollution += 15
                happiness -= 10
                budget += 2000 # Industry income
            elif tile_id == 4: # Park
                pollution -= 5 # Cleans air
                happiness += 10
                budget -= 200 # Maintenance cost

    # The "Reshape Formula" for Sustainability (0-100)
    score = 100 - pollution + (happiness * 0.5)
    
    # Ensure it stays between 0 and 100
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
    # Run on Port 5000
    print("🚀 Reshape_S Brain is Active on Port 5000...")
    app.run(host='0.0.0.0', port=5000, debug=True)