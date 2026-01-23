from flask import Blueprint, jsonify, request

v2 = Blueprint('v2', __name__)

@v2.route('/status', methods=['GET'])
def status():
    return jsonify({
        "status": "Plan B Engine Online", 
        "version": "2.0",
        "mode": "Real World Simulation"
    })

# To_do- add the Chunk Loader here shortly