"""Saved-workout endpoints (API.md, "GET /templates", "POST /templates", "PUT" and "DELETE").

All need sign-in. Handlers only parse the request and return JSON; services/template_service.py
has the logic.

SCAFFOLD: every endpoint answers 501 until build mode. @require_user is added in build mode,
so the "unauthorized" tests stay red until then.
"""
from __future__ import annotations

from flask import Blueprint, jsonify

bp = Blueprint("templates", __name__)


def _not_built():
    return jsonify({"error": {"code": "internal", "message": "Not built yet."}}), 501


@bp.get("")
def list_templates():
    return _not_built()


@bp.post("")
def create_template():
    return _not_built()


@bp.put("/<template_id>")
def update_template(template_id):
    return _not_built()


@bp.delete("/<template_id>")
def delete_template(template_id):
    return _not_built()
