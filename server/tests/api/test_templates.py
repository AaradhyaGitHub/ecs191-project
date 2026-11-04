"""Saved-workout endpoints against the Datastore emulator (specs/saved-workouts.llm.md, AC-1 to AC-5, AC-7).

The part of AC-7 that goes through `POST /workouts` is added once #42 is merged.
"""
from __future__ import annotations

import json
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

import models
from services import auth, template_service

pytestmark = pytest.mark.emulator

SEED = Path(__file__).resolve().parents[2] / "seed" / "exercises.json"
URL = "/api/v1/templates"

T0 = datetime(2026, 11, 2, 17, 2, tzinfo=timezone.utc)

TEMPLATE_KEYS = {"id", "name", "focus", "exercises", "last_done_at", "top_muscles"}
EXERCISE_KEYS = {"exercise_id", "target_sets", "target_reps", "rest_s", "superset_group"}


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


def make_body(**changes) -> dict:
    body = {
        "id": new_id(),
        "name": "Push 1",
        "focus": "tricep focus",
        "exercises": [
            {"exercise_id": "barbell_bench_press", "target_sets": 4, "target_reps": 6, "rest_s": 180},
            {"exercise_id": "triceps_pushdown", "target_sets": 3, "target_reps": 12, "rest_s": 90,
             "superset_group": "a"},
            {"exercise_id": "plank", "target_sets": 3, "rest_s": 90, "superset_group": "a"},
        ],
    }
    body.update(changes)
    return body


def bench_only(**changes) -> dict:
    return make_body(exercises=[
        {"exercise_id": "barbell_bench_press", "target_sets": 4, "target_reps": 6, "rest_s": 180}],
        **changes)


def post(client, headers, body):
    return client.post(URL, json=body, headers=headers)


def listed(client, headers) -> list[dict]:
    response = client.get(URL, headers=headers)
    assert response.status_code == 200
    return response.get_json()["templates"]


def create(client, headers, **changes) -> dict:
    response = post(client, headers, make_body(**changes))
    assert response.status_code == 201
    return response.get_json()


# --- AC-1: sign-in and the list -------------------------------------------------------------

@pytest.mark.parametrize("method,path", [
    ("get", URL), ("post", URL), ("put", f"{URL}/{uuid.uuid4()}"), ("delete", f"{URL}/{uuid.uuid4()}")])
def test_ac1_no_token_is_401_unauthorized(client, library, method, path):
    kwargs = {"json": make_body()} if method in ("post", "put") else {}
    response = getattr(client, method)(path, **kwargs)
    assert response.status_code == 401
    assert error_of(response)["code"] == "unauthorized"


@pytest.mark.parametrize("method,path", [("get", URL), ("post", URL)])
def test_ac1_unknown_token_is_401_unauthorized(client, library, method, path):
    kwargs = {"json": make_body()} if method == "post" else {}
    response = getattr(client, method)(path, headers={"Authorization": "Bearer nope"}, **kwargs)
    assert response.status_code == 401
    assert error_of(response)["code"] == "unauthorized"


def test_ac1_a_rejected_post_stores_nothing(client, library, signed_in):
    client.post(URL, json=make_body())
    assert listed(client, signed_in["headers"]) == []


def test_ac1_a_new_user_gets_an_empty_wrapped_list(client, library, signed_in):
    response = client.get(URL, headers=signed_in["headers"])
    assert response.status_code == 200
    assert response.get_json() == {"templates": []}


def test_ac1_the_list_is_oldest_created_first(client, library, signed_in):
    ids = [new_id() for _ in range(3)]
    for number, template_id in enumerate(ids):
        create(client, signed_in["headers"], id=template_id, name=f"Day {number}")
    assert [t["id"] for t in listed(client, signed_in["headers"])] == ids


def test_ac1_the_order_is_creation_not_name_or_id(client, library, signed_in):
    first = create(client, signed_in["headers"], id="ffffffff-0000-4000-8000-000000000000", name="Zulu")
    second = create(client, signed_in["headers"], id="00000000-0000-4000-8000-000000000000", name="Alpha")
    assert [t["id"] for t in listed(client, signed_in["headers"])] == [first["id"], second["id"]]


def test_ac1_only_this_users_templates_are_listed(client, library, signed_in, other_user):
    mine = create(client, signed_in["headers"], name="Mine")
    create(client, other_user["headers"], name="Theirs")
    assert [t["id"] for t in listed(client, signed_in["headers"])] == [mine["id"]]
    assert [t["name"] for t in listed(client, other_user["headers"])] == ["Theirs"]


