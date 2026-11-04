"""Exercise endpoints (API.md, "GET /exercises" and "GET /exercises/mine").

`GET ""` is public. `GET "/mine"` needs sign-in (@require_user).

SCAFFOLD: both handlers answer 200 with an empty list, and "/mine" doesn't check sign-in
yet. Build mode adds the service calls and @require_user.
"""
from __future__ import annotations

from flask import Blueprint, jsonify

bp = Blueprint("exercises", __name__)


@bp.get("")
def search_exercises():
    return jsonify({"exercises": []})


@bp.get("/mine")
def my_exercises():
    return jsonify({"exercises": []})
