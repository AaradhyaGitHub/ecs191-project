"""Goal endpoints (API.md, "GET /goals", "POST /goals", "PUT" and "DELETE").

All need sign-in (@require_user). Handlers only parse the request and return JSON;
services/goal_service.py has the logic.
"""
from __future__ import annotations

from datetime import date, datetime, timezone

from flask import Blueprint, jsonify, request

from api.auth import require_user
from services import goal_service
from services.errors import ApiError

bp = Blueprint("goals", __name__)


def _body() -> dict:
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        raise ApiError("bad_request", "Send a JSON object.")
    return data


def _today() -> date:
    """`?today=YYYY-MM-DD` (the phone's local date), else the server's UTC date."""
    text = request.args.get("today")
    if text is None:
        return datetime.now(timezone.utc).date()
    try:
        if len(text) == 10:
            return date.fromisoformat(text)
    except ValueError:
        pass
    raise ApiError("bad_request", "today must be a date written YYYY-MM-DD.")


@bp.get("")
@require_user
def list_goals(user_id):
    return jsonify({"goals": goal_service.list_goals(user_id, _today())})


@bp.post("")
@require_user
def create_goal(user_id):
    goal, created = goal_service.create_goal(user_id, _body(), _today())
    return jsonify(goal), 201 if created else 200


@bp.put("/<goal_id>")
@require_user
def update_goal(user_id, goal_id):
    return jsonify(goal_service.update_goal(user_id, goal_id, _body(), _today()))


@bp.delete("/<goal_id>")
@require_user
def delete_goal(user_id, goal_id):
    goal_service.delete_goal(user_id, goal_id)
    return "", 204
