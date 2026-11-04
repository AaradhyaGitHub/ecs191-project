"""Workout endpoints (API.md, "POST /workouts", "GET /workouts", "GET /workouts/{id}").
All need sign-in.
"""
from __future__ import annotations

from flask import Blueprint, jsonify, request

from api.auth import require_user
from services import workout_service
from services.errors import ApiError

bp = Blueprint("workouts", __name__)


@bp.post("")
@require_user
def save_workout(user_id):
    body = request.get_json(silent=True)
    if not isinstance(body, dict):
        raise ApiError("bad_request", "Send the workout as a JSON object.")
    detail, created = workout_service.save_workout(user_id, body)
    return jsonify(detail), 201 if created else 200


@bp.get("")
@require_user
def list_workouts(user_id):
    text = request.args.get("limit")
    limit = workout_service.DEFAULT_LIMIT
    if text is not None:
        try:
            limit = int(text)
        except ValueError:
            raise ApiError("bad_request", "limit must be a whole number from 1 to 100.") from None
    return jsonify({"workouts": workout_service.list_workouts(user_id, limit)})


@bp.get("/<workout_id>")
@require_user
def get_workout(user_id, workout_id):
    return jsonify(workout_service.get_workout(user_id, workout_id))
