"""Saving and reading finished workouts (API.md, "POST /workouts", "GET /workouts",
"GET /workouts/{id}"). No Flask here; api/workouts.py has the endpoints.

Plan: specs/log-workout.llm.md. The workout, its sets and each exercise's UserExercise are
saved in one transaction by models.save_workout. Daily stats and totals come later (D-1).

SCAFFOLD: every function returns a valid but wrong value. Build mode fills them in.
"""
from __future__ import annotations

import models  # noqa: F401  (used in build mode)
from services.errors import ApiError  # noqa: F401  (used in build mode)

# Limits from API.md.
MAX_SETS = 300
DEFAULT_LIMIT = 20
MAX_LIMIT = 100

SET_TYPES = ("warmup", "working", "dropset", "failure")
TIME_SOURCES = ("rest_timer", "manual", "camera", "none")
INPUTS = ("manual", "text", "voice", "photo", "camera", "import")


def validate_workout(body: dict, known_exercise_ids: set[str]) -> dict:
    """Checks a POST /workouts body against API.md's rules (AC-4).

    Returns the clean workout: {"workout": {...}, "sets": [...]}, with every field present
    (None when not sent) and timestamps parsed. Raises ApiError("bad_request") on any broken rule.
    """
    return {}


def merge_user_exercise(old: dict | None, workout: dict, sets: list[dict]) -> dict:
    """The new UserExercise for one exercise after `workout` (AC-5, AC-6). Pure.

    `old` is the stored UserExercise or None; `sets` are this workout's sets of that exercise.
    """
    return {}


def to_detail(workout: dict, sets: list[dict]) -> dict:
    """A stored workout and its sets in the GET /workouts/{id} shape."""
    return {}


def to_summary(workout: dict, sets: list[dict]) -> dict:
    """A stored workout in the GET /workouts list shape (no sets)."""
    return {}


def save_workout(user_id: str, body: dict) -> tuple[dict, bool]:
    """Validates and saves a workout. Returns (detail, created); created is False for a repeat."""
    return {}, False


def get_workout(user_id: str, workout_id: str) -> dict:
    """One workout in the detail shape. Raises ApiError("not_found") for an unknown id."""
    return {}


def list_workouts(user_id: str, limit: int = DEFAULT_LIMIT) -> list[dict]:
    """This user's workouts, newest started_at first, at most `limit` (1–100)."""
    return []
