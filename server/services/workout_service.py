"""Saving and reading finished workouts (API.md, "POST /workouts", "GET /workouts",
"GET /workouts/{id}"). No Flask here; api/workouts.py has the endpoints.

Plan: specs/log-workout.llm.md. The workout, its sets and each exercise's UserExercise are
saved in one transaction by models.save_workout. Daily stats and totals come later (D-1).
"""
from __future__ import annotations

import re
from datetime import date

import models
from services.errors import ApiError
from services.timestamps import iso, parse

# Limits from API.md.
MAX_SETS = 300
DEFAULT_LIMIT = 20
MAX_LIMIT = 100

SET_TYPES = ("warmup", "working", "dropset", "failure")
TIME_SOURCES = ("rest_timer", "manual", "camera", "none")
INPUTS = ("manual", "text", "voice", "photo", "camera", "import")

# Every workout always stores "finished" for now (llm.md, Decisions).
FINISHED = "finished"

# The order of the fields in a response (API.md, "GET /workouts/{id}").
WORKOUT_FIELDS = ("id", "name", "template_id", "status", "started_at", "ended_at", "timezone",
                  "local_date", "bodyweight_kg")
SET_FIELDS = ("id", "exercise_id", "order", "superset_group", "set_type", "reps", "duration_s",
              "weight_kg", "added_load_kg", "effort_pct", "started_at", "ended_at",
              "rest_before_s", "time_source", "input")
SUMMARY_FIELDS = ("id", "name", "template_id", "started_at", "ended_at", "local_date")
# The fields of UserExercise.last_set (API.md, "GET /exercises/mine").
LAST_SET_FIELDS = ("weight_kg", "added_load_kg", "reps", "duration_s", "effort_pct")
# Set types that make a good pre-fill for next time (D-4).
_LAST_SET_TYPES = ("working", "failure")

_UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
_LOCAL_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


# --- Small checks --------------------------------------------------------------------------

def _bad(message: str) -> ApiError:
    return ApiError("bad_request", message)


def is_client_id(value) -> bool:
    """A lowercase UUID, as the phone makes them (API.md, "Conventions")."""
    return isinstance(value, str) and bool(_UUID.match(value))


