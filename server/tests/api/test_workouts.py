"""Workout endpoints against the Datastore emulator (specs/log-workout.llm.md, AC-1 to AC-3, AC-5 to AC-8).

AC-4 and AC-5 and AC-6 have their rules tested in services/test_workout_service.py; here a few
cases check that the endpoint answers 400 and saves nothing, and that history reaches
GET /exercises/mine.
"""
from __future__ import annotations

import copy
import json
import uuid
from datetime import datetime
from pathlib import Path

import pytest

import models
from services import auth

pytestmark = pytest.mark.emulator

ROOT = Path(__file__).resolve().parents[3]
SEED = ROOT / "server" / "seed" / "exercises.json"
POST_FIXTURE = ROOT / "shared" / "fixtures" / "workout_post.json"
DETAIL_FIXTURE = ROOT / "shared" / "fixtures" / "workout_detail.json"

WORKOUT_ID = "6f1c2b1e-4b7a-4c3e-9d2a-0a1b2c3d4e5f"
SET_KEYS = {"id", "exercise_id", "order", "superset_group", "set_type", "reps", "duration_s",
            "weight_kg", "added_load_kg", "effort_pct", "started_at", "ended_at", "rest_before_s",
            "time_source", "input"}
WORKOUT_KEYS = {"id", "name", "template_id", "status", "started_at", "ended_at", "timezone",
                "local_date", "bodyweight_kg", "sets"}
SUMMARY_KEYS = {"id", "name", "template_id", "started_at", "ended_at", "local_date",
                "set_count", "exercise_count"}


def fixture_body() -> dict:
    return copy.deepcopy(json.loads(POST_FIXTURE.read_text()))


def when(text: str) -> datetime:
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def error_of(response) -> dict:
    body = response.get_json()
    assert set(body) == {"error"}
    assert set(body["error"]) == {"code", "message"}
    return body["error"]


def a_workout(started="2026-11-02T17:00:00Z", ended="2026-11-02T18:00:00Z", sets=None, name="Workout") -> dict:
    """A new valid workout with its own ids."""
    if sets is None:
        sets = [{"exercise_id": "push_up", "reps": 10}]
    made = []
    for index, fields in enumerate(sets, start=1):
        made.append({"id": str(uuid.uuid4()), "order": index, "set_type": "working", **fields})
    return {"id": str(uuid.uuid4()), "name": name, "started_at": started, "ended_at": ended,
            "timezone": "America/Los_Angeles", "local_date": started[:10], "sets": made}


@pytest.fixture
def library(emulator):
    data = json.loads(SEED.read_text())
    models.put_exercises(data["exercises"] if isinstance(data, dict) else data)


@pytest.fixture
def post(client, signed_in, library):
    """POST /workouts. A good workout must answer 200 or 201 (pass accepted=False to see a refusal)."""
    def send(body, accepted=True):
        response = client.post("/api/v1/workouts", json=body, headers=signed_in["headers"])
        if accepted:
            assert response.status_code in (200, 201), response.get_json()
        return response
    return send


@pytest.fixture
def get_ok(client, signed_in):
    """GET with the signed-in token; must answer 200; returns the JSON."""
    def read(path):
        response = client.get(path, headers=signed_in["headers"])
        assert response.status_code == 200, response.get_json()
        return response.get_json()
    return read


@pytest.fixture
def mine(client, signed_in):
    def read():
        response = client.get("/api/v1/exercises/mine", headers=signed_in["headers"])
        assert response.status_code == 200
        return {i["exercise_id"]: i for i in response.get_json()["exercises"]}
    return read


# --- AC-1 ------------------------------------------------------------------------------------

REQUESTS = [("post", "/api/v1/workouts"), ("get", "/api/v1/workouts"),
            ("get", f"/api/v1/workouts/{WORKOUT_ID}")]


@pytest.mark.parametrize("method, path", REQUESTS)
def test_ac1_without_a_token_is_401(client, emulator, method, path):
    kwargs = {"json": fixture_body()} if method == "post" else {}
    response = getattr(client, method)(path, **kwargs)
    assert response.status_code == 401
    assert error_of(response)["code"] == "unauthorized"


@pytest.mark.parametrize("method, path", REQUESTS)
def test_ac1_with_an_unknown_token_is_401(client, emulator, method, path):
    kwargs = {"json": fixture_body()} if method == "post" else {}
    response = getattr(client, method)(path, headers={"Authorization": "Bearer nope"}, **kwargs)
    assert response.status_code == 401
    assert error_of(response)["code"] == "unauthorized"


# --- AC-2 ------------------------------------------------------------------------------------

