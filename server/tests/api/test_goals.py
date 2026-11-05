"""Goal endpoints against the Datastore emulator (specs/goals.llm.md, AC-1 to AC-4, AC-6, AC-8 to AC-10).

Workouts are saved through `POST /workouts`, so progress is checked end to end.
"""
from __future__ import annotations

import json
import uuid
from pathlib import Path

import pytest

import models
from services import auth

pytestmark = pytest.mark.emulator

SEED = Path(__file__).resolve().parents[2] / "seed" / "exercises.json"
GOALS = "/api/v1/goals"
WORKOUTS = "/api/v1/workouts"
TODAY = "2026-11-04"  # a Wednesday; the week is 2026-11-02 .. 2026-11-08
BENCH = "barbell_bench_press"

GOAL_KEYS = {"id", "type", "exercise_id", "exercise_name", "target", "start_date", "deadline",
             "created_at", "status", "progress"}
PROGRESS_KEYS = {"current", "percent", "remaining", "achieved_on", "met_this_week", "week_start"}


def _load_seed() -> list[dict]:
    data = json.loads(SEED.read_text())
    return data["exercises"] if isinstance(data, dict) else data


@pytest.fixture
def library(emulator):
    seed = _load_seed()
    models.put_exercises(seed)
    return seed


@pytest.fixture
def other_user(emulator):
    session = auth.sign_in("other_user")
    return {"user_id": session["user_id"], "headers": {"Authorization": f"Bearer {session['token']}"}}


def error_of(response) -> dict:
    body = response.get_json()
    assert set(body) == {"error"}
    assert set(body["error"]) == {"code", "message"}
    return body["error"]


def new_id() -> str:
    return str(uuid.uuid4())


def strength(**changes) -> dict:
    body = {"id": new_id(), "type": "strength", "exercise_id": BENCH, "target": 100.0,
            "start_date": "2026-10-20", "deadline": "2026-12-15"}
    body.update(changes)
    return body


def frequency(**changes) -> dict:
    body = {"id": new_id(), "type": "frequency", "target": 4, "start_date": "2026-10-12"}
    body.update(changes)
    return body


def post(client, headers, body):
    return client.post(GOALS, json=body, headers=headers)


def create(client, headers, body) -> dict:
    response = post(client, headers, body)
    assert response.status_code == 201
    return response.get_json()


def listed(client, headers, today=TODAY) -> list[dict]:
    response = client.get(f"{GOALS}?today={today}", headers=headers)
    assert response.status_code == 200
    return response.get_json()["goals"]


def save_workout(client, headers, local_date, sets=None, workout_id=None) -> str:
    """Saves a finished workout. `sets` is a list of (exercise_id, set_type, weight_kg, reps)."""
    sets = sets if sets is not None else [(BENCH, "working", 60.0, 5)]
    workout_id = workout_id or new_id()
    body = {
        "id": workout_id, "name": "Push 1",
        "started_at": f"{local_date}T17:02:00Z", "ended_at": f"{local_date}T18:02:00Z",
        "timezone": "America/Los_Angeles", "local_date": local_date,
        "sets": [{"id": new_id(), "exercise_id": ex, "order": n + 1, "set_type": kind,
                  "weight_kg": weight, "reps": reps} for n, (ex, kind, weight, reps) in enumerate(sets)],
    }
    response = client.post(WORKOUTS, json=body, headers=headers)
    assert response.status_code == 201, response.get_json()
    return workout_id


# --- AC-10: sign-in -------------------------------------------------------------------------

@pytest.mark.parametrize("method,path", [
    ("get", GOALS), ("post", GOALS), ("put", f"{GOALS}/{uuid.uuid4()}"), ("delete", f"{GOALS}/{uuid.uuid4()}")])
def test_ac10_no_token_is_401_unauthorized(client, library, method, path):
    kwargs = {"json": strength()} if method in ("post", "put") else {}
    response = getattr(client, method)(path, **kwargs)
    assert response.status_code == 401
    assert error_of(response)["code"] == "unauthorized"


