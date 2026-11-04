"""Workout rules (specs/log-workout.llm.md, AC-4 to AC-6).

Pure logic: no database and no Flask. The body comes from shared/fixtures/workout_post.json.
"""
from __future__ import annotations

import copy
import json
import uuid
from datetime import datetime, timezone
from pathlib import Path

import pytest

from services import workout_service
from services.errors import ApiError

FIXTURE = Path(__file__).resolve().parents[3] / "shared" / "fixtures" / "workout_post.json"
KNOWN = {"barbell_bench_press", "push_up", "deadlift"}


def base_body() -> dict:
    return copy.deepcopy(json.loads(FIXTURE.read_text()))


def make_set(order: int, exercise_id: str = "push_up", **extra) -> dict:
    return {"id": str(uuid.uuid4()), "exercise_id": exercise_id, "order": order,
            "set_type": "working", "reps": 10, **extra}


def assert_bad_request(body: dict) -> None:
    with pytest.raises(ApiError) as caught:
        workout_service.validate_workout(body, KNOWN)
    assert caught.value.code == "bad_request"


# --- AC-4: what is accepted ------------------------------------------------------------------

def test_ac4_the_fixture_is_valid_and_keeps_its_sets():
    clean = workout_service.validate_workout(base_body(), KNOWN)
    assert clean.get("workout", {}).get("id") == "6f1c2b1e-4b7a-4c3e-9d2a-0a1b2c3d4e5f"
    assert [s["id"] for s in clean.get("sets", [])] == [
        "a0b1c2d3-0000-4000-8000-000000000001", "a0b1c2d3-0000-4000-8000-000000000002"]


def test_ac4_unsent_set_fields_come_back_as_none():
    clean = workout_service.validate_workout(base_body(), KNOWN)
    second = (clean.get("sets") or [{}, {}])[1]
    assert second.get("weight_kg", "missing") is None
    assert second.get("added_load_kg") == 0
    assert second.get("duration_s", "missing") is None


def test_ac4_template_id_and_bodyweight_may_be_null_or_missing():
    body = base_body()
    del body["template_id"]
    body["bodyweight_kg"] = None
    workout = workout_service.validate_workout(body, KNOWN).get("workout", {})
    assert workout.get("id") == body["id"]
    assert workout.get("template_id", "missing") is None
    assert workout.get("bodyweight_kg", "missing") is None


@pytest.mark.parametrize("effort", [0, 100])
def test_ac4_effort_at_the_edges_is_valid(effort):
    body = base_body()
    body["sets"][0]["effort_pct"] = effort
    sets = workout_service.validate_workout(body, KNOWN).get("sets", [])
    assert [s.get("effort_pct") for s in sets][:1] == [effort]


def test_ac4_weight_zero_is_valid():
    body = base_body()
    body["sets"][0]["weight_kg"] = 0
    assert len(workout_service.validate_workout(body, KNOWN).get("sets", [])) == 2


def test_ac4_a_negative_added_load_is_valid_assistance():
    body = base_body()
    body["sets"][1]["added_load_kg"] = -20
    sets = workout_service.validate_workout(body, KNOWN).get("sets", [])
    assert [s.get("added_load_kg") for s in sets][1:] == [-20]


def test_ac4_a_timed_set_with_only_duration_is_valid():
    body = base_body()
    body["sets"][1] = {"id": body["sets"][1]["id"], "exercise_id": "push_up", "order": 2,
                       "set_type": "working", "duration_s": 45}
    sets = workout_service.validate_workout(body, KNOWN).get("sets", [])
    assert [(s.get("duration_s"), s.get("reps", "missing")) for s in sets][1:] == [(45, None)]


def test_ac4_ended_at_equal_to_started_at_is_valid():
    body = base_body()
    body["ended_at"] = body["started_at"]
    assert workout_service.validate_workout(body, KNOWN).get("workout", {}).get("id") == body["id"]


def test_ac4_exactly_300_sets_is_valid():
    body = base_body()
    body["sets"] = [make_set(i) for i in range(1, 301)]
    assert len(workout_service.validate_workout(body, KNOWN).get("sets", [])) == 300


def test_ac4_one_set_is_valid():
    body = base_body()
    body["sets"] = body["sets"][:1]
    assert len(workout_service.validate_workout(body, KNOWN).get("sets", [])) == 1


