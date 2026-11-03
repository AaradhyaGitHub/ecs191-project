"""GET /api/v1/health: lets the app and deploy checks see the server is up. No auth."""
from flask import Blueprint, jsonify

bp = Blueprint("health", __name__)


@bp.get("")
def health():
    return jsonify({"status": "ok"})