def test_ac1_items_have_the_api_md_shape(client, library, signed_in):
    create(client, signed_in["headers"])
    item = listed(client, signed_in["headers"])[0]
    assert set(item) == TEMPLATE_KEYS
    assert all(set(e) == EXERCISE_KEYS for e in item["exercises"])
    assert all(set(m) == {"muscle_id", "name", "level"} for m in item["top_muscles"])


def test_ac1_exercises_keep_their_order_and_fields(client, library, signed_in):
    create(client, signed_in["headers"])
    exercises = listed(client, signed_in["headers"])[0]["exercises"]
    assert exercises == [
        {"exercise_id": "barbell_bench_press", "target_sets": 4, "target_reps": 6, "rest_s": 180,
         "superset_group": None},
        {"exercise_id": "triceps_pushdown", "target_sets": 3, "target_reps": 12, "rest_s": 90,
         "superset_group": "a"},
        {"exercise_id": "plank", "target_sets": 3, "target_reps": None, "rest_s": 90,
         "superset_group": "a"},
    ]


# --- AC-2: create ---------------------------------------------------------------------------

def test_ac2_a_new_id_is_201_with_the_full_template(client, library, signed_in):
    body = make_body()
    response = post(client, signed_in["headers"], body)
    assert response.status_code == 201
    template = response.get_json()
    assert set(template) == TEMPLATE_KEYS
    assert template["id"] == body["id"]
    assert template["name"] == "Push 1"
    assert template["focus"] == "tricep focus"
    assert len(template["exercises"]) == 3
    assert template["last_done_at"] is None


def test_ac2_top_muscles_are_computed(client, library, signed_in):
    template = create(client, signed_in["headers"], **bench_only())
    assert [(m["muscle_id"], m["name"], m["level"]) for m in template["top_muscles"]] == [
        ("chest", "Chest", 4), ("delts", "Delts", 2), ("triceps", "Triceps", 2)]


def test_ac2_top_muscles_are_at_most_three_and_start_at_level_four(client, library, signed_in):
    template = create(client, signed_in["headers"])
    assert 1 <= len(template["top_muscles"]) <= 3
    assert template["top_muscles"][0]["level"] == 4


def test_ac2_name_and_focus_are_trimmed_and_empty_focus_is_null(client, library, signed_in):
    template = create(client, signed_in["headers"], name="  Pull 1 ", focus="   ")
    assert template["name"] == "Pull 1"
    assert template["focus"] is None


def test_ac2_the_created_template_is_listed(client, library, signed_in):
    template = create(client, signed_in["headers"])
    assert listed(client, signed_in["headers"]) == [template]


def test_ac2_the_same_id_again_is_200_with_the_stored_template(client, library, signed_in):
    body = make_body()
    first = post(client, signed_in["headers"], body)
    second = post(client, signed_in["headers"], body)
    assert first.status_code == 201
    assert second.status_code == 200
    assert second.get_json() == first.get_json()


def test_ac2_a_repeat_with_a_different_body_changes_nothing(client, library, signed_in):
    body = make_body()
    first = post(client, signed_in["headers"], body).get_json()
    again = post(client, signed_in["headers"], {**body, "name": "Changed", "focus": "other"})
    assert again.status_code == 200
    assert again.get_json() == first
    assert listed(client, signed_in["headers"]) == [first]


def test_ac2_a_repeat_keeps_the_order_of_the_list(client, library, signed_in):
    first = make_body(name="First")
    post(client, signed_in["headers"], first)
    create(client, signed_in["headers"], name="Second")
    post(client, signed_in["headers"], first)
    assert [t["name"] for t in listed(client, signed_in["headers"])] == ["First", "Second"]


def test_ac2_a_repeat_keeps_last_done_at(client, library, signed_in):
    body = make_body()
    post(client, signed_in["headers"], body)
    template_service.record_done(signed_in["user_id"], body["id"], T0)
    again = post(client, signed_in["headers"], body)
    assert again.status_code == 200
    assert again.get_json()["last_done_at"] == "2026-11-02T17:02:00Z"


def test_ac2_two_users_may_use_the_same_id_without_clashing(client, library, signed_in, other_user):
    body = make_body()
    assert post(client, signed_in["headers"], body).status_code == 201
    assert post(client, other_user["headers"], {**body, "name": "Theirs"}).status_code == 201
    assert listed(client, signed_in["headers"])[0]["name"] == "Push 1"