def _is_number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _is_int(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _optional(data: dict, key: str, check, what: str, where: str):
    """The value of an optional field: None when missing or null, else it must pass `check`."""
    value = data.get(key)
    if value is not None and not check(value):
        raise _bad(f"{where}{key} must be {what}.")
    return value


def _required_text(body: dict, key: str) -> str:
    value = body.get(key)
    if not isinstance(value, str) or not value.strip():
        raise _bad(f"{key} is required.")
    return value


def _required_time(body: dict, key: str):
    if body.get(key) is None:
        raise _bad(f"{key} is required.")
    value = parse(body[key])
    if value is None:
        raise _bad(f"{key} must be an ISO 8601 timestamp.")
    return value


def _optional_time(data: dict, key: str, where: str):
    if data.get(key) is None:
        return None
    value = parse(data[key])
    if value is None:
        raise _bad(f"{where}{key} must be an ISO 8601 timestamp.")
    return value


def _local_date(body: dict) -> str:
    value = _required_text(body, "local_date")
    try:
        if not _LOCAL_DATE.match(value):
            raise ValueError
        date.fromisoformat(value)
    except ValueError:
        raise _bad("local_date must be a date written YYYY-MM-DD.") from None
    return value


def _choice(data: dict, key: str, allowed: tuple, where: str, required: bool = False):
    value = data.get(key)
    if value is None and not required:
        return None
    if value not in allowed:
        raise _bad(f"{where}{key} must be one of: {', '.join(allowed)}.")
    return value


# --- Validation (AC-4) ---------------------------------------------------------------------

def _clean_set(raw, index: int, known_exercise_ids: set[str]) -> dict:
    where = f"Set {index}: "
    if not isinstance(raw, dict):
        raise _bad(f"Set {index} must be a JSON object.")
    if not is_client_id(raw.get("id")):
        raise _bad(f"{where}id must be a lowercase UUID.")
    exercise_id = raw.get("exercise_id")
    if not isinstance(exercise_id, str) or exercise_id not in known_exercise_ids:
        raise _bad(f"{where}unknown exercise_id {exercise_id!r}.")
    if not _is_int(raw.get("order")):
        raise _bad(f"{where}order must be a whole number.")

    clean = {
        "id": raw["id"],
        "exercise_id": exercise_id,
        "order": raw["order"],
        "superset_group": _optional(raw, "superset_group", lambda v: isinstance(v, str), "text", where),
        "set_type": _choice(raw, "set_type", SET_TYPES, where, required=True),
        "reps": _optional(raw, "reps", _is_int, "a whole number", where),
        "duration_s": _optional(raw, "duration_s", _is_int, "a whole number", where),
        "weight_kg": _optional(raw, "weight_kg", lambda v: _is_number(v) and v >= 0,
                               "a number of 0 or more", where),
        "added_load_kg": _optional(raw, "added_load_kg", _is_number, "a number", where),
        "effort_pct": _optional(raw, "effort_pct", lambda v: _is_number(v) and 0 <= v <= 100,
                                "a number from 0 to 100", where),
        "started_at": _optional_time(raw, "started_at", where),
        "ended_at": _optional_time(raw, "ended_at", where),
        "rest_before_s": _optional(raw, "rest_before_s", _is_int, "a whole number", where),
        "time_source": _choice(raw, "time_source", TIME_SOURCES, where),
        "input": _choice(raw, "input", INPUTS, where),
    }
    if clean["reps"] is None and clean["duration_s"] is None:
        raise _bad(f"{where}send reps or duration_s.")
    return clean


def validate_workout(body: dict, known_exercise_ids: set[str]) -> dict:
    """Checks a POST /workouts body against API.md's rules (AC-4).

    Returns the clean workout: {"workout": {...}, "sets": [...]}, with every field present
    (None when not sent) and timestamps parsed. Raises ApiError("bad_request") on any broken rule.
    """
    if not isinstance(body, dict):
        raise _bad("Send the workout as a JSON object.")
    if not is_client_id(body.get("id")):
        raise _bad("id must be a lowercase UUID.")
    workout = {
        "id": body["id"],
        "name": _required_text(body, "name"),
        "template_id": _optional(body, "template_id", lambda v: isinstance(v, str), "text", ""),
        "status": FINISHED,
        "started_at": _required_time(body, "started_at"),
        "ended_at": _required_time(body, "ended_at"),
        "timezone": _required_text(body, "timezone"),
        "local_date": _local_date(body),
        "bodyweight_kg": _optional(body, "bodyweight_kg", _is_number, "a number", ""),
    }
    if workout["ended_at"] < workout["started_at"]:
        raise _bad("ended_at is before started_at.")

    raw_sets = body.get("sets")
    if not isinstance(raw_sets, list) or not raw_sets:
        raise _bad("A workout needs at least one set.")
    if len(raw_sets) > MAX_SETS:
        raise _bad(f"A workout can have at most {MAX_SETS} sets.")
    sets = [_clean_set(raw, index, known_exercise_ids) for index, raw in enumerate(raw_sets, start=1)]
    if len({s["id"] for s in sets}) != len(sets):
        raise _bad("Two sets have the same id.")
    if len({s["order"] for s in sets}) != len(sets):
        raise _bad("Two sets have the same order.")

    workout["set_count"] = len(sets)
    workout["exercise_count"] = len({s["exercise_id"] for s in sets})
    return {"workout": workout, "sets": sets}


# --- History for one exercise (AC-5, AC-6) -------------------------------------------------

def _last_set(sets: list[dict]) -> dict | None:
    """The highest-order working or failure set, else the highest-order set (D-4)."""
    good = [s for s in sets if s.get("set_type") in _LAST_SET_TYPES]
    pool = good or list(sets)
    if not pool:
        return None
    chosen = max(pool, key=lambda s: s["order"])
    return {key: chosen.get(key) for key in LAST_SET_FIELDS}


def merge_user_exercise(old: dict | None, workout: dict, sets: list[dict]) -> dict:
    """The new UserExercise for one exercise after `workout` (AC-5, AC-6). Pure.

    `old` is the stored UserExercise or None; `sets` are this workout's sets of that exercise.
    A workout that ended at or before the stored `last_used_at` only adds to `use_count`.
    """
    old = old or {}
    merged = {
        "use_count": (old.get("use_count") or 0) + 1,
        "last_used_at": old.get("last_used_at"),
        "last_set": dict(old["last_set"]) if old.get("last_set") is not None else None,
        "best_e1rm_kg": old.get("best_e1rm_kg"),
        "best_e1rm_at": old.get("best_e1rm_at"),
    }
    ended_at = workout["ended_at"]
    if merged["last_used_at"] is None or ended_at > merged["last_used_at"]:
        merged["last_used_at"] = ended_at
        merged["last_set"] = _last_set(sets)
    return merged


# --- Response shapes -----------------------------------------------------------------------

def _set_detail(stored: dict) -> dict:
    item = {key: stored.get(key) for key in SET_FIELDS}
    item["started_at"] = iso(item["started_at"])
    item["ended_at"] = iso(item["ended_at"])
    return item


def to_detail(workout: dict, sets: list[dict]) -> dict:
    """A stored workout and its sets in the GET /workouts/{id} shape."""
    detail = {key: workout.get(key) for key in WORKOUT_FIELDS}
    detail["status"] = detail["status"] or FINISHED
    detail["started_at"] = iso(detail["started_at"])
    detail["ended_at"] = iso(detail["ended_at"])
    detail["sets"] = [_set_detail(s) for s in sorted(sets, key=lambda s: s["order"])]
    return detail


def to_summary(workout: dict, sets: list[dict]) -> dict:
    """A stored workout in the GET /workouts list shape (no sets).

    The counts are stored on the Workout at save (D-7); `sets` is only used when they aren't.
    """
    summary = {key: workout.get(key) for key in SUMMARY_FIELDS}
    summary["started_at"] = iso(summary["started_at"])
    summary["ended_at"] = iso(summary["ended_at"])
    set_count = workout.get("set_count")
    exercise_count = workout.get("exercise_count")
    summary["set_count"] = set_count if set_count is not None else len(sets)
    summary["exercise_count"] = (exercise_count if exercise_count is not None
                                 else len({s["exercise_id"] for s in sets}))
    return summary


# --- Use cases -----------------------------------------------------------------------------

def _known_exercise_ids(body) -> set[str]:
    """The slugs in the body's sets that are in the library."""
    raw_sets = body.get("sets") if isinstance(body, dict) else None
    if not isinstance(raw_sets, list):
        return set()
    slugs = {s.get("exercise_id") for s in raw_sets
             if isinstance(s, dict) and isinstance(s.get("exercise_id"), str)}
    return set(models.get_exercises(slugs)) if slugs else set()


def save_workout(user_id: str, body: dict) -> tuple[dict, bool]:
    """Validates and saves a workout. Returns (detail, created); created is False for a repeat.

    A repeat with the same id returns the stored workout, even when the new body differs.
    """
    if isinstance(body, dict) and is_client_id(body.get("id")):
        stored = models.get_workout(user_id, body["id"])
        if stored is not None:
            return to_detail(*stored), False
    clean = validate_workout(body, _known_exercise_ids(body))
    workout, sets, created = models.save_workout(user_id, clean["workout"], clean["sets"],
                                                 merge_user_exercise)
    return to_detail(workout, sets), created


def get_workout(user_id: str, workout_id: str) -> dict:
    """One workout in the detail shape. Raises ApiError("not_found") for an unknown id."""
    stored = models.get_workout(user_id, workout_id) if is_client_id(workout_id) else None
    if stored is None:
        raise ApiError("not_found", "No workout with that id.")
    return to_detail(*stored)


def list_workouts(user_id: str, limit: int = DEFAULT_LIMIT) -> list[dict]:
    """This user's workouts, newest started_at first, at most `limit` (1–100)."""
    if not _is_int(limit) or not 1 <= limit <= MAX_LIMIT:
        raise _bad(f"limit must be a whole number from 1 to {MAX_LIMIT}.")
    return [to_summary(w, []) for w in models.list_workouts(user_id, limit)]