@pytest.mark.parametrize("method,path", [("get", GOALS), ("post", GOALS)])
def test_ac10_unknown_token_is_401_unauthorized(client, library, method, path):
    kwargs = {"json": strength()} if method == "post" else {}
    response = getattr(client, method)(path, headers={"Authorization": "Bearer nope"}, **kwargs)
    assert response.status_code == 401
    assert error_of(response)["code"] == "unauthorized"


def test_ac10_a_rejected_post_stores_nothing(client, library, signed_in):
    client.post(GOALS, json=strength())
    assert listed(client, signed_in["headers"]) == []


def test_ac10_a_rejected_delete_deletes_nothing(client, library, signed_in):
    goal = create(client, signed_in["headers"], strength())
    assert client.delete(f"{GOALS}/{goal['id']}").status_code == 401
    assert [g["id"] for g in listed(client, signed_in["headers"])] == [goal["id"]]


# --- AC-1: create ---------------------------------------------------------------------------

def test_ac1_a_new_id_is_201_with_the_full_goal(client, library, signed_in):
    body = strength()
    response = post(client, signed_in["headers"], body)
    assert response.status_code == 201
    goal = response.get_json()
    assert set(goal) == GOAL_KEYS
    assert set(goal["progress"]) == PROGRESS_KEYS
    assert goal["id"] == body["id"]
    assert goal["type"] == "strength"
    assert goal["exercise_id"] == BENCH
    assert goal["exercise_name"] == "Bench Press"
    assert goal["target"] == 100.0
    assert goal["start_date"] == "2026-10-20"
    assert goal["deadline"] == "2026-12-15"
    assert isinstance(goal["created_at"], str) and goal["created_at"]
    assert goal["status"] == "active"
    assert goal["progress"]["current"] is None


def test_ac1_a_frequency_goal_is_201_with_null_exercise_and_deadline(client, library, signed_in):
    goal = create(client, signed_in["headers"], frequency())
    assert set(goal) == GOAL_KEYS
    assert goal["exercise_id"] is None
    assert goal["exercise_name"] is None
    assert goal["deadline"] is None
    assert goal["target"] == 4
    assert goal["status"] == "active"
    assert goal["progress"]["current"] == 0


def test_ac1_the_target_keeps_full_precision(client, library, signed_in):
    goal = create(client, signed_in["headers"], strength(target=102.05828325))
    assert goal["target"] == 102.05828325
    assert listed(client, signed_in["headers"])[0]["target"] == 102.05828325


def test_ac1_the_created_goal_is_listed(client, library, signed_in):
    goal = create(client, signed_in["headers"], strength())
    assert [g["id"] for g in listed(client, signed_in["headers"])] == [goal["id"]]


def test_ac1_same_id_again_is_200_with_the_stored_goal_and_nothing_changes(client, library, signed_in):
    body = strength()
    first = create(client, signed_in["headers"], body)
    again = post(client, signed_in["headers"], body)
    assert again.status_code == 200
    assert again.get_json() == first
    assert len(listed(client, signed_in["headers"])) == 1


def test_ac1_same_id_with_a_different_body_returns_the_stored_goal(client, library, signed_in):
    body = strength(target=100.0)
    create(client, signed_in["headers"], body)
    again = post(client, signed_in["headers"], {**body, "target": 150.0, "deadline": None})
    assert again.status_code == 200
    assert again.get_json()["target"] == 100.0
    assert again.get_json()["deadline"] == "2026-12-15"
    assert listed(client, signed_in["headers"])[0]["target"] == 100.0


def test_ac1_a_retry_at_the_limit_is_200_not_409(client, library, signed_in):
    first = strength()
    create(client, signed_in["headers"], first)
    create(client, signed_in["headers"], strength())
    create(client, signed_in["headers"], strength())
    assert post(client, signed_in["headers"], first).status_code == 200


