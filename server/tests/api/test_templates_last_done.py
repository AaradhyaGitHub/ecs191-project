"""AC-7, the `POST /workouts` part (specs/saved-workouts.llm.md, API.md "Last done for a saved workout").

After `POST /workouts` with a `template_id`, `GET /templates` shows the workout's `started_at` as
`last_done_at`. It only moves forward, a repeat is safe, and an unknown or deleted `template_id`
never makes `POST /workouts` fail.
"""
from __future__ import annotations

import copy
import json
import uuid
from pathlib import Path

import pytest

import models

pytestmark = pytest.mark.emulator

ROOT = Path(__file__).resolve().parents[3]
SEED = ROOT / "server" / "seed" / "exercises.json"
WORKOUT_FIXTURE = ROOT / "shared" / "fixtures" / "workout_post.json"
TEMPLATES = "/api/v1/templates"
WORKOUTS = "/api/v1/workouts"

DAY1 = "2026-11-01T17:02:00Z"
DAY2 = "2026-11-02T17:02:00Z"
DAY3 = "2026-11-03T17:02:00Z"


@pytest.fixture
def library(emulator):
    data = json.loads(SEED.read_text())
    seed = data["exercises"] if isinstance(data, dict) else data
    models.put_exercises(seed)
    return seed


def new_id() -> str:
    return str(uuid.uuid4())


def template_body(template_id: str | None = None) -> dict:
    return {
        "id": template_id or new_id(),
        "name": "Push 1",
        "focus": None,
        "exercises": [{"exercise_id": "barbell_bench_press", "target_sets": 4, "target_reps": 6, "rest_s": 180}],
    }


def workout_body(template_id, started_at: str, workout_id: str | None = None) -> dict:
    """The contract fixture, with fresh ids and the given template and start time."""
    body = copy.deepcopy(json.loads(WORKOUT_FIXTURE.read_text()))
    body["id"] = workout_id or new_id()
    body["template_id"] = template_id
    body["started_at"] = started_at
    body["ended_at"] = started_at.replace("17:02", "18:30")
    body["local_date"] = started_at[:10]
    for number, row in enumerate(body["sets"], start=1):
        row["id"] = new_id()
        row.pop("started_at", None)
        row.pop("ended_at", None)
    return body


def save_template(client, headers, template_id: str | None = None) -> str:
    body = template_body(template_id)
    assert client.post(TEMPLATES, json=body, headers=headers).status_code == 201
    return body["id"]


def save_workout(client, headers, body):
    return client.post(WORKOUTS, json=body, headers=headers)


def last_done(client, headers, template_id):
    response = client.get(TEMPLATES, headers=headers)
    assert response.status_code == 200
    return next(t for t in response.get_json()["templates"] if t["id"] == template_id)["last_done_at"]


def test_ac7_a_first_post_sets_last_done_to_started_at(client, library, signed_in):
    template_id = save_template(client, signed_in["headers"])
    response = save_workout(client, signed_in["headers"], workout_body(template_id, DAY2))
    assert response.status_code == 201
    assert last_done(client, signed_in["headers"], template_id) == DAY2


def test_ac7_a_never_done_template_stays_null_without_a_workout(client, library, signed_in):
    template_id = save_template(client, signed_in["headers"])
    save_workout(client, signed_in["headers"], workout_body(None, DAY2))
    assert last_done(client, signed_in["headers"], template_id) is None


def test_ac7_a_later_workout_moves_last_done_forward(client, library, signed_in):
    template_id = save_template(client, signed_in["headers"])
    save_workout(client, signed_in["headers"], workout_body(template_id, DAY1))
    save_workout(client, signed_in["headers"], workout_body(template_id, DAY3))
    assert last_done(client, signed_in["headers"], template_id) == DAY3


