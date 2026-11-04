"""Profile endpoints (API.md, "GET /users/me" and "PUT /users/me"). Both need sign-in.

SCAFFOLD: both endpoints answer 501. Build mode adds @require_user and calls
services/user_service.py.
"""
from __future__ import annotations

from flask import Blueprint, jsonify

bp = Blueprint("users", __name__)


def _not_built():
    return jsonify({"error": {"code": "internal", "message": "Not built yet."}}), 501


@bp.get("/me")
def get_me():
    return _not_built()


@bp.put("/me")
def update_me():
    return _not_built()