def test_ac1_the_same_id_for_another_user_is_a_new_goal(client, library, signed_in, other_user):
    body = strength()
    create(client, signed_in["headers"], body)
    assert post(client, other_user["headers"], body).status_code == 201
    assert len(listed(client, signed_in["headers"])) == 1
    assert len(listed(client, other_user["headers"])) == 1


def test_ac1_a_deadline_is_optional(client, library, signed_in):
    body = strength()
    del body["deadline"]
    assert create(client, signed_in["headers"], body)["deadline"] is None


# --- AC-2: bad input ------------------------------------------------------------------------

BAD_BODIES = {
    "id_not_a_uuid": strength(id="nope"),
    "id_uppercase": strength(id="7B1E4C2A-9D3F-4E8A-B5C6-1A2B3C4D5E6F"),
    "id_null": strength(id=None),
    "type_unknown": strength(type="volume"),
    "type_null": strength(type=None),
    "exercise_unknown": strength(exercise_id="no_such_exercise"),
    "exercise_null": strength(exercise_id=None),
    "exercise_bodyweight": strength(exercise_id="push_up"),
    "exercise_timed": strength(exercise_id="plank"),
    "strength_target_zero": strength(target=0),
    "strength_target_negative": strength(target=-1),
    "strength_target_string": strength(target="100"),
    "strength_target_null": strength(target=None),
    "strength_target_over_max": strength(target=1500.5),
    "frequency_target_zero": frequency(target=0),
    "frequency_target_eight": frequency(target=8),
    "frequency_target_fraction": frequency(target=2.5),
    "frequency_target_string": frequency(target="3"),
    "frequency_with_exercise": frequency(exercise_id=BENCH),
    "frequency_with_deadline": frequency(deadline="2026-12-15"),
    "start_not_a_date": strength(start_date="Oct 20"),
    "start_null": strength(start_date=None),
    "deadline_not_a_date": strength(deadline="soon"),
    "deadline_before_start": strength(deadline="2026-10-19"),
    "deadline_over_five_years": strength(deadline="2031-10-21"),
}


@pytest.mark.parametrize("body", BAD_BODIES.values(), ids=BAD_BODIES.keys())
def test_ac2_bad_body_is_400_and_saves_nothing(client, library, signed_in, body):
    response = post(client, signed_in["headers"], body)
    assert response.status_code == 400
    assert error_of(response)["code"] == "bad_request"
    assert listed(client, signed_in["headers"]) == []


@pytest.mark.parametrize("field", ["id", "type", "start_date", "target"])
def test_ac2_missing_required_field_is_400(client, library, signed_in, field):
    body = strength()
    del body[field]
    response = post(client, signed_in["headers"], body)
    assert response.status_code == 400
    assert error_of(response)["code"] == "bad_request"
    assert listed(client, signed_in["headers"]) == []


@pytest.mark.parametrize("raw", ['{"id": "7b1e4c2a-9d3f-4e8a-b5c6-1a2b3c4d5e6f", "type": "strength", '
                                 '"exercise_id": "barbell_bench_press", "start_date": "2026-10-20", "target": NaN}',
                                 '{"id": "7b1e4c2a-9d3f-4e8a-b5c6-1a2b3c4d5e6f", "type": "strength", '
                                 '"exercise_id": "barbell_bench_press", "start_date": "2026-10-20", "target": Infinity}'])
def test_ac2_nan_and_infinity_are_400(client, library, signed_in, raw):
    response = client.post(GOALS, data=raw, content_type="application/json", headers=signed_in["headers"])
    assert response.status_code == 400
    assert error_of(response)["code"] == "bad_request"
    assert listed(client, signed_in["headers"]) == []


def test_ac2_a_body_that_is_not_an_object_is_400(client, library, signed_in):
    response = client.post(GOALS, json=[strength()], headers=signed_in["headers"])
    assert response.status_code == 400
    assert error_of(response)["code"] == "bad_request"