def test_ac2_the_fixture_is_created_with_201_in_the_detail_shape(post):
    response = post(fixture_body())
    assert response.status_code == 201
    saved = response.get_json()
    assert WORKOUT_KEYS <= set(saved)
    assert saved["id"] == WORKOUT_ID
    assert saved["name"] == "Push 1"
    assert saved["status"] == "finished"
    assert saved["template_id"] == "3c9d7e1a-5b2f-4c8d-a6e4-7f8a9b0c1d2e"
    assert saved["timezone"] == "America/Los_Angeles"
    assert saved["local_date"] == "2026-11-02"
    assert saved["bodyweight_kg"] == 82.1
    assert when(saved["started_at"]) == when("2026-11-02T17:02:00Z")
    assert when(saved["ended_at"]) == when("2026-11-02T19:33:00Z")


def test_ac2_every_set_field_is_present_and_unsent_ones_are_null(post):
    sets = post(fixture_body()).get_json()["sets"]
    assert len(sets) == 2
    for item in sets:
        assert SET_KEYS <= set(item)
    bench, push_up = sets
    assert bench["superset_group"] is None
    assert bench["added_load_kg"] is None
    assert bench["duration_s"] is None
    assert push_up["weight_kg"] is None
    assert push_up["started_at"] is None
    assert push_up["ended_at"] is None


def test_ac2_set_values_come_back_as_sent(post):
    bench, push_up = post(fixture_body()).get_json()["sets"]
    assert bench["id"] == "a0b1c2d3-0000-4000-8000-000000000001"
    assert bench["exercise_id"] == "barbell_bench_press"
    assert bench["order"] == 1
    assert bench["set_type"] == "working"
    assert bench["reps"] == 5
    assert bench["effort_pct"] == 80
    assert bench["rest_before_s"] == 186
    assert bench["time_source"] == "rest_timer"
    assert bench["input"] == "manual"
    assert when(bench["started_at"]) == when("2026-11-02T17:10:05Z")
    assert when(bench["ended_at"]) == when("2026-11-02T17:10:40Z")
    assert push_up["superset_group"] == "a"
    assert push_up["added_load_kg"] == 0, "0 means plain bodyweight and must not become null"
    assert push_up["reps"] == 20


def test_ac2_weights_are_exactly_as_sent(post):
    exact = 157.5 * 0.45359237
    body = fixture_body()
    body["sets"][0]["weight_kg"] = exact
    body["bodyweight_kg"] = 82.123456789
    saved = post(body).get_json()
    assert saved["sets"][0]["weight_kg"] == exact
    assert saved["bodyweight_kg"] == 82.123456789


def test_ac2_sets_are_sorted_by_order_whatever_the_order_sent(post):
    body = fixture_body()
    body["sets"].reverse()
    assert [s["order"] for s in post(body).get_json()["sets"]] == [1, 2]


def test_ac2_template_id_is_null_when_not_sent(post):
    body = fixture_body()
    del body["template_id"]
    saved = post(body).get_json()
    assert saved["template_id"] is None


def test_ac2_the_same_data_as_the_detail_fixture_for_the_first_set(post):
    expected = json.loads(DETAIL_FIXTURE.read_text())["sets"][0]
    got = post(fixture_body()).get_json()["sets"][0]
    for key in ("id", "exercise_id", "order", "superset_group", "set_type", "reps", "duration_s",
                "weight_kg", "added_load_kg", "effort_pct", "rest_before_s", "time_source", "input"):
        assert got[key] == expected[key], key


# --- AC-3 ------------------------------------------------------------------------------------

def test_ac3_the_same_request_again_is_200_with_the_same_body(post):
    first = post(fixture_body())
    second = post(fixture_body())
    assert first.status_code == 201
    assert second.status_code == 200
    assert second.get_json() == first.get_json()


def test_ac3_a_repeat_changes_no_stored_data(post, get_ok, mine):
    post(fixture_body())
    before_list = get_ok("/api/v1/workouts")
    before_mine = mine()
    post(fixture_body())
    post(fixture_body())
    assert get_ok("/api/v1/workouts") == before_list
    assert mine() == before_mine
    assert before_mine["barbell_bench_press"]["use_count"] == 1


def test_ac3_the_same_id_with_a_different_body_returns_the_saved_workout(post, get_ok, mine):
    first = post(fixture_body())
    other = fixture_body()
    other["name"] = "Something else"
    other["sets"] = [{"id": str(uuid.uuid4()), "exercise_id": "deadlift", "order": 1,
                      "set_type": "working", "reps": 3, "weight_kg": 140}]
    second = post(other)
    assert second.status_code == 200
    assert second.get_json() == first.get_json()
    assert second.get_json()["name"] == "Push 1"
    assert get_ok(f"/api/v1/workouts/{WORKOUT_ID}") == first.get_json()
    assert "deadlift" not in mine()


