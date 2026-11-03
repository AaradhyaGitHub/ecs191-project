"""Creates the Flask app and registers one Blueprint per resource under /api/v1.

App Engine runs Gunicorn on `main:app` (app.yaml has no entrypoint).
Locally: `flask --app main run --port 5000` from server/.
"""
from flask import Flask

from api.errors import register_error_handlers
from api.health import bp as health_bp

API_PREFIX = "/api/v1"


def create_app() -> Flask:
    app = Flask(__name__)
    register_error_handlers(app)
    app.register_blueprint(health_bp, url_prefix=f"{API_PREFIX}/health")
    return app


app = create_app()