@pytest.mark.parametrize("changes", [{"target": 1500}, {"target": 0.5}, {"deadline": "2026-10-20"}])
def test_ac2_boundaries_that_are_allowed(client, library, signed_in, changes):
    assert post(client, signed_in["headers"], strength(**changes)).status_code == 201


@pytest.mark.parametrize("target", [1, 7])
def test_ac2_frequency_boundaries_that_are_allowed(client, library, signed_in, target):
    assert post(client, signed_in["headers"], frequency(target=target)).status_code == 201


# --- AC-3: the limit ------------------------------------------------------------------------

def test_ac3_a_fourth_active_goal_is_409_and_saves_nothing(client, library, signed_in):
    for _ in range(3):
        create(client, signed_in["headers"], strength())
    response = post(client, signed_in["headers"], strength())
    assert response.status_code == 409
    assert error_of(response)["code"] == "conflict"
    assert len(listed(client, signed_in["headers"])) == 3


def test_ac3_a_frequency_goal_counts(client, library, signed_in):
    create(client, signed_in["headers"], frequency())
    create(client, signed_in["headers"], strength())
    create(client, signed_in["headers"], strength())
    assert post(client, signed_in["headers"], strength()).status_code == 409


def test_ac3_completed_goals_do_not_count(client, library, signed_in):
    save_workout(client, signed_in["headers"], "2026-10-28", [(BENCH, "working", 100.0, 5)])
    for _ in range(3):
        goal = create(client, signed_in["headers"], strength(target=100.0))
        assert goal["status"] == "completed"
    for _ in range(3):
        assert post(client, signed_in["headers"], strength(target=900.0)).status_code == 201
    assert post(client, signed_in["headers"], strength(target=900.0)).status_code == 409


def test_ac3_another_users_goals_do_not_count(client, library, signed_in, other_user):
    for _ in range(3):
        create(client, other_user["headers"], strength())
    assert post(client, signed_in["headers"], strength()).status_code == 201


def test_ac3_a_second_frequency_goal_is_409(client, library, signed_in):
    create(client, signed_in["headers"], frequency())
    response = post(client, signed_in["headers"], frequency(target=2))
    assert response.status_code == 409
    assert error_of(response)["code"] == "conflict"
    assert len(listed(client, signed_in["headers"])) == 1


def test_ac3_a_deleted_goal_frees_a_slot(client, library, signed_in):
    goals = [create(client, signed_in["headers"], strength()) for _ in range(3)]
    assert client.delete(f"{GOALS}/{goals[0]['id']}", headers=signed_in["headers"]).status_code == 204
    assert post(client, signed_in["headers"], strength()).status_code == 201


def test_ac3_raising_a_completed_goal_with_three_active_is_409(client, library, signed_in):
    save_workout(client, signed_in["headers"], "2026-10-28", [(BENCH, "working", 100.0, 5)])
    done = create(client, signed_in["headers"], strength(target=100.0))
    assert done["status"] == "completed"
    for _ in range(3):
        create(client, signed_in["headers"], strength(exercise_id="deadlift", target=900.0))
    response = client.put(f"{GOALS}/{done['id']}", json={"target": 500.0}, headers=signed_in["headers"])
    assert response.status_code == 409
    assert error_of(response)["code"] == "conflict"
    stored = next(g for g in listed(client, signed_in["headers"]) if g["id"] == done["id"])
    assert stored["target"] == 100.0
    assert stored["status"] == "completed"


# --- AC-4: list -----------------------------------------------------------------------------

def test_ac4_a_new_user_gets_an_empty_wrapped_list(client, library, signed_in):
    response = client.get(GOALS, headers=signed_in["headers"])
    assert response.status_code == 200
    assert response.get_json() == {"goals": []}


