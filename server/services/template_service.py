"""Saved workouts (API.md, "GET /templates", "POST /templates", "PUT" and "DELETE").

No Flask here; api/templates.py has the endpoints. A *saved workout* is a Template in the
code and the API (specs/saved-workouts.llm.md). `top_muscles` and the response shape are
computed on request and never stored.

Stored template: {id, name, focus, exercises, last_done_at, created_at}. The two times are
timezone-aware datetimes; they become ISO strings only in the response.
"""
from __future__ import annotations

import math
import re
from datetime import datetime, timezone
from functools import lru_cache

import models
from services import exercise_service
from services.errors import ApiError
from services.timestamps import iso, parse

# Lowercase only: Datastore keys are case-sensitive, so a retry must match exactly (API.md, "IDs").
_UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")

MAX_NAME = 60
MAX_FOCUS = 60
MAX_EXERCISES = 30
MAX_GROUP = 60
SETS = (1, 20)
REPS = (1, 100)
REST = (0, 600)
TOP_COUNT = 3
TOP_LEVEL = 4


@lru_cache(maxsize=1)
def _muscles() -> dict:
    """The muscle tables, read once per process."""
    return exercise_service.load_muscles()


# --- Top muscles ----------------------------------------------------------------------------

def top_muscles(items: list[dict], exercises: dict[str, dict], muscles: dict) -> list[dict]:
    """The 3 parent muscles the template works most: [{muscle_id, name, level}].

    `items` are the template's exercises, `exercises` maps slug → library exercise, and
    `muscles` is the parsed server/muscles.json.
    """
    parents = muscles["parents"]
    order = {p["id"]: index for index, p in enumerate(parents)}
    parent_of = {p["id"]: p["id"] for p in parents}
    parent_of.update({head["id"]: head["parent"] for head in muscles["muscles"]})

    work: dict[str, float] = {}
    for row in items:
        exercise = exercises.get(row["exercise_id"])
        if exercise is None:
            continue
        for m in exercise.get("muscles", []):
            parent = parent_of.get(m["muscle_id"])
            if parent not in order:
                continue
            work[parent] = work.get(parent, 0) + row["target_sets"] * (m.get("weight") or 0)

    ranked = sorted((pid for pid, w in work.items() if w > 0), key=lambda pid: (-work[pid], order[pid]))
    top = ranked[:TOP_COUNT]
    if not top:
        return []
    most = work[top[0]]
    # round() keeps float noise (2.0000000001) from pushing a level up by one.
    return [{"muscle_id": pid, "name": parents[order[pid]]["name"],
             "level": math.ceil(round(TOP_LEVEL * work[pid] / most, 9))} for pid in top]


# --- Checking a POST/PUT body ---------------------------------------------------------------

def _bad(message: str) -> ApiError:
    return ApiError("bad_request", message)


def _is_int(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _int_in(value, low: int, high: int) -> bool:
    return _is_int(value) and low <= value <= high


def is_template_id(value) -> bool:
    return isinstance(value, str) and _UUID.match(value) is not None


def _clean_exercise(row, number: int, exercises: dict[str, dict]) -> dict:
    where = f"exercises[{number}]"
    if not isinstance(row, dict):
        raise _bad(f"{where} must be an object.")
    slug = row.get("exercise_id")
    if not isinstance(slug, str) or slug not in exercises:
        raise _bad(f"{where}.exercise_id {slug!r} isn't in the exercise library.")
    if not _int_in(row.get("target_sets"), *SETS):
        raise _bad(f"{where}.target_sets must be a whole number from {SETS[0]} to {SETS[1]}.")
    reps = row.get("target_reps")
    if reps is not None and not _int_in(reps, *REPS):
        raise _bad(f"{where}.target_reps must be a whole number from {REPS[0]} to {REPS[1]}, or null.")
    if not _int_in(row.get("rest_s"), *REST):
        raise _bad(f"{where}.rest_s must be a whole number from {REST[0]} to {REST[1]}.")
    group = row.get("superset_group")
    if group is not None and not isinstance(group, str):
        raise _bad(f"{where}.superset_group must be text or null.")
    if group is not None and len(group) > MAX_GROUP:
        raise _bad(f"{where}.superset_group must be at most {MAX_GROUP} characters.")
    return {"exercise_id": slug, "target_sets": row["target_sets"], "target_reps": reps,
            "rest_s": row["rest_s"], "superset_group": group}


def _clean_last_done(value, now: datetime) -> datetime | None:
    """The optional `last_done_at` of a POST: an ISO timestamp. A time later than `now` (a phone
    clock running ahead) becomes `now`, so it is never in the future (Sasa, Nov 4, 2026)."""
    if value is None:
        return None
    done = parse(value)
    if done is None:
        raise _bad("last_done_at must be an ISO 8601 timestamp or null.")
    return min(done, now)


def clean_input(body: dict, exercises: dict[str, dict], now: datetime | None = None) -> dict:
    """Checks a POST/PUT body against API.md's rules and returns the cleaned fields.

    Returns {id, name, focus, exercises, last_done_at}: name and focus trimmed, empty focus None,
    every exercise with all five fields, and `last_done_at` as a UTC datetime or None. Raises
    ApiError("bad_request") when a rule is broken. `now` is for tests; it defaults to the clock.
    """
    if not isinstance(body, dict):
        raise _bad("Send a JSON object.")
    if not is_template_id(body.get("id")):
        raise _bad("id must be a lowercase UUID.")

    name = body.get("name")
    name = name.strip() if isinstance(name, str) else ""
    if not 1 <= len(name) <= MAX_NAME:
        raise _bad(f"name must be 1 to {MAX_NAME} characters.")

    focus = body.get("focus")
    if focus is not None and not isinstance(focus, str):
        raise _bad("focus must be text or null.")
    focus = (focus or "").strip()
    if len(focus) > MAX_FOCUS:
        raise _bad(f"focus must be at most {MAX_FOCUS} characters.")

    rows = body.get("exercises")
    if not isinstance(rows, list) or not 1 <= len(rows) <= MAX_EXERCISES:
        raise _bad(f"exercises must have 1 to {MAX_EXERCISES} items.")

    last_done = _clean_last_done(body.get("last_done_at"), now or datetime.now(timezone.utc))
    return {"id": body["id"], "name": name, "focus": focus or None,
            "exercises": [_clean_exercise(row, n, exercises) for n, row in enumerate(rows)],
            "last_done_at": last_done}


def _body_slugs(body) -> list[str]:
    """The exercise IDs a body names, so the library is read once per request."""
    rows = body.get("exercises") if isinstance(body, dict) else None
    if not isinstance(rows, list):
        return []
    return [row["exercise_id"] for row in rows
            if isinstance(row, dict) and isinstance(row.get("exercise_id"), str)]


# --- Last done ------------------------------------------------------------------------------

def _aware(value: datetime) -> datetime:
    return value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)


