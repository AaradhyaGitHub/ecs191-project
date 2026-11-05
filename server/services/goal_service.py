"""Goals (API.md, "Endpoints for the Goals tab"; plan specs/goals.llm.md).

No Flask here; api/goals.py has the endpoints. The server stores what a goal is
({id, type, exercise_id, target, start_date, deadline, created_at}); `status`,
`exercise_name` and `progress` are worked out on every request and never stored.

SCAFFOLD: every function returns a valid but wrong value until the build step.
"""
from __future__ import annotations

from datetime import date

import models  # noqa: F401  (used by the build step)
from services.errors import ApiError  # noqa: F401  (used by the build step)

MAX_ACTIVE = 3
MAX_STRENGTH_TARGET_KG = 1500
FREQUENCY_TARGET = (1, 7)
MAX_DEADLINE_YEARS = 5


def _empty_progress() -> dict:
    return {"current": None, "percent": None, "remaining": None, "achieved_on": None,
            "met_this_week": None, "week_start": None}


def epley(weight_kg: float, reps: int) -> float:
    """Estimated one-rep max: weight_kg × (1 + reps / 30)."""
    return 0.0


def strength_progress(goal: dict, sets: list[dict]) -> dict:
    """Progress of a strength goal from stored SetEntry dicts (each with its workout's
    `local_date`): {current, percent, remaining, achieved_on, met_this_week, week_start}."""
    return _empty_progress()


def frequency_progress(goal: dict, workouts: list[dict], today: date) -> dict:
    """Progress of a frequency goal over the Monday–Sunday week containing `today`.
    `workouts` are dicts with at least `local_date` (YYYY-MM-DD)."""
    return _empty_progress()


def list_goals(user_id: str, today: date) -> list[dict]:
    """This user's goals with status and progress, in API.md's order."""
    return []


def create_goal(user_id: str, body: dict, today: date) -> tuple[dict, bool]:
    """Validates and creates a goal. Returns (goal, created); a repeated id returns the
    stored goal with created False."""
    return {}, False


def update_goal(user_id: str, goal_id: str, body: dict, today: date) -> dict:
    """Changes `target` and, for strength, `deadline`; returns the full goal."""
    return {}


def delete_goal(user_id: str, goal_id: str) -> None:
    """Deletes one of this user's goals. A missing one is no error."""
    return None