def test_ac4_only_this_users_goals(client, library, signed_in, other_user):
    mine = create(client, signed_in["headers"], strength())
    create(client, other_user["headers"], frequency())
    assert [g["id"] for g in listed(client, signed_in["headers"])] == [mine["id"]]
    assert [g["type"] for g in listed(client, other_user["headers"])] == ["frequency"]


def test_ac4_items_have_the_api_md_shape_and_a_status(client, library, signed_in):
    create(client, signed_in["headers"], strength())
    create(client, signed_in["headers"], frequency())
    goals = listed(client, signed_in["headers"])
    assert len(goals) == 2
    for goal in goals:
        assert set(goal) == GOAL_KEYS
        assert set(goal["progress"]) == PROGRESS_KEYS
        assert goal["status"] in ("active", "completed")


def test_ac4_active_goals_are_oldest_created_first(client, library, signed_in):
    first = create(client, signed_in["headers"], strength(id="ffffffff-0000-4000-8000-000000000000"))
    second = create(client, signed_in["headers"], strength(id="00000000-0000-4000-8000-000000000000"))
    third = create(client, signed_in["headers"], frequency())
    assert [g["id"] for g in listed(client, signed_in["headers"])] == [first["id"], second["id"], third["id"]]


def test_ac4_completed_goals_come_after_active_ones(client, library, signed_in):
    save_workout(client, signed_in["headers"], "2026-10-28", [(BENCH, "working", 100.0, 5)])
    done = create(client, signed_in["headers"], strength(target=100.0))
    active = create(client, signed_in["headers"], strength(exercise_id="deadlift", target=900.0))
    assert [g["id"] for g in listed(client, signed_in["headers"])] == [active["id"], done["id"]]


def test_ac4_a_bad_today_is_400(client, library, signed_in):
    response = client.get(f"{GOALS}?today=not-a-date", headers=signed_in["headers"])
    assert response.status_code == 400
    assert error_of(response)["code"] == "bad_request"


def test_ac4_today_may_be_left_out(client, library, signed_in):
    create(client, signed_in["headers"], frequency())
    response = client.get(GOALS, headers=signed_in["headers"])
    assert response.status_code == 200
    assert response.get_json()["goals"][0]["progress"]["week_start"] is not None


# --- AC-5 and AC-6: strength progress, end to end -------------------------------------------

def test_ac5_current_is_the_best_epley_over_eligible_sets(client, library, signed_in):
    save_workout(client, signed_in["headers"], "2026-10-25", [
        (BENCH, "working", 70.0, 5),       # 81.67
        (BENCH, "failure", 60.0, 10),      # 80.0
        (BENCH, "warmup", 200.0, 5),       # ignored
        (BENCH, "dropset", 200.0, 5),      # ignored
        (BENCH, "working", 200.0, 11),     # ignored: 11 reps
        (BENCH, "working", 0, 5),          # ignored: no external weight
    ])
    create(client, signed_in["headers"], strength(target=100.0))
    progress = listed(client, signed_in["headers"])[0]["progress"]
    assert progress["current"] == pytest.approx(70 * (1 + 5 / 30))
    assert progress["percent"] == pytest.approx(70 * (1 + 5 / 30))
    assert progress["remaining"] == pytest.approx(100 - 70 * (1 + 5 / 30))
    assert listed(client, signed_in["headers"])[0]["status"] == "active"


def test_ac5_sets_from_before_start_date_and_other_exercises(client, library, signed_in):
    save_workout(client, signed_in["headers"], "2026-01-10", [(BENCH, "working", 80.0, 3), ("deadlift", "working", 300.0, 3)])
    create(client, signed_in["headers"], strength(target=100.0, start_date="2026-10-20"))
    assert listed(client, signed_in["headers"])[0]["progress"]["current"] == pytest.approx(80 * (1 + 3 / 30))