def next_last_done(template: dict, done_at: datetime) -> dict | None:
    """The template with `last_done_at` moved forward to `done_at`, or None for no change."""
    old = template.get("last_done_at")
    if old is not None and _aware(old) >= _aware(done_at):
        return None
    return {**template, "last_done_at": done_at}


# --- Reads and writes -----------------------------------------------------------------------

def _public(template: dict, exercises: dict[str, dict]) -> dict:
    """A stored template in API.md's shape."""
    rows = [{"exercise_id": row["exercise_id"], "target_sets": row["target_sets"],
             "target_reps": row.get("target_reps"), "rest_s": row["rest_s"],
             "superset_group": row.get("superset_group")} for row in template.get("exercises", [])]
    return {
        "id": template["id"],
        "name": template["name"],
        "focus": template.get("focus"),
        "exercises": rows,
        "last_done_at": iso(template.get("last_done_at")),
        "top_muscles": top_muscles(rows, exercises, _muscles()),
    }


def _library_for(templates: list[dict]) -> dict[str, dict]:
    return models.get_exercises(row["exercise_id"] for t in templates for row in t.get("exercises", []))


def _created(template: dict) -> datetime:
    value = template.get("created_at")
    return _aware(value) if isinstance(value, datetime) else datetime.min.replace(tzinfo=timezone.utc)


def list_templates(user_id: str) -> list[dict]:
    """This user's saved workouts, oldest-created first, in API.md's shape."""
    templates = sorted(models.user_templates(user_id), key=_created)
    library = _library_for(templates)
    return [_public(t, library) for t in templates]


def create_template(user_id: str, body: dict) -> tuple[dict, bool]:
    """Creates a saved workout. Returns (template, created); a repeat id gives the stored one.

    `last_done_at` is the body's (a saved workout made from a finished workout counts as done,
    Sasa, Nov 4, 2026), else None.
    """
    library = models.get_exercises(_body_slugs(body))
    cleaned = clean_input(body, library)
    template = {**cleaned, "created_at": datetime.now(timezone.utc)}
    # One transaction, so two POSTs with the same id at the same moment write only once.
    stored, created = models.add_template(user_id, template)
    return _public(stored, library if created else _library_for([stored])), created


def update_template(user_id: str, template_id: str, body: dict) -> dict:
    """Replaces name, focus and exercises; keeps `last_done_at`. ApiError("not_found") if missing.

    The path id decides which template changes; an id or `last_done_at` in the body is ignored
    (API.md).
    """
    if not is_template_id(template_id):
        raise ApiError("not_found", "No saved workout with that id.")
    library = models.get_exercises(_body_slugs(body))
    # PUT ignores `last_done_at`, so it is dropped before checking: a bad value never gives 400.
    if isinstance(body, dict):
        body = {key: value for key, value in body.items() if key != "last_done_at"}
        body["id"] = template_id
    cleaned = clean_input(body, library)
    fields = {k: cleaned[k] for k in ("name", "focus", "exercises")}
    changed = models.change_template(user_id, template_id, lambda old: {**old, **fields})
    if changed is None:
        raise ApiError("not_found", "No saved workout with that id.")
    return _public(changed, library)


def delete_template(user_id: str, template_id: str) -> None:
    """Deletes a saved workout. A missing one is no error.

    An id that isn't a lowercase UUID can't be a saved workout, so the database isn't asked.
    """
    if not is_template_id(template_id):
        return
    models.delete_template(user_id, template_id)


def record_done(user_id: str, template_id: str, done_at: datetime) -> None:
    """Moves `last_done_at` forward to `done_at`. Safe to repeat; a missing template is no error.

    workout_service.save_workout calls this after models.save_workout (plan D13).
    """
    if not is_template_id(template_id):
        return
    models.change_template(user_id, template_id, lambda old: next_last_done(old, done_at))