# --- AC-4 (the endpoint side) ----------------------------------------------------------------

def bad_id(body):
    body["id"] = body["id"].upper()


def duplicate_order(body):
    body["sets"][1]["order"] = 1


def unknown_exercise(body):
    body["sets"][1]["exercise_id"] = "not_an_exercise"


def no_sets(body):
    body["sets"] = []


def missing_name(body):
    del body["name"]


def ends_early(body):
    body["ended_at"] = "2026-11-02T16:00:00Z"


@pytest.mark.parametrize("damage", [bad_id, duplicate_order, unknown_exercise, no_sets, missing_name, ends_early])
def test_ac4_a_bad_workout_is_400_and_saves_nothing(post, get_ok, mine, damage):
    body = fixture_body()
    damage(body)
    response = post(body, accepted=False)
    assert response.status_code == 400
    assert error_of(response)["code"] == "bad_request"
    assert get_ok("/api/v1/workouts") == {"workouts": []}
    assert mine() == {}


# --- AC-5 ------------------------------------------------------------------------------------

def test_ac5_a_saved_workout_updates_one_user_exercise_per_exercise(post, mine):
    post(fixture_body())
    history = mine()
    assert set(history) == {"barbell_bench_press", "push_up"}
    bench = history["barbell_bench_press"]
    assert bench["use_count"] == 1
    assert when(bench["last_used_at"]) == when("2026-11-02T19:33:00Z")
    assert bench["last_set"]["weight_kg"] == 70.3
    assert bench["last_set"]["reps"] == 5
    assert bench["last_set"]["effort_pct"] == 80
    push_up = history["push_up"]
    assert push_up["last_set"]["added_load_kg"] == 0
    assert push_up["last_set"]["reps"] == 20
    assert push_up["last_set"]["weight_kg"] is None


def test_ac5_use_count_is_per_workout_not_per_set(post, mine):
    sets = [{"exercise_id": "push_up", "reps": n} for n in (10, 9, 8)]
    post(a_workout(sets=sets))
    assert mine()["push_up"]["use_count"] == 1


def test_ac5_a_second_workout_adds_one_and_moves_last_used_at_and_last_set(post, mine):
    post(a_workout(sets=[{"exercise_id": "push_up", "reps": 10}]))
    post(a_workout(started="2026-11-03T17:00:00Z", ended="2026-11-03T18:00:00Z",
                   sets=[{"exercise_id": "push_up", "reps": 15}]))
    push_up = mine()["push_up"]
    assert push_up["use_count"] == 2
    assert when(push_up["last_used_at"]) == when("2026-11-03T18:00:00Z")
    assert push_up["last_set"]["reps"] == 15


def test_ac5_last_set_skips_a_trailing_drop_set(post, mine):
    sets = [{"exercise_id": "barbell_bench_press", "reps": 5, "weight_kg": 100},
            {"exercise_id": "barbell_bench_press", "reps": 12, "weight_kg": 60, "set_type": "dropset"}]
    post(a_workout(sets=sets))
    assert mine()["barbell_bench_press"]["last_set"]["weight_kg"] == 100


def test_ac5_a_workout_with_other_exercises_leaves_their_history_alone(post, mine):
    post(a_workout(sets=[{"exercise_id": "push_up", "reps": 10}]))
    post(a_workout(started="2026-11-03T17:00:00Z", ended="2026-11-03T18:00:00Z",
                   sets=[{"exercise_id": "deadlift", "reps": 3, "weight_kg": 150}]))
    history = mine()
    assert history["push_up"]["use_count"] == 1
    assert history["deadlift"]["use_count"] == 1


def test_ac5_other_users_history_is_not_touched(client, post, mine):
    post(fixture_body())
    other = auth.sign_in("someone_else")
    response = client.get("/api/v1/exercises/mine", headers={"Authorization": f"Bearer {other['token']}"})
    assert response.status_code == 200
    assert response.get_json() == {"exercises": []}
    assert mine()["push_up"]["use_count"] == 1


# --- AC-6 ------------------------------------------------------------------------------------

def test_ac6_a_workout_that_ended_earlier_only_adds_to_use_count(post, mine):
    post(a_workout(started="2026-11-05T17:00:00Z", ended="2026-11-05T18:00:00Z",
                   sets=[{"exercise_id": "push_up", "reps": 30}]))
    before = mine()["push_up"]
    post(a_workout(started="2026-11-01T17:00:00Z", ended="2026-11-01T18:00:00Z",
                   sets=[{"exercise_id": "push_up", "reps": 5}]))
    after = mine()["push_up"]
    assert after["use_count"] == 2
    assert after["last_used_at"] == before["last_used_at"]
    assert after["last_set"] == before["last_set"]
    assert after["last_set"]["reps"] == 30