def test_ac2_names_may_repeat(client, library, signed_in):
    create(client, signed_in["headers"], name="Same")
    create(client, signed_in["headers"], name="Same")
    assert len(listed(client, signed_in["headers"])) == 2


def test_ac2_the_service_says_whether_it_created(library, signed_in):
    body = make_body()
    template, created = template_service.create_template(signed_in["user_id"], body)
    again, created_again = template_service.create_template(signed_in["user_id"], body)
    assert (created, created_again) == (True, False)
    assert again == template


# --- AC-3: bad input ------------------------------------------------------------------------

def bad_exercise(**changes) -> dict:
    row = {"exercise_id": "barbell_bench_press", "target_sets": 4, "target_reps": 6, "rest_s": 180}
    row.update(changes)
    return {"exercises": [row]}


BAD_BODIES = {
    "uppercase id": {"id": "3C9D7E1A-5B2F-4C8D-A6E4-7F8A9B0C1D2E"},
    "id not a uuid": {"id": "push-1"},
    "blank name": {"name": "   "},
    "name over 60": {"name": "x" * 61},
    "focus over 60": {"focus": "f" * 61},
    "no exercises": {"exercises": []},
    "31 exercises": {"exercises": [bad_exercise()["exercises"][0]] * 31},
    "unknown exercise": bad_exercise(exercise_id="no_such_exercise"),
    "sets 0": bad_exercise(target_sets=0),
    "sets 21": bad_exercise(target_sets=21),
    "reps 0": bad_exercise(target_reps=0),
    "reps 101": bad_exercise(target_reps=101),
    "rest -1": bad_exercise(rest_s=-1),
    "rest 601": bad_exercise(rest_s=601),
}


@pytest.mark.parametrize("changes", BAD_BODIES.values(), ids=BAD_BODIES.keys())
def test_ac3_post_rejects_bad_bodies_and_stores_nothing(client, library, signed_in, changes):
    response = post(client, signed_in["headers"], make_body(**changes))
    assert response.status_code == 400
    assert error_of(response)["code"] == "bad_request"
    assert listed(client, signed_in["headers"]) == []


@pytest.mark.parametrize("changes", [c for k, c in BAD_BODIES.items() if k not in ("uppercase id", "id not a uuid")],
                         ids=[k for k in BAD_BODIES if k not in ("uppercase id", "id not a uuid")])
def test_ac3_put_rejects_bad_bodies_and_changes_nothing(client, library, signed_in, changes):
    original = create(client, signed_in["headers"])
    response = client.put(f"{URL}/{original['id']}", json=make_body(id=original["id"], **changes),
                          headers=signed_in["headers"])
    assert response.status_code == 400
    assert error_of(response)["code"] == "bad_request"
    assert listed(client, signed_in["headers"]) == [original]


def test_ac3_a_missing_name_is_400(client, library, signed_in):
    body = make_body()
    del body["name"]
    assert post(client, signed_in["headers"], body).status_code == 400


def test_ac3_a_body_that_is_not_an_object_is_400(client, library, signed_in):
    response = client.post(URL, json=[1, 2], headers=signed_in["headers"])
    assert response.status_code == 400
    assert error_of(response)["code"] == "bad_request"


def test_ac3_a_body_that_is_not_json_is_400(client, library, signed_in):
    response = client.post(URL, data="not json", content_type="text/plain", headers=signed_in["headers"])
    assert response.status_code == 400
    assert error_of(response)["code"] == "bad_request"


@pytest.mark.parametrize("changes", [
    {"name": "x"}, {"name": "x" * 60}, {"focus": "f" * 60},
    bad_exercise(target_sets=1, target_reps=1, rest_s=0),
    bad_exercise(target_sets=20, target_reps=100, rest_s=600),
    bad_exercise(target_reps=None),
    {"exercises": [bad_exercise()["exercises"][0]] * 30},
], ids=["name 1", "name 60", "focus 60", "lower limits", "upper limits", "null reps", "30 exercises"])
def test_ac3_values_at_the_limits_are_accepted(client, library, signed_in, changes):
    response = post(client, signed_in["headers"], make_body(**changes))
    assert response.status_code == 201


def test_ac3_a_left_out_target_reps_comes_back_null(client, library, signed_in):
    template = create(client, signed_in["headers"])
    assert template["exercises"][2]["target_reps"] is None


# --- AC-4: update ---------------------------------------------------------------------------

