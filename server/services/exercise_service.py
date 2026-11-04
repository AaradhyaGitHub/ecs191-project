"""Exercise search and this user's exercises (API.md, "GET /exercises" and "GET /exercises/mine").

No Flask here; api/exercises.py has the endpoints. `muscles` is the parsed server/muscles.json,
the server's copy of shared/muscles.json (a test checks the two are the same).

SCAFFOLD: every function returns a valid but wrong value. Build mode fills them in.
"""
from __future__ import annotations

from pathlib import Path

MUSCLES_PATH = Path(__file__).resolve().parents[1] / "muscles.json"


def load_muscles() -> dict:
    """Reads server/muscles.json only (never shared/, which isn't deployed)."""
    return {"groups": [], "parents": [], "muscles": []}


def groups_of(exercise: dict, muscles: dict) -> list[str]:
    """Group IDs of the exercise's primary muscles, strongest first, no repeats."""
    return []


def primary_muscles_of(exercise: dict, muscles: dict) -> list[str]:
    """Display names of the parents of the exercise's primary muscles, strongest first, no repeats."""
    return []


def search(exercises: list[dict], q: str | None, group: str | None, muscles: dict) -> list[dict]:
    """Matches, filters and orders `exercises`, and adds `groups` and `primary_muscles` to each."""
    return []


def find_exercises(q: str | None, group: str | None) -> list[dict]:
    """Searches the whole library. An unknown `group` raises ApiError("bad_request")."""
    return []


def my_exercises(user_id: str) -> list[dict]:
    """This user's history, one item per UserExercise, in API.md's shape."""
    return []
