from flask import Flask
from flask_cors import CORS

# Import the two versions
from api.v1.routes import v1
from api.v2.routes import v2

app = Flask(__name__)
# Enable CORS for everyone so both Mobile and Web can connect
CORS(app)

# Register the Blueprints (This creates the separation)
# Old App talks to: /api/v1/...
app.register_blueprint(v1, url_prefix='/api/v1')

# New App talks to: /api/v2/...
app.register_blueprint(v2, url_prefix='/api/v2')

@app.route('/')
def home():
    return "Reshape_S Server Online. Active Versions: [v1, v2]"

if __name__ == '__main__':
    # Run on 0.0.0.0 so external devices can connect
    app.run(host='0.0.0.0', port=5000)