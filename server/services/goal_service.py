"""Goals (API.md, "Endpoints for the Goals tab"; plan specs/goals.llm.md).

No Flask here; api/goals.py has the endpoints. The server stores what a goal is
({id, type, exercise_id, target, start_date, deadline, created_at}); `status`,
`exercise_name` and `progress` are worked out on every request and never stored.
"""
from __future__ import annotations

import math
import re
from datetime import date, datetime, timedelta, timezone

import models
from services.errors import ApiError
from services.timestamps import iso

MAX_ACTIVE = 3
MAX_STRENGTH_TARGET_KG = 1500
FREQUENCY_TARGET = (1, 7)
MAX_DEADLINE_YEARS = 5

# Sets that count toward a strength goal (Decided 1 and AC-5).
ELIGIBLE_SET_TYPES = ("working", "failure")
ELIGIBLE_REPS = (1, 10)
UNSUPPORTED_LOAD_TYPES = ("bodyweight", "timed")

# Lowercase only: Datastore keys are case-sensitive, so a retry must match exactly (API.md, "IDs").
_UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
# Float noise must not decide whether a target was reached (60 kg × 5 is exactly 70.0).
_EPSILON = 1e-9


def _empty_progress() -> dict:
    return {"current": None, "percent": None, "remaining": None, "achieved_on": None,
            "met_this_week": None, "week_start": None}


# --- Progress ----------------------------------------------------------------------------------

def epley(weight_kg: float, reps: int) -> float:
    """Estimated one-rep max: weight_kg × (1 + reps / 30)."""
    # Written as one division so whole-number cases (60 × 35 / 30 = 70) come out exact.
    return weight_kg * (30 + reps) / 30


def _number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def _eligible(s: dict, exercise_id: str) -> bool:
    weight, reps = s.get("weight_kg"), s.get("reps")
    return (s.get("exercise_id") == exercise_id
            and s.get("set_type") in ELIGIBLE_SET_TYPES
            and _number(weight) and weight > 0
            and _number(reps) and ELIGIBLE_REPS[0] <= reps <= ELIGIBLE_REPS[1])


def _reached(current: float, target: float) -> bool:
    return current >= target - _EPSILON


def strength_progress(goal: dict, sets: list[dict]) -> dict:
    """Progress of a strength goal from stored SetEntry dicts (each with its workout's
    `local_date`): {current, percent, remaining, achieved_on, met_this_week, week_start}."""
    progress = _empty_progress()
    target = goal["target"]
    eligible = [s for s in sets if _eligible(s, goal.get("exercise_id"))]
    if not eligible:
        return progress

    current = max(epley(s["weight_kg"], s["reps"]) for s in eligible)
    progress["current"] = current
    if _reached(current, target):
        progress["percent"] = 100.0
        progress["remaining"] = 0.0
        reaching = [s.get("local_date") or "" for s in eligible
                    if _reached(epley(s["weight_kg"], s["reps"]), target)]
        progress["achieved_on"] = min(reaching) or None
    else:
        progress["percent"] = min(100.0, current / target * 100)
        progress["remaining"] = max(0.0, target - current)
    return progress


def week_start(today: date) -> date:
    """The Monday of the Monday–Sunday week containing `today`."""
    return today - timedelta(days=today.weekday())


def frequency_progress(goal: dict, workouts: list[dict], today: date) -> dict:
    """Progress of a frequency goal over the Monday–Sunday week containing `today`.
    `workouts` are dicts with at least `local_date` (YYYY-MM-DD)."""
    monday = week_start(today)
    first, last = monday.isoformat(), (monday + timedelta(days=6)).isoformat()
    target = goal["target"]
    current = sum(1 for w in workouts if first <= (w.get("local_date") or "") <= last)
    progress = _empty_progress()
    progress.update({
        "current": current,
        "percent": min(100.0, current / target * 100),
        "remaining": max(0, target - current),
        "met_this_week": current >= target,
        "week_start": first,
    })
    return progress


# --- Response shape ----------------------------------------------------------------------------

def _status(goal: dict, progress: dict) -> str:
    if goal["type"] == "strength" and progress["achieved_on"] is not None:
        return "completed"
    return "active"


