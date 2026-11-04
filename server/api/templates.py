"""Saved-workout endpoints (API.md, "GET /templates", "POST /templates", "PUT" and "DELETE").

All need sign-in (@require_user). Handlers only parse the request and return JSON;
services/template_service.py has the logic.
"""
from __future__ import annotations

from flask import Blueprint, jsonify, request

from api.auth import require_user
from services import template_service
from services.errors import ApiError

bp = Blueprint("templates", __name__)


def _body() -> dict:
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        raise ApiError("bad_request", "Send a JSON object.")
    return data


@bp.get("")
@require_user
def list_templates(user_id):
    return jsonify({"templates": template_service.list_templates(user_id)})


@bp.post("")
@require_user
def create_template(user_id):
    template, created = template_service.create_template(user_id, _body())
    return jsonify(template), 201 if created else 200


@bp.put("/<template_id>")
@require_user
def update_template(user_id, template_id):
    return jsonify(template_service.update_template(user_id, template_id, _body()))


@bp.delete("/<template_id>")
@require_user
def delete_template(user_id, template_id):
    template_service.delete_template(user_id, template_id)
    return "", 204