def test_ac4_put_replaces_name_focus_and_exercises(client, library, signed_in):
    original = create(client, signed_in["headers"])
    new_body = {"id": original["id"], "name": "Pull 1", "focus": "back",
                "exercises": [{"exercise_id": "deadlift", "target_sets": 3, "target_reps": 5, "rest_s": 240}]}
    response = client.put(f"{URL}/{original['id']}", json=new_body, headers=signed_in["headers"])
    assert response.status_code == 200
    template = response.get_json()
    assert set(template) == TEMPLATE_KEYS
    assert template["id"] == original["id"]
    assert template["name"] == "Pull 1"
    assert template["focus"] == "back"
    assert template["exercises"] == [{"exercise_id": "deadlift", "target_sets": 3, "target_reps": 5,
                                      "rest_s": 240, "superset_group": None}]
    assert listed(client, signed_in["headers"]) == [template]


def test_ac4_put_recomputes_top_muscles(client, library, signed_in):
    original = create(client, signed_in["headers"], **bench_only())
    new_body = make_body(id=original["id"], exercises=[
        {"exercise_id": "deadlift", "target_sets": 4, "target_reps": 5, "rest_s": 240}])
    template = client.put(f"{URL}/{original['id']}", json=new_body, headers=signed_in["headers"]).get_json()
    assert template["top_muscles"] != original["top_muscles"]
    assert template["top_muscles"][0]["level"] == 4


def test_ac4_put_keeps_last_done_at(client, library, signed_in):
    original = create(client, signed_in["headers"])
    template_service.record_done(signed_in["user_id"], original["id"], T0)
    response = client.put(f"{URL}/{original['id']}", json=make_body(id=original["id"], name="Renamed"),
                          headers=signed_in["headers"])
    assert response.status_code == 200
    assert response.get_json()["last_done_at"] == "2026-11-02T17:02:00Z"
    assert response.get_json()["name"] == "Renamed"


def test_ac4_put_keeps_the_place_in_the_list(client, library, signed_in):
    first = create(client, signed_in["headers"], name="First")
    create(client, signed_in["headers"], name="Second")
    client.put(f"{URL}/{first['id']}", json=make_body(id=first["id"], name="First, renamed"),
               headers=signed_in["headers"])
    assert [t["name"] for t in listed(client, signed_in["headers"])] == ["First, renamed", "Second"]


def test_ac4_put_clears_focus_when_it_is_empty(client, library, signed_in):
    original = create(client, signed_in["headers"])
    response = client.put(f"{URL}/{original['id']}", json=make_body(id=original["id"], focus=""),
                          headers=signed_in["headers"])
    assert response.get_json()["focus"] is None


def test_ac4_an_unknown_id_is_404_not_found(client, library, signed_in):
    missing = new_id()
    response = client.put(f"{URL}/{missing}", json=make_body(id=missing), headers=signed_in["headers"])
    assert response.status_code == 404
    assert error_of(response)["code"] == "not_found"
    assert listed(client, signed_in["headers"]) == []


def test_ac4_another_users_id_is_404_and_changes_nothing(client, library, signed_in, other_user):
    theirs = create(client, other_user["headers"], name="Theirs")
    response = client.put(f"{URL}/{theirs['id']}", json=make_body(id=theirs["id"], name="Hijacked"),
                          headers=signed_in["headers"])
    assert response.status_code == 404
    assert error_of(response)["code"] == "not_found"
    assert listed(client, other_user["headers"]) == [theirs]
    assert listed(client, signed_in["headers"]) == []


def test_ac4_the_service_raises_not_found(library, signed_in):
    from services.errors import ApiError

    missing = new_id()
    with pytest.raises(ApiError) as caught:
        template_service.update_template(signed_in["user_id"], missing, make_body(id=missing))
    assert caught.value.code == "not_found"


# --- AC-5: delete ---------------------------------------------------------------------------

def test_ac5_delete_is_204_with_no_body(client, library, signed_in):
    template = create(client, signed_in["headers"])
    response = client.delete(f"{URL}/{template['id']}", headers=signed_in["headers"])
    assert response.status_code == 204
    assert response.get_data() == b""


def test_ac5_a_deleted_template_is_not_listed(client, library, signed_in):
    keep = create(client, signed_in["headers"], name="Keep")
    gone = create(client, signed_in["headers"], name="Gone")
    client.delete(f"{URL}/{gone['id']}", headers=signed_in["headers"])
    assert listed(client, signed_in["headers"]) == [keep]