# --- AC-4: what is refused -------------------------------------------------------------------

@pytest.mark.parametrize("bad_id", [
    "6F1C2B1E-4B7A-4C3E-9D2A-0A1B2C3D4E5F",   # upper case
    "not-a-uuid", "", "6f1c2b1e4b7a4c3e9d2a0a1b2c3d4e5f",
])
def test_ac4_workout_id_must_be_a_lowercase_uuid(bad_id):
    body = base_body()
    body["id"] = bad_id
    assert_bad_request(body)


@pytest.mark.parametrize("bad_id", ["A0B1C2D3-0000-4000-8000-000000000001", "set-1", ""])
def test_ac4_set_id_must_be_a_lowercase_uuid(bad_id):
    body = base_body()
    body["sets"][0]["id"] = bad_id
    assert_bad_request(body)


def test_ac4_two_sets_with_the_same_id_are_refused():
    body = base_body()
    body["sets"][1]["id"] = body["sets"][0]["id"]
    assert_bad_request(body)


def test_ac4_two_sets_with_the_same_order_are_refused():
    body = base_body()
    body["sets"][1]["order"] = body["sets"][0]["order"]
    assert_bad_request(body)


def test_ac4_unknown_exercise_is_refused():
    body = base_body()
    body["sets"][1]["exercise_id"] = "not_an_exercise"
    assert_bad_request(body)


@pytest.mark.parametrize("field, value", [
    ("set_type", "superset"), ("set_type", "Working"),
    ("time_source", "guess"), ("input", "telepathy"),
])
def test_ac4_unknown_enum_values_are_refused(field, value):
    body = base_body()
    body["sets"][0][field] = value
    assert_bad_request(body)


@pytest.mark.parametrize("effort", [-1, 101])
def test_ac4_effort_outside_0_to_100_is_refused(effort):
    body = base_body()
    body["sets"][0]["effort_pct"] = effort
    assert_bad_request(body)


def test_ac4_a_negative_weight_is_refused():
    body = base_body()
    body["sets"][0]["weight_kg"] = -0.5
    assert_bad_request(body)


def test_ac4_a_set_with_neither_reps_nor_duration_is_refused():
    body = base_body()
    del body["sets"][0]["reps"]
    assert_bad_request(body)


def test_ac4_a_set_with_null_reps_and_null_duration_is_refused():
    body = base_body()
    body["sets"][0]["reps"] = None
    body["sets"][0]["duration_s"] = None
    assert_bad_request(body)


def test_ac4_no_sets_is_refused():
    body = base_body()
    body["sets"] = []
    assert_bad_request(body)


def test_ac4_301_sets_are_refused():
    body = base_body()
    body["sets"] = [make_set(i) for i in range(1, 302)]
    assert_bad_request(body)


def test_ac4_ended_before_started_is_refused():
    body = base_body()
    body["ended_at"] = "2026-11-02T17:01:59Z"
    assert_bad_request(body)


@pytest.mark.parametrize("local_date", ["11/02/2026", "2026-1-2", "2026-13-45", "20261102", "", "today"])
def test_ac4_local_date_must_be_yyyy_mm_dd(local_date):
    body = base_body()
    body["local_date"] = local_date
    assert_bad_request(body)


@pytest.mark.parametrize("field", ["name", "started_at", "ended_at", "timezone", "local_date"])
def test_ac4_a_missing_required_field_is_refused(field):
    body = base_body()
    del body[field]
    assert_bad_request(body)


# --- AC-5: history for one exercise ---------------------------------------------------------

def finished(ended_at: datetime) -> dict:
    return {"id": str(uuid.uuid4()), "ended_at": ended_at}


def a_set(order: int, set_type: str = "working", **extra) -> dict:
    fields = {"id": str(uuid.uuid4()), "exercise_id": "barbell_bench_press", "order": order,
              "set_type": set_type, "reps": 5, "duration_s": None, "weight_kg": 60.0,
              "added_load_kg": None, "effort_pct": 80}
    fields.update(extra)
    return fields


LATE = datetime(2026, 11, 2, 19, 33, tzinfo=timezone.utc)
EARLY = datetime(2026, 10, 1, 19, 33, tzinfo=timezone.utc)


def test_ac5_the_first_workout_makes_use_count_1_and_sets_last_used_at():
    merged = workout_service.merge_user_exercise(None, finished(LATE), [a_set(1)])
    assert merged.get("use_count") == 1
    assert merged.get("last_used_at") == LATE