def test_ac5_no_eligible_set_gives_null_progress(client, library, signed_in):
    save_workout(client, signed_in["headers"], "2026-10-25", [(BENCH, "warmup", 60.0, 5)])
    create(client, signed_in["headers"], strength(target=100.0))
    goal = listed(client, signed_in["headers"])[0]
    assert goal["status"] == "active"
    assert goal["progress"]["current"] is None
    assert goal["progress"]["percent"] is None
    assert goal["progress"]["remaining"] is None


def test_ac5_other_users_sets_do_not_count(client, library, signed_in, other_user):
    save_workout(client, other_user["headers"], "2026-10-25", [(BENCH, "working", 150.0, 5)])
    create(client, signed_in["headers"], strength(target=100.0))
    assert listed(client, signed_in["headers"])[0]["progress"]["current"] is None


def test_ac6_reaching_the_target_completes_the_goal(client, library, signed_in):
    save_workout(client, signed_in["headers"], "2026-10-28", [(BENCH, "working", 100.0, 5)])
    goal = create(client, signed_in["headers"], strength(target=100.0))
    assert goal["status"] == "completed"
    assert goal["progress"]["percent"] == 100
    assert goal["progress"]["remaining"] == 0
    assert goal["progress"]["achieved_on"] == "2026-10-28"
    assert goal["progress"]["current"] == pytest.approx(100 * (1 + 5 / 30))


def test_ac6_achieved_on_is_the_first_workout_that_reached_it(client, library, signed_in):
    save_workout(client, signed_in["headers"], "2026-11-03", [(BENCH, "working", 120.0, 5)])
    save_workout(client, signed_in["headers"], "2026-10-28", [(BENCH, "working", 100.0, 5)])
    goal = create(client, signed_in["headers"], strength(target=100.0))
    assert goal["progress"]["achieved_on"] == "2026-10-28"


def test_ac6_a_new_workout_completes_an_active_goal_on_the_next_load(client, library, signed_in):
    create(client, signed_in["headers"], strength(target=100.0))
    assert listed(client, signed_in["headers"])[0]["status"] == "active"
    save_workout(client, signed_in["headers"], "2026-11-03", [(BENCH, "working", 100.0, 5)])
    goal = listed(client, signed_in["headers"])[0]
    assert goal["status"] == "completed"
    assert goal["progress"]["achieved_on"] == "2026-11-03"


def test_ac6_raising_the_target_makes_it_active_again(client, library, signed_in):
    save_workout(client, signed_in["headers"], "2026-10-28", [(BENCH, "working", 100.0, 5)])
    goal = create(client, signed_in["headers"], strength(target=100.0))
    response = client.put(f"{GOALS}/{goal['id']}", json={"target": 130.0}, headers=signed_in["headers"])
    assert response.status_code == 200
    assert response.get_json()["status"] == "active"
    assert response.get_json()["progress"]["achieved_on"] is None
    assert listed(client, signed_in["headers"])[0]["status"] == "active"


# --- AC-7: frequency progress, end to end ---------------------------------------------------

def test_ac7_counts_this_weeks_workouts_once_each(client, library, signed_in):
    save_workout(client, signed_in["headers"], "2026-11-02", [(BENCH, "working", 60.0, 5)] * 5)
    save_workout(client, signed_in["headers"], "2026-11-02")
    save_workout(client, signed_in["headers"], "2026-11-04")
    create(client, signed_in["headers"], frequency(target=4))
    progress = listed(client, signed_in["headers"])[0]["progress"]
    assert progress["current"] == 3
    assert progress["percent"] == pytest.approx(75.0)
    assert progress["remaining"] == 1
    assert progress["met_this_week"] is False
    assert progress["week_start"] == "2026-11-02"


