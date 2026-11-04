"""Saved workouts (API.md, "GET /templates", "POST /templates", "PUT" and "DELETE").

No Flask here; api/templates.py has the endpoints. A *saved workout* is a Template in the
code and the API (specs/saved-workouts.llm.md). `top_muscles` and the response shape are
computed on request and never stored.

SCAFFOLD: every function returns a valid but wrong value. Build mode fills them in.
"""
from __future__ import annotations

from datetime import datetime


def top_muscles(items: list[dict], exercises: dict[str, dict], muscles: dict) -> list[dict]:
    """The 3 parent muscles the template works most: [{muscle_id, name, level}].

    `items` are the template's exercises, `exercises` maps slug → library exercise, and
    `muscles` is the parsed server/muscles.json.
    """
    return []


def clean_input(body: dict, exercises: dict[str, dict]) -> dict:
    """Checks a POST/PUT body against API.md's rules and returns the cleaned fields.

    Raises ApiError("bad_request") when a rule is broken.
    """
    return {}


def next_last_done(template: dict, done_at: datetime) -> dict | None:
    """The template with `last_done_at` moved forward to `done_at`, or None for no change."""
    return None


def list_templates(user_id: str) -> list[dict]:
    """This user's saved workouts, oldest-created first, in API.md's shape."""
    return []


def create_template(user_id: str, body: dict) -> tuple[dict, bool]:
    """Creates a saved workout. Returns (template, created); a repeat id gives the stored one."""
    return {}, False


def update_template(user_id: str, template_id: str, body: dict) -> dict:
    """Replaces name, focus and exercises; keeps `last_done_at`. ApiError("not_found") if missing."""
    return {}


def delete_template(user_id: str, template_id: str) -> None:
    """Deletes a saved workout. A missing one is no error."""
    return None


def record_done(user_id: str, template_id: str, done_at: datetime) -> None:
    """Moves `last_done_at` forward to `done_at`. Safe to repeat; a missing template is no error.

    workout_service.save_workout calls this after models.save_workout (plan D13).
    """
    return None
