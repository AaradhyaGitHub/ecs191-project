"""Workout endpoints (API.md, "POST /workouts", "GET /workouts", "GET /workouts/{id}").
All need sign-in.

SCAFFOLD: every endpoint answers 501. Build mode adds @require_user and calls
services/workout_service.py.
"""
from __future__ import annotations

from flask import Blueprint, jsonify

bp = Blueprint("workouts", __name__)


def _not_built():
    return jsonify({"error": {"code": "internal", "message": "Not built yet."}}), 501


@bp.post("")
def save_workout():
    return _not_built()


@bp.get("")
def list_workouts():
    return _not_built()


@bp.get("/<workout_id>")
def get_workout(workout_id):
    return _not_built()