def test_ac7_the_week_runs_monday_to_sunday(client, library, signed_in):
    for local_date in ["2026-11-01", "2026-11-02", "2026-11-08", "2026-11-09"]:
        save_workout(client, signed_in["headers"], local_date)
    create(client, signed_in["headers"], frequency(target=4))
    assert listed(client, signed_in["headers"], today="2026-11-04")[0]["progress"]["current"] == 2
    assert listed(client, signed_in["headers"], today="2026-11-09")[0]["progress"]["current"] == 1
    assert listed(client, signed_in["headers"], today="2026-11-09")[0]["progress"]["week_start"] == "2026-11-09"


def test_ac7_meeting_the_target_is_met_and_capped(client, library, signed_in):
    for local_date in ["2026-11-02", "2026-11-03", "2026-11-04"]:
        save_workout(client, signed_in["headers"], local_date)
    create(client, signed_in["headers"], frequency(target=2))
    goal = listed(client, signed_in["headers"])[0]
    assert goal["status"] == "active"
    assert goal["progress"]["current"] == 3
    assert goal["progress"]["percent"] == 100
    assert goal["progress"]["remaining"] == 0
    assert goal["progress"]["met_this_week"] is True


def test_ac7_a_week_without_workouts_is_zero(client, library, signed_in):
    create(client, signed_in["headers"], frequency(target=3))
    progress = listed(client, signed_in["headers"])[0]["progress"]
    assert progress["current"] == 0
    assert progress["percent"] == 0
    assert progress["remaining"] == 3
    assert progress["met_this_week"] is False


def test_ac7_other_users_workouts_do_not_count(client, library, signed_in, other_user):
    save_workout(client, other_user["headers"], "2026-11-03")
    create(client, signed_in["headers"], frequency(target=3))
    assert listed(client, signed_in["headers"])[0]["progress"]["current"] == 0


# --- AC-8: update ---------------------------------------------------------------------------

def put(client, headers, goal_id, body):
    return client.put(f"{GOALS}/{goal_id}", json=body, headers=headers)


def test_ac8_changes_target_and_deadline_and_returns_the_full_goal(client, library, signed_in):
    goal = create(client, signed_in["headers"], strength())
    response = put(client, signed_in["headers"], goal["id"],
                   {"id": goal["id"], "type": "strength", "exercise_id": BENCH,
                    "target": 102.05828325, "start_date": "2026-10-20", "deadline": "2027-01-31"})
    assert response.status_code == 200
    updated = response.get_json()
    assert set(updated) == GOAL_KEYS
    assert updated["target"] == 102.05828325
    assert updated["deadline"] == "2027-01-31"
    stored = listed(client, signed_in["headers"])[0]
    assert stored["target"] == 102.05828325
    assert stored["deadline"] == "2027-01-31"


def test_ac8_the_deadline_can_be_cleared(client, library, signed_in):
    goal = create(client, signed_in["headers"], strength())
    response = put(client, signed_in["headers"], goal["id"], {"target": 100.0, "deadline": None})
    assert response.status_code == 200
    assert response.get_json()["deadline"] is None


def test_ac8_other_fields_are_ignored(client, library, signed_in):
    goal = create(client, signed_in["headers"], strength())
    response = put(client, signed_in["headers"], goal["id"], {
        "id": new_id(), "type": "frequency", "exercise_id": "deadlift", "start_date": "2026-01-01",
        "target": 110.0, "deadline": "2026-12-15"})
    assert response.status_code == 200
    updated = response.get_json()
    assert updated["id"] == goal["id"]
    assert updated["type"] == "strength"
    assert updated["exercise_id"] == BENCH
    assert updated["start_date"] == "2026-10-20"
    assert updated["created_at"] == goal["created_at"]
    assert updated["target"] == 110.0
    assert len(listed(client, signed_in["headers"])) == 1


def test_ac8_a_frequency_target_can_change(client, library, signed_in):
    goal = create(client, signed_in["headers"], frequency(target=3))
    response = put(client, signed_in["headers"], goal["id"], {"target": 5})
    assert response.status_code == 200
    assert response.get_json()["target"] == 5