# --- AC-7 ------------------------------------------------------------------------------------

def test_ac7_get_returns_the_saved_workout(post, get_ok):
    created = post(fixture_body()).get_json()
    assert get_ok(f"/api/v1/workouts/{WORKOUT_ID}") == created


def test_ac7_an_unknown_id_is_404(client, post, signed_in):
    post(fixture_body())
    response = client.get(f"/api/v1/workouts/{uuid.uuid4()}", headers=signed_in["headers"])
    assert response.status_code == 404
    assert error_of(response)["code"] == "not_found"


def test_ac7_another_users_workout_is_404(client, post, signed_in):
    post(fixture_body())
    other = auth.sign_in("someone_else")
    response = client.get(f"/api/v1/workouts/{WORKOUT_ID}",
                          headers={"Authorization": f"Bearer {other['token']}"})
    assert response.status_code == 404
    assert error_of(response)["code"] == "not_found"


# --- AC-8 ------------------------------------------------------------------------------------

def listing(client, signed_in, query=""):
    return client.get(f"/api/v1/workouts{query}", headers=signed_in["headers"])


def names_of(get_ok, query=""):
    return [w["name"] for w in get_ok(f"/api/v1/workouts{query}")["workouts"]]


def test_ac8_no_workouts_gives_an_empty_list(get_ok):
    assert get_ok("/api/v1/workouts") == {"workouts": []}


def test_ac8_summary_shape_with_counts_and_no_sets(post, get_ok):
    post(fixture_body())
    items = get_ok("/api/v1/workouts")["workouts"]
    assert len(items) == 1
    item = items[0]
    assert set(item) == SUMMARY_KEYS
    assert item["id"] == WORKOUT_ID
    assert item["name"] == "Push 1"
    assert item["template_id"] == "3c9d7e1a-5b2f-4c8d-a6e4-7f8a9b0c1d2e"
    assert item["local_date"] == "2026-11-02"
    assert item["set_count"] == 2
    assert item["exercise_count"] == 2
    assert when(item["started_at"]) == when("2026-11-02T17:02:00Z")
    assert when(item["ended_at"]) == when("2026-11-02T19:33:00Z")


def test_ac8_counts_sets_and_distinct_exercises(post, get_ok):
    sets = [{"exercise_id": "push_up", "reps": n} for n in (10, 9, 8)]
    post(a_workout(sets=sets))
    item = get_ok("/api/v1/workouts")["workouts"][0]
    assert (item["set_count"], item["exercise_count"]) == (3, 1)


def test_ac8_newest_started_at_first(post, get_ok):
    middle = a_workout(started="2026-11-02T17:00:00Z", ended="2026-11-02T18:00:00Z", name="middle")
    oldest = a_workout(started="2026-10-01T17:00:00Z", ended="2026-10-01T18:00:00Z", name="oldest")
    newest = a_workout(started="2026-11-04T17:00:00Z", ended="2026-11-04T18:00:00Z", name="newest")
    for body in (middle, oldest, newest):
        assert post(body).status_code == 201
    assert names_of(get_ok) == ["newest", "middle", "oldest"]


def test_ac8_limit_caps_the_list(post, get_ok):
    for day in (1, 2, 3):
        post(a_workout(started=f"2026-11-0{day}T17:00:00Z", ended=f"2026-11-0{day}T18:00:00Z", name=f"d{day}"))
    assert names_of(get_ok, "?limit=1") == ["d3"]
    assert names_of(get_ok, "?limit=2") == ["d3", "d2"]


def test_ac8_the_default_limit_is_20(post, get_ok):
    for minute in range(21):
        post(a_workout(started=f"2026-11-02T17:{minute:02d}:00Z", ended=f"2026-11-02T18:{minute:02d}:00Z"))
    assert len(names_of(get_ok)) == 20
    assert len(names_of(get_ok, "?limit=100")) == 21


@pytest.mark.parametrize("limit", ["0", "101", "-1", "abc", ""])
def test_ac8_a_bad_limit_is_400(client, signed_in, limit):
    response = listing(client, signed_in, f"?limit={limit}")
    assert response.status_code == 400
    assert error_of(response)["code"] == "bad_request"


@pytest.mark.parametrize("limit", ["1", "100"])
def test_ac8_limit_at_the_edges_is_accepted(client, signed_in, limit):
    assert listing(client, signed_in, f"?limit={limit}").status_code == 200


def test_ac8_only_this_users_workouts_are_listed(client, post, signed_in):
    post(fixture_body())
    other = auth.sign_in("someone_else")
    response = client.get("/api/v1/workouts", headers={"Authorization": f"Bearer {other['token']}"})
    assert response.status_code == 200
    assert response.get_json() == {"workouts": []}