def test_ac7_an_older_workout_does_not_move_last_done_back(client, library, signed_in):
    template_id = save_template(client, signed_in["headers"])
    save_workout(client, signed_in["headers"], workout_body(template_id, DAY3))
    response = save_workout(client, signed_in["headers"], workout_body(template_id, DAY1))
    assert response.status_code == 201
    assert last_done(client, signed_in["headers"], template_id) == DAY3


def test_ac7_a_repeat_post_is_200_and_keeps_last_done(client, library, signed_in):
    template_id = save_template(client, signed_in["headers"])
    body = workout_body(template_id, DAY2)
    first = save_workout(client, signed_in["headers"], body)
    again = save_workout(client, signed_in["headers"], body)
    assert (first.status_code, again.status_code) == (201, 200)
    assert last_done(client, signed_in["headers"], template_id) == DAY2


def test_ac7_a_repeat_after_a_later_workout_does_not_move_it_back(client, library, signed_in):
    template_id = save_template(client, signed_in["headers"])
    older = workout_body(template_id, DAY1)
    save_workout(client, signed_in["headers"], older)
    save_workout(client, signed_in["headers"], workout_body(template_id, DAY3))
    assert save_workout(client, signed_in["headers"], older).status_code == 200
    assert last_done(client, signed_in["headers"], template_id) == DAY3


def test_ac7_a_repeat_does_not_change_other_template_fields(client, library, signed_in):
    template_id = save_template(client, signed_in["headers"])
    body = workout_body(template_id, DAY2)
    save_workout(client, signed_in["headers"], body)
    before = client.get(TEMPLATES, headers=signed_in["headers"]).get_json()
    save_workout(client, signed_in["headers"], body)
    assert client.get(TEMPLATES, headers=signed_in["headers"]).get_json() == before


def test_ac7_an_unknown_template_id_does_not_fail_the_post(client, library, signed_in):
    response = save_workout(client, signed_in["headers"], workout_body(new_id(), DAY2))
    assert response.status_code == 201
    assert client.get(TEMPLATES, headers=signed_in["headers"]).get_json() == {"templates": []}


def test_ac7_an_unknown_template_id_still_saves_the_workout(client, library, signed_in):
    body = workout_body(new_id(), DAY2)
    save_workout(client, signed_in["headers"], body)
    stored = client.get(f"{WORKOUTS}/{body['id']}", headers=signed_in["headers"])
    assert stored.status_code == 200
    assert stored.get_json()["template_id"] == body["template_id"]


def test_ac7_a_deleted_template_does_not_fail_the_post_or_come_back(client, library, signed_in):
    template_id = save_template(client, signed_in["headers"])
    assert client.delete(f"{TEMPLATES}/{template_id}", headers=signed_in["headers"]).status_code == 204
    response = save_workout(client, signed_in["headers"], workout_body(template_id, DAY2))
    assert response.status_code == 201
    assert client.get(TEMPLATES, headers=signed_in["headers"]).get_json() == {"templates": []}


def test_ac7_a_template_id_of_another_user_is_not_touched(client, library, signed_in):
    from services import auth

    other = auth.sign_in("other_user")
    other_headers = {"Authorization": f"Bearer {other['token']}"}
    theirs = save_template(client, other_headers)
    response = save_workout(client, signed_in["headers"], workout_body(theirs, DAY2))
    assert response.status_code == 201
    assert last_done(client, other_headers, theirs) is None


def test_ac7_only_the_named_template_is_updated(client, library, signed_in):
    one = save_template(client, signed_in["headers"])
    two = save_template(client, signed_in["headers"])
    save_workout(client, signed_in["headers"], workout_body(one, DAY2))
    assert last_done(client, signed_in["headers"], one) == DAY2
    assert last_done(client, signed_in["headers"], two) is None


def test_ac7_a_rejected_post_does_not_change_last_done(client, library, signed_in):
    template_id = save_template(client, signed_in["headers"])
    body = workout_body(template_id, DAY2)
    body["sets"] = []
    assert save_workout(client, signed_in["headers"], body).status_code == 400
    assert last_done(client, signed_in["headers"], template_id) is None
