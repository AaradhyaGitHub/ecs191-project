"""Profile endpoints (API.md, "GET /users/me" and "PUT /users/me"). Both need sign-in."""
from __future__ import annotations

from flask import Blueprint, jsonify, request

from api.auth import require_user
from services import user_service
from services.errors import ApiError

bp = Blueprint("users", __name__)


@bp.get("/me")
@require_user
def get_me(user_id):
    return jsonify(user_service.get_me(user_id))


@bp.put("/me")
@require_user
def update_me(user_id):
    body = request.get_json(silent=True)
    if not isinstance(body, dict):
        raise ApiError("bad_request", "Send the changes as a JSON object.")
    return jsonify(user_service.update_me(user_id, body))