@pytest.mark.parametrize("body", [
    {"target": 0}, {"target": -3}, {"target": "5"}, {"target": 1501},
    {"target": 100.0, "deadline": "whenever"}, {"target": 100.0, "deadline": "2026-10-19"},
    {"target": 100.0, "deadline": "2031-10-21"}])
def test_ac8_invalid_strength_changes_are_400_and_change_nothing(client, library, signed_in, body):
    goal = create(client, signed_in["headers"], strength())
    response = put(client, signed_in["headers"], goal["id"], body)
    assert response.status_code == 400
    assert error_of(response)["code"] == "bad_request"
    assert listed(client, signed_in["headers"])[0] == goal


@pytest.mark.parametrize("target", [0, 8, 2.5])
def test_ac8_invalid_frequency_targets_are_400(client, library, signed_in, target):
    goal = create(client, signed_in["headers"], frequency(target=3))
    response = put(client, signed_in["headers"], goal["id"], {"target": target})
    assert response.status_code == 400
    assert listed(client, signed_in["headers"])[0]["target"] == 3


def test_ac8_an_unknown_id_is_404(client, library, signed_in):
    response = put(client, signed_in["headers"], new_id(), {"target": 100.0})
    assert response.status_code == 404
    assert error_of(response)["code"] == "not_found"


def test_ac8_another_users_goal_is_404_and_untouched(client, library, signed_in, other_user):
    theirs = create(client, other_user["headers"], strength())
    response = put(client, signed_in["headers"], theirs["id"], {"target": 5.0})
    assert response.status_code == 404
    assert error_of(response)["code"] == "not_found"
    assert listed(client, other_user["headers"])[0]["target"] == 100.0


# --- AC-9: delete ---------------------------------------------------------------------------

def test_ac9_delete_is_204_with_no_body_and_the_goal_is_gone(client, library, signed_in):
    goal = create(client, signed_in["headers"], strength())
    response = client.delete(f"{GOALS}/{goal['id']}", headers=signed_in["headers"])
    assert response.status_code == 204
    assert response.data == b""
    assert listed(client, signed_in["headers"]) == []


def test_ac9_deleting_again_or_an_unknown_id_is_still_204(client, library, signed_in):
    goal = create(client, signed_in["headers"], strength())
    assert client.delete(f"{GOALS}/{goal['id']}", headers=signed_in["headers"]).status_code == 204
    assert client.delete(f"{GOALS}/{goal['id']}", headers=signed_in["headers"]).status_code == 204
    assert client.delete(f"{GOALS}/{new_id()}", headers=signed_in["headers"]).status_code == 204


def test_ac9_workouts_and_sets_are_untouched(client, library, signed_in):
    workout_id = save_workout(client, signed_in["headers"], "2026-11-03", [(BENCH, "working", 100.0, 5)])
    goal = create(client, signed_in["headers"], strength(target=100.0))
    client.delete(f"{GOALS}/{goal['id']}", headers=signed_in["headers"])
    response = client.get(f"{WORKOUTS}/{workout_id}", headers=signed_in["headers"])
    assert response.status_code == 200
    assert len(response.get_json()["sets"]) == 1
    assert len(client.get(WORKOUTS, headers=signed_in["headers"]).get_json()["workouts"]) == 1


def test_ac9_another_users_goal_is_never_deleted(client, library, signed_in, other_user):
    theirs = create(client, other_user["headers"], strength())
    assert client.delete(f"{GOALS}/{theirs['id']}", headers=signed_in["headers"]).status_code == 204
    assert [g["id"] for g in listed(client, other_user["headers"])] == [theirs["id"]]


def test_ac9_other_goals_of_the_user_stay(client, library, signed_in):
    keep = create(client, signed_in["headers"], strength())
    drop = create(client, signed_in["headers"], strength())
    client.delete(f"{GOALS}/{drop['id']}", headers=signed_in["headers"])
    assert [g["id"] for g in listed(client, signed_in["headers"])] == [keep["id"]]