def test_ac5_deleting_twice_is_204_both_times(client, library, signed_in):
    template = create(client, signed_in["headers"])
    assert client.delete(f"{URL}/{template['id']}", headers=signed_in["headers"]).status_code == 204
    assert client.delete(f"{URL}/{template['id']}", headers=signed_in["headers"]).status_code == 204


def test_ac5_an_unknown_id_is_204(client, library, signed_in):
    response = client.delete(f"{URL}/{new_id()}", headers=signed_in["headers"])
    assert response.status_code == 204
    assert response.get_data() == b""


def test_ac5_another_users_template_is_not_deleted(client, library, signed_in, other_user):
    theirs = create(client, other_user["headers"])
    client.delete(f"{URL}/{theirs['id']}", headers=signed_in["headers"])
    assert listed(client, other_user["headers"]) == [theirs]


def test_ac5_after_delete_the_same_id_can_be_created_again(client, library, signed_in):
    body = make_body()
    post(client, signed_in["headers"], body)
    client.delete(f"{URL}/{body['id']}", headers=signed_in["headers"])
    assert post(client, signed_in["headers"], body).status_code == 201


def test_ac5_put_after_delete_is_404(client, library, signed_in):
    template = create(client, signed_in["headers"])
    client.delete(f"{URL}/{template['id']}", headers=signed_in["headers"])
    response = client.put(f"{URL}/{template['id']}", json=make_body(id=template["id"]),
                          headers=signed_in["headers"])
    assert response.status_code == 404


# --- AC-7: record_done ----------------------------------------------------------------------

def last_done(client, headers, template_id):
    return next(t for t in listed(client, headers) if t["id"] == template_id)["last_done_at"]


def test_ac7_record_done_sets_an_empty_last_done(client, library, signed_in):
    template = create(client, signed_in["headers"])
    template_service.record_done(signed_in["user_id"], template["id"], T0)
    assert last_done(client, signed_in["headers"], template["id"]) == "2026-11-02T17:02:00Z"


def test_ac7_record_done_moves_an_older_last_done_forward(client, library, signed_in):
    template = create(client, signed_in["headers"])
    template_service.record_done(signed_in["user_id"], template["id"], T0 - timedelta(days=3))
    template_service.record_done(signed_in["user_id"], template["id"], T0)
    assert last_done(client, signed_in["headers"], template["id"]) == "2026-11-02T17:02:00Z"


def test_ac7_an_older_done_at_changes_nothing(client, library, signed_in):
    template = create(client, signed_in["headers"])
    template_service.record_done(signed_in["user_id"], template["id"], T0)
    template_service.record_done(signed_in["user_id"], template["id"], T0 - timedelta(days=1))
    assert last_done(client, signed_in["headers"], template["id"]) == "2026-11-02T17:02:00Z"


def test_ac7_the_same_done_at_twice_is_the_same_as_once(client, library, signed_in):
    template = create(client, signed_in["headers"])
    template_service.record_done(signed_in["user_id"], template["id"], T0)
    once = listed(client, signed_in["headers"])
    template_service.record_done(signed_in["user_id"], template["id"], T0)
    assert listed(client, signed_in["headers"]) == once
    assert once[0]["last_done_at"] == "2026-11-02T17:02:00Z"


def test_ac7_a_missing_template_is_no_error_and_creates_nothing(client, library, signed_in):
    template_service.record_done(signed_in["user_id"], new_id(), T0)
    assert listed(client, signed_in["headers"]) == []


def test_ac7_record_done_does_not_touch_other_fields(client, library, signed_in):
    template = create(client, signed_in["headers"])
    template_service.record_done(signed_in["user_id"], template["id"], T0)
    done = listed(client, signed_in["headers"])[0]
    assert {k: v for k, v in done.items() if k != "last_done_at"} == \
           {k: v for k, v in template.items() if k != "last_done_at"}


def test_ac7_record_done_for_another_user_does_not_touch_mine(client, library, signed_in, other_user):
    mine = create(client, signed_in["headers"])
    template_service.record_done(other_user["user_id"], mine["id"], T0)
    assert last_done(client, signed_in["headers"], mine["id"]) is None


def test_ac7_record_done_only_changes_the_named_template(client, library, signed_in):
    one = create(client, signed_in["headers"], name="One")
    two = create(client, signed_in["headers"], name="Two")
    template_service.record_done(signed_in["user_id"], one["id"], T0)
    assert last_done(client, signed_in["headers"], one["id"]) == "2026-11-02T17:02:00Z"
    assert last_done(client, signed_in["headers"], two["id"]) is None
