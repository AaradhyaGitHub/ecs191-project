"""Exercise search and this user's exercises (API.md, "GET /exercises" and "GET /exercises/mine").

No Flask here; api/exercises.py has the endpoints. `muscles` is the parsed server/muscles.json,
the server's copy of shared/muscles.json (a test checks the two are the same).

Search rules (specs/exercise-search.llm.md): a word starts at the beginning of a name or alias,
or after a space or a hyphen. An exercise matches when the typed text starts at a word start.
Order: name starts with the text, then a later word of the name, then alias only; ties A–Z.
"""
from __future__ import annotations

import json
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path

import models
from services.errors import ApiError

MUSCLES_PATH = Path(__file__).resolve().parents[1] / "muscles.json"

# The fields API.md lists for an exercise. Stored fields such as `source` stay on the server.
_PUBLIC_FIELDS = ("id", "name", "aliases", "load_type", "bodyweight_fraction", "muscles")

_WORD_BREAKS = (" ", "-")

# Order tiers for a match.
_NAME_START, _NAME_WORD, _ALIAS_ONLY = 0, 1, 2


def load_muscles() -> dict:
    """Reads server/muscles.json only (never shared/, which isn't deployed)."""
    return json.loads(MUSCLES_PATH.read_text())


@lru_cache(maxsize=1)
def _muscles() -> dict:
    """The muscle tables, read once per process."""
    return load_muscles()


def _parent_of(muscle_id: str, muscles: dict) -> dict | None:
    """The parent entry for a head ID (`triceps_long`) or a parent ID (`triceps`)."""
    parents = {p["id"]: p for p in muscles["parents"]}
    if muscle_id in parents:
        return parents[muscle_id]
    for head in muscles["muscles"]:
        if head["id"] == muscle_id:
            return parents.get(head["parent"])
    return None


def _primary_parents(exercise: dict, muscles: dict) -> list[dict]:
    """Parents of the primary muscles, strongest first (list order breaks ties), no repeats."""
    primaries = [m for m in exercise.get("muscles", []) if m.get("role") == "primary"]
    primaries.sort(key=lambda m: -(m.get("weight") or 0))  # sort is stable
    result: list[dict] = []
    for m in primaries:
        parent = _parent_of(m["muscle_id"], muscles)
        if parent is not None and parent not in result:
            result.append(parent)
    return result


def _unique(values: list[str]) -> list[str]:
    return list(dict.fromkeys(values))


def groups_of(exercise: dict, muscles: dict) -> list[str]:
    """Group IDs of the exercise's primary muscles, strongest first, no repeats."""
    return _unique([p["group"] for p in _primary_parents(exercise, muscles)])


def primary_muscles_of(exercise: dict, muscles: dict) -> list[str]:
    """Display names of the parents of the exercise's primary muscles, strongest first, no repeats."""
    return _unique([p["name"] for p in _primary_parents(exercise, muscles)])


def _word_starts(text: str) -> list[int]:
    return [0] + [i for i in range(1, len(text)) if text[i - 1] in _WORD_BREAKS]


def _starts_a_word(text: str, q: str) -> bool:
    return any(text.startswith(q, i) for i in _word_starts(text))


def _tier(exercise: dict, q: str) -> int | None:
    """The order tier of a match, or None when the exercise doesn't match `q` (lowercase)."""
    name = exercise["name"].lower()
    if name.startswith(q):
        return _NAME_START
    if _starts_a_word(name, q):
        return _NAME_WORD
    if any(_starts_a_word(alias.lower(), q) for alias in exercise.get("aliases") or []):
        return _ALIAS_ONLY
    return None


def _public(exercise: dict, muscles: dict) -> dict:
    item = {key: exercise.get(key) for key in _PUBLIC_FIELDS}
    item["aliases"] = list(item["aliases"] or [])
    item["muscles"] = [{"muscle_id": m["muscle_id"], "role": m["role"], "weight": m["weight"]}
                       for m in exercise.get("muscles", [])]
    item["groups"] = groups_of(exercise, muscles)
    item["primary_muscles"] = primary_muscles_of(exercise, muscles)
    return item


def search(exercises: list[dict], q: str | None, group: str | None, muscles: dict) -> list[dict]:
    """Matches, filters and orders `exercises`, and adds `groups` and `primary_muscles` to each."""
    text = (q or "").strip().lower()
    ranked = []
    for exercise in exercises:
        tier = _tier(exercise, text) if text else _NAME_START
        if tier is None:
            continue
        item = _public(exercise, muscles)
        if group and group not in item["groups"]:
            continue
        ranked.append((tier, item["name"].lower(), item))
    ranked.sort(key=lambda r: (r[0], r[1]))
    return [item for _, _, item in ranked]


def find_exercises(q: str | None, group: str | None) -> list[dict]:
    """Searches the whole library. An unknown `group` raises ApiError("bad_request")."""
    muscles = _muscles()
    group_ids = [g["id"] for g in muscles["groups"]]
    if group is not None and group not in group_ids:
        raise ApiError("bad_request", f"Unknown group {group!r}. Use one of: {', '.join(group_ids)}.")
    return search(models.all_exercises(), q, group, muscles)


def _iso(value) -> str | None:
    """A UTC timestamp as API.md writes it: 2026-11-01T18:10:00Z."""
    if not isinstance(value, datetime):
        return value
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def my_exercises(user_id: str) -> list[dict]:
    """This user's history, one item per UserExercise, in API.md's shape."""
    return [{
        "exercise_id": row["exercise_id"],
        "use_count": row.get("use_count", 0),
        "last_used_at": _iso(row.get("last_used_at")),
        "last_set": row.get("last_set"),
        "best_e1rm_kg": row.get("best_e1rm_kg"),
        "best_e1rm_at": _iso(row.get("best_e1rm_at")),
    } for row in models.user_exercises(user_id)]
