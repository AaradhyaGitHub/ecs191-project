"""Exercise endpoints (API.md, "GET /exercises" and "GET /exercises/mine").

`GET ""` is public. `GET "/mine"` needs sign-in (@require_user).
"""
from __future__ import annotations

from flask import Blueprint, jsonify, request

from api.auth import require_user
from services import exercise_service

bp = Blueprint("exercises", __name__)


@bp.get("")
def search_exercises():
    q = request.args.get("q")
    # The raw value: an empty `group=` fails the group check like an unknown group (#44).
    group = request.args.get("group")
    return jsonify({"exercises": exercise_service.find_exercises(q, group)})


@bp.get("/mine")
@require_user
def my_exercises(user_id):
    return jsonify({"exercises": exercise_service.my_exercises(user_id)})
