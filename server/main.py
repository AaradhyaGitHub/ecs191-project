"""Creates the Flask app and registers one Blueprint per resource under /api/v1.

App Engine runs Gunicorn on `main:app` (app.yaml has no entrypoint).
Locally: `flask --app main run --port 5000` from server/.
"""
from flask import Flask

from api.auth import bp as auth_bp
from api.errors import register_error_handlers
from api.exercises import bp as exercises_bp
from api.health import bp as health_bp
from api.templates import bp as templates_bp
from api.users import bp as users_bp
from api.workouts import bp as workouts_bp

API_PREFIX = "/api/v1"


def create_app() -> Flask:
    app = Flask(__name__)
    register_error_handlers(app)
    app.register_blueprint(health_bp, url_prefix=f"{API_PREFIX}/health")
    app.register_blueprint(auth_bp, url_prefix=f"{API_PREFIX}/auth")
    app.register_blueprint(exercises_bp, url_prefix=f"{API_PREFIX}/exercises")
    app.register_blueprint(templates_bp, url_prefix=f"{API_PREFIX}/templates")
    app.register_blueprint(users_bp, url_prefix=f"{API_PREFIX}/users")
    app.register_blueprint(workouts_bp, url_prefix=f"{API_PREFIX}/workouts")
    return app


app = create_app()