def test_ac5_use_count_goes_up_by_one_per_workout_not_per_set():
    sets = [a_set(1), a_set(2), a_set(3)]
    old = {"use_count": 4, "last_used_at": EARLY, "last_set": None}
    assert workout_service.merge_user_exercise(old, finished(LATE), sets).get("use_count") == 5


def test_ac5_last_set_has_the_five_fields_of_api_md():
    merged = workout_service.merge_user_exercise(
        None, finished(LATE), [a_set(1, reps=5, weight_kg=70.3, effort_pct=80)])
    assert merged.get("last_set") == {"weight_kg": 70.3, "added_load_kg": None, "reps": 5,
                                      "duration_s": None, "effort_pct": 80}


def test_ac5_last_set_is_the_highest_order_working_set_even_when_listed_out_of_order():
    sets = [a_set(3, reps=3), a_set(1, reps=1), a_set(2, reps=2)]
    merged = workout_service.merge_user_exercise(None, finished(LATE), sets)
    assert merged.get("last_set", {}).get("reps") == 3


def test_ac5_a_drop_set_after_a_working_set_is_not_the_last_set():
    sets = [a_set(1, "working", reps=6), a_set(2, "dropset", reps=12)]
    assert workout_service.merge_user_exercise(None, finished(LATE), sets).get("last_set", {}).get("reps") == 6


def test_ac5_a_warm_up_after_a_working_set_is_not_the_last_set():
    sets = [a_set(1, "working", reps=6), a_set(2, "warmup", reps=12)]
    assert workout_service.merge_user_exercise(None, finished(LATE), sets).get("last_set", {}).get("reps") == 6


def test_ac5_a_failure_set_counts_like_a_working_set():
    sets = [a_set(1, "working", reps=6), a_set(2, "failure", reps=4), a_set(3, "dropset", reps=12)]
    assert workout_service.merge_user_exercise(None, finished(LATE), sets).get("last_set", {}).get("reps") == 4


def test_ac5_with_no_working_or_failure_set_the_last_set_is_used():
    sets = [a_set(1, "warmup", reps=10), a_set(2, "dropset", reps=8), a_set(3, "warmup", reps=7)]
    assert workout_service.merge_user_exercise(None, finished(LATE), sets).get("last_set", {}).get("reps") == 7


def test_ac5_a_bodyweight_last_set_keeps_added_load_and_null_weight():
    sets = [a_set(1, weight_kg=None, added_load_kg=0, reps=20, effort_pct=90)]
    merged = workout_service.merge_user_exercise(None, finished(LATE), sets)
    assert merged.get("last_set") == {"weight_kg": None, "added_load_kg": 0, "reps": 20,
                                      "duration_s": None, "effort_pct": 90}


def test_ac5_a_newer_workout_replaces_last_used_at_and_last_set():
    old = {"use_count": 2, "last_used_at": EARLY,
           "last_set": {"weight_kg": 50.0, "added_load_kg": None, "reps": 8,
                        "duration_s": None, "effort_pct": 70}}
    merged = workout_service.merge_user_exercise(old, finished(LATE), [a_set(1, reps=5, weight_kg=60.0)])
    assert merged.get("last_used_at") == LATE
    assert merged["last_set"]["weight_kg"] == 60.0
    assert merged["use_count"] == 3


def test_ac5_the_old_history_is_not_changed_in_place():
    old = {"use_count": 2, "last_used_at": EARLY, "last_set": None}
    snapshot = copy.deepcopy(old)
    merged = workout_service.merge_user_exercise(old, finished(LATE), [a_set(1)])
    assert merged.get("use_count") == 3
    assert old == snapshot


# --- AC-6: a workout logged late -------------------------------------------------------------

def test_ac6_an_older_workout_adds_to_use_count_only():
    last_set = {"weight_kg": 80.0, "added_load_kg": None, "reps": 3, "duration_s": None, "effort_pct": 95}
    old = {"use_count": 7, "last_used_at": LATE, "last_set": last_set}
    merged = workout_service.merge_user_exercise(old, finished(EARLY), [a_set(1, reps=12, weight_kg=40.0)])
    assert merged.get("use_count") == 8
    assert merged.get("last_used_at") == LATE
    assert merged.get("last_set") == last_set