class _Context:
    """What progress needs for one user, read from the database at most once per request."""

    def __init__(self, user_id: str, today: date):
        self.user_id = user_id
        self.today = today
        self._sets: dict[str, list[dict]] = {}
        self._workouts: list[dict] | None = None
        self._names: dict[str, str] = {}

    def load_sets(self, exercise_ids) -> None:
        missing = sorted({e for e in exercise_ids if e and e not in self._sets})
        if not missing:
            return
        for e in missing:
            self._sets[e] = []
        for s in models.user_sets(self.user_id, missing):
            self._sets.setdefault(s.get("exercise_id"), []).append(s)

    def load_names(self, exercise_ids) -> None:
        missing = sorted({e for e in exercise_ids if e and e not in self._names})
        if missing:
            for slug, exercise in models.get_exercises(missing).items():
                self._names[slug] = exercise.get("name")

    def sets(self, exercise_id: str) -> list[dict]:
        self.load_sets([exercise_id])
        return self._sets.get(exercise_id, [])

    def workouts(self) -> list[dict]:
        if self._workouts is None:
            self._workouts = [{"local_date": d} for d in models.user_workout_dates(self.user_id)]
        return self._workouts

    def name(self, exercise_id: str | None) -> str | None:
        if not exercise_id:
            return None
        self.load_names([exercise_id])
        return self._names.get(exercise_id)

    def progress(self, goal: dict) -> dict:
        if goal["type"] == "strength":
            return strength_progress(goal, self.sets(goal.get("exercise_id")))
        return frequency_progress(goal, self.workouts(), self.today)

    def full(self, goal: dict) -> dict:
        progress = self.progress(goal)
        return {
            "id": goal["id"],
            "type": goal["type"],
            "exercise_id": goal.get("exercise_id"),
            "exercise_name": self.name(goal.get("exercise_id")),
            "target": goal["target"],
            "start_date": goal["start_date"],
            "deadline": goal.get("deadline"),
            "created_at": iso(goal.get("created_at")),
            "status": _status(goal, progress),
            "progress": progress,
        }


def _ordered(goals: list[dict]) -> list[dict]:
    """Active oldest-created first, then completed newest `achieved_on` first (Decided 11)."""
    active = sorted((g for g in goals if g["status"] == "active"), key=lambda g: (g["created_at"] or "", g["id"]))
    done = sorted((g for g in goals if g["status"] == "completed"),
                  key=lambda g: (g["progress"]["achieved_on"] or "", g["created_at"] or ""), reverse=True)
    return active + done


def _all_full(ctx: _Context, stored: list[dict]) -> list[dict]:
    ctx.load_sets(g.get("exercise_id") for g in stored if g["type"] == "strength")
    ctx.load_names(g.get("exercise_id") for g in stored)
    return [ctx.full(g) for g in stored]


def list_goals(user_id: str, today: date) -> list[dict]:
    """This user's goals with status and progress, in API.md's order."""
    ctx = _Context(user_id, today)
    return _ordered(_all_full(ctx, models.user_goals(user_id)))


# --- Checking a body ---------------------------------------------------------------------------

def _bad(message: str) -> ApiError:
    return ApiError("bad_request", message)


def _day(value, field: str) -> date:
    if isinstance(value, str) and _DATE.match(value):
        try:
            return date.fromisoformat(value)
        except ValueError:
            pass
    raise _bad(f"{field} must be a date written YYYY-MM-DD.")


def _years_after(start: date, years: int) -> date:
    try:
        return start.replace(year=start.year + years)
    except ValueError:  # 29 February
        return start.replace(year=start.year + years, day=28)


def _strength_target(value) -> float:
    if not _number(value) or value <= 0 or value > MAX_STRENGTH_TARGET_KG:
        raise _bad(f"target must be a number above 0 and at most {MAX_STRENGTH_TARGET_KG} (kg).")
    return float(value)


def _frequency_target(value) -> int:
    low, high = FREQUENCY_TARGET
    if not _number(value) or value != int(value) or not low <= value <= high:
        raise _bad(f"target must be a whole number from {low} to {high}.")
    return int(value)


def _deadline(value, start_text: str) -> str | None:
    if value is None:
        return None
    deadline = _day(value, "deadline")
    start = date.fromisoformat(start_text)
    if deadline < start:
        raise _bad("deadline can't be before start_date.")
    if deadline > _years_after(start, MAX_DEADLINE_YEARS):
        raise _bad(f"deadline must be at most {MAX_DEADLINE_YEARS} years after start_date.")
    return value


