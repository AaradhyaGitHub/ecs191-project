"""Exercise endpoints against the Datastore emulator (AC-1, AC-6, AC-7, AC-8)."""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

import pytest

import models
from services import auth

pytestmark = pytest.mark.emulator

SEED = Path(__file__).resolve().parents[2] / "seed" / "exercises.json"

EXERCISE_KEYS = {"id", "name", "aliases", "load_type", "bodyweight_fraction", "muscles",
                 "groups", "primary_muscles"}


def _load_seed() -> list[dict]:
    data = json.loads(SEED.read_text())
    return data["exercises"] if isinstance(data, dict) else data


@pytest.fixture
def library(emulator):
    seed = _load_seed()
    models.put_exercises(seed)
    return seed


def error_of(response) -> dict:
    body = response.get_json()
    assert set(body) == {"error"}
    assert set(body["error"]) == {"code", "message"}
    return body["error"]


# --- AC-1 ----------------------------------------------------------------------------------

def test_ac1_no_text_returns_the_whole_library_a_to_z(client, library):
    response = client.get("/api/v1/exercises")
    assert response.status_code == 200
    items = response.get_json()["exercises"]
    assert len(items) == len(library)
    result = [i["name"] for i in items]
    assert result == sorted(result, key=str.lower)


def test_ac1_needs_no_authorization_header(client, library):
    response = client.get("/api/v1/exercises")
    assert response.status_code == 200
    assert response.get_json()["exercises"], "the library should not be empty"


def test_ac1_blank_text_is_the_same_as_no_text(client, library):
    everything = client.get("/api/v1/exercises").get_json()
    assert len(everything["exercises"]) == len(library)
    blank = client.get("/api/v1/exercises?q=%20%20")
    assert blank.status_code == 200
    assert blank.get_json() == everything
    empty = client.get("/api/v1/exercises?q=")
    assert empty.get_json() == everything


def test_ac1_items_have_the_api_md_shape(client, library):
    items = client.get("/api/v1/exercises").get_json()["exercises"]
    assert items
    for item in items:
        assert set(item) == EXERCISE_KEYS, item.get("name")
    bench = next(i for i in items if i["id"] == "barbell_bench_press")
    assert bench["name"] == "Bench Press"
    assert bench["load_type"] == "barbell"
    assert bench["groups"] == ["chest"]
    assert bench["primary_muscles"] == ["Chest"]
    assert {"muscle_id", "role", "weight"} == set(bench["muscles"][0])


def test_ac1_text_and_group_reach_the_service(client, library):
    items = client.get("/api/v1/exercises?q=bench").get_json()["exercises"]
    assert [i["name"] for i in items] == ["Bench Press", "Dumbbell Bench Press", "Incline Bench Press"]
    legs = client.get("/api/v1/exercises?group=legs").get_json()["exercises"]
    assert "Deadlift" in [i["name"] for i in legs]
    assert all("legs" in i["groups"] for i in legs)


# --- AC-6 ----------------------------------------------------------------------------------

def test_ac6_unknown_group_is_400_bad_request(client, library):
    response = client.get("/api/v1/exercises?group=biceps")
    assert response.status_code == 400
    assert error_of(response)["code"] == "bad_request"


def test_ac6_unknown_group_is_400_even_with_text(client, library):
    response = client.get("/api/v1/exercises?q=bench&group=nonsense")
    assert response.status_code == 400
    assert error_of(response)["code"] == "bad_request"


# --- AC-7 ----------------------------------------------------------------------------------

def test_ac7_mine_without_a_token_is_401(client, emulator):
    response = client.get("/api/v1/exercises/mine")
    assert response.status_code == 401
    assert error_of(response)["code"] == "unauthorized"


def test_ac7_mine_with_an_unknown_token_is_401(client, emulator):
    response = client.get("/api/v1/exercises/mine", headers={"Authorization": "Bearer not-a-real-token"})
    assert response.status_code == 401
    assert error_of(response)["code"] == "unauthorized"


# --- AC-8 ----------------------------------------------------------------------------------

def test_ac8_a_user_with_no_history_gets_an_empty_list(client, signed_in):
    response = client.get("/api/v1/exercises/mine", headers=signed_in["headers"])
    assert response.status_code == 200
    assert response.get_json() == {"exercises": []}


def test_ac8_one_item_per_user_exercise(client, signed_in):
    when = datetime(2026, 11, 1, 18, 10, tzinfo=timezone.utc)
    last_set = {"weight_kg": None, "added_load_kg": 0, "reps": 20, "duration_s": None, "effort_pct": 90}
    models.put_user_exercise(signed_in["user_id"], "push_up", {
        "use_count": 14, "last_used_at": when, "last_set": last_set,
        "best_e1rm_kg": None, "best_e1rm_at": None})
    models.put_user_exercise(signed_in["user_id"], "barbell_bench_press", {
        "use_count": 3, "last_used_at": when,
        "last_set": {"weight_kg": 70.3, "added_load_kg": None, "reps": 5, "duration_s": None,
                     "effort_pct": 80}})

    response = client.get("/api/v1/exercises/mine", headers=signed_in["headers"])
    assert response.status_code == 200
    items = response.get_json()["exercises"]
    assert len(items) == 2
    by_id = {i["exercise_id"]: i for i in items}
    assert set(by_id) == {"push_up", "barbell_bench_press"}

    push_up = by_id["push_up"]
    assert {"exercise_id", "use_count", "last_used_at", "last_set"} <= set(push_up)
    assert push_up["use_count"] == 14
    assert push_up["last_set"]["reps"] == 20
    assert push_up["last_set"]["effort_pct"] == 90
    assert datetime.fromisoformat(push_up["last_used_at"].replace("Z", "+00:00")) == when
    assert by_id["barbell_bench_press"]["last_set"]["weight_kg"] == 70.3


def test_ac8_other_users_exercises_are_not_included(client, signed_in):
    when = datetime(2026, 11, 1, 18, 10, tzinfo=timezone.utc)
    other = auth.sign_in("someone_else")
    models.put_user_exercise(other["user_id"], "deadlift", {"use_count": 9, "last_used_at": when})
    models.put_user_exercise(signed_in["user_id"], "push_up", {"use_count": 1, "last_used_at": when})

    mine = client.get("/api/v1/exercises/mine", headers=signed_in["headers"]).get_json()["exercises"]
    assert [i["exercise_id"] for i in mine] == ["push_up"]