def _check_exercise(slug) -> None:
    exercise = models.get_exercise(slug) if isinstance(slug, str) and slug else None
    if exercise is None:
        raise _bad("exercise_id isn't in the exercise library.")
    if exercise.get("load_type") in UNSUPPORTED_LOAD_TYPES:
        raise _bad("A strength goal needs an exercise with added weight.")


def _clean_new(body) -> dict:
    """The stored fields of a POST body, or ApiError("bad_request")."""
    if not isinstance(body, dict):
        raise _bad("Send a JSON object.")
    goal_id = body.get("id")
    if not isinstance(goal_id, str) or not _UUID.match(goal_id):
        raise _bad("id must be a lowercase UUID.")
    kind = body.get("type")
    if kind not in ("strength", "frequency"):
        raise _bad("type must be strength or frequency.")
    start = body.get("start_date")
    _day(start, "start_date")

    if kind == "strength":
        target = _strength_target(body.get("target"))
        deadline = _deadline(body.get("deadline"), start)
        _check_exercise(body.get("exercise_id"))
        exercise_id = body["exercise_id"]
    else:
        target = _frequency_target(body.get("target"))
        if body.get("exercise_id") is not None:
            raise _bad("A frequency goal has no exercise_id.")
        if body.get("deadline") is not None:
            raise _bad("A frequency goal has no deadline.")
        exercise_id, deadline = None, None

    return {"id": goal_id, "type": kind, "exercise_id": exercise_id, "target": target,
            "start_date": start, "deadline": deadline}


def _conflict(message: str) -> ApiError:
    return ApiError("conflict", message)


# --- Writes ------------------------------------------------------------------------------------

def _active_count(ctx: _Context, goals: list[dict]) -> int:
    ctx.load_sets(g.get("exercise_id") for g in goals if g["type"] == "strength")
    return sum(1 for g in goals if _status(g, ctx.progress(g)) == "active")


def create_goal(user_id: str, body: dict, today: date) -> tuple[dict, bool]:
    """Validates and creates a goal. Returns (goal, created); a repeated id returns the
    stored goal with created False. The limit checks and the write share one transaction."""
    data = _clean_new(body)
    data["created_at"] = datetime.now(timezone.utc)
    ctx = _Context(user_id, today)

    def check(goals: list[dict]) -> None:
        if data["type"] == "frequency" and any(g["type"] == "frequency" for g in goals):
            raise _conflict("You already have a weekly workout goal.")
        new_is_active = _status(data, ctx.progress(data)) == "active"
        if new_is_active and _active_count(ctx, goals) >= MAX_ACTIVE:
            raise _conflict(f"You can have at most {MAX_ACTIVE} active goals.")

    goal, created = models.add_goal(user_id, data, check)
    return ctx.full(goal), created


def update_goal(user_id: str, goal_id: str, body: dict, today: date) -> dict:
    """Changes `target` and, for strength, `deadline`; returns the full goal. The reopen
    check and the write share one transaction."""
    if not isinstance(body, dict):
        raise _bad("Send a JSON object.")
    if not isinstance(goal_id, str) or not _UUID.match(goal_id):
        raise ApiError("not_found", "No goal with that id.")
    ctx = _Context(user_id, today)

    def change(stored: dict, others: list[dict]) -> dict:
        changed = dict(stored)
        if stored["type"] == "strength":
            changed["target"] = _strength_target(body.get("target"))
            # The app leaves `deadline` out when there is none, so missing means no deadline.
            changed["deadline"] = _deadline(body.get("deadline"), stored["start_date"])
        else:
            changed["target"] = _frequency_target(body.get("target"))
            if body.get("deadline") is not None:
                raise _bad("A frequency goal has no deadline.")
        reopens = (_status(stored, ctx.progress(stored)) == "completed"
                   and _status(changed, ctx.progress(changed)) == "active")
        if reopens and _active_count(ctx, others) >= MAX_ACTIVE:
            raise _conflict(f"You can have at most {MAX_ACTIVE} active goals.")
        return changed

    changed = models.change_goal(user_id, goal_id, change)
    if changed is None:
        raise ApiError("not_found", "No goal with that id.")
    return ctx.full(changed)


def delete_goal(user_id: str, goal_id: str) -> None:
    """Deletes one of this user's goals. A missing one is no error."""
    if isinstance(goal_id, str) and _UUID.match(goal_id):
        models.delete_goal(user_id, goal_id)
    return None
