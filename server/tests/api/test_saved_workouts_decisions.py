"""Review fix S-1 and Sasa's Nov 4, 2026 decisions for saved workouts (#43).

- S-1: `record_done` never fails `POST /workouts`, first save or repeat.
- A saved workout made from a finished workout counts as done: `POST /templates` takes an
  optional `last_done_at`; a future time is stored as the server's current time. `PUT` drops
  the field before checking, so it never causes a 400 there.
"""
from __future__ import annotations

import copy
import json
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

import models
from services import template_service

pytestmark = pytest.mark.emulator

ROOT = Path(__file__).resolve().parents[3]
SEED = ROOT / "server" / "seed" / "exercises.json"
WORKOUT_FIXTURE = ROOT / "shared" / "fixtures" / "workout_post.json"
TEMPLATES = "/api/v1/templates"
WORKOUTS = "/api/v1/workouts"
DAY2 = "2026-11-02T17:02:00Z"


@pytest.fixture
def library(emulator):
    models.put_exercises(json.loads(SEED.read_text())["exercises"])


def new_id() -> str:
    return str(uuid.uuid4())


def template_body(**changes) -> dict:
    body = {"id": new_id(), "name": "Push A", "focus": None,
            "exercises": [{"exercise_id": "barbell_bench_press", "target_sets": 2, "target_reps": 8,
                           "rest_s": 90}]}
    body.update(changes)
    return body


def workout_body(template_id) -> dict:
    body = copy.deepcopy(json.loads(WORKOUT_FIXTURE.read_text()))
    body["id"] = new_id()
    body["template_id"] = template_id
    body["started_at"] = DAY2
    body["ended_at"] = DAY2.replace("17:02", "18:30")
    body["local_date"] = DAY2[:10]
    for row in body["sets"]:
        row["id"] = new_id()
        row.pop("started_at", None)
        row.pop("ended_at", None)
    return body


def listed(client, headers, template_id):
    response = client.get(TEMPLATES, headers=headers)
    assert response.status_code == 200
    return next(t for t in response.get_json()["templates"] if t["id"] == template_id)


def iso(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


# --- S-1 ------------------------------------------------------------------------------------

@pytest.fixture
def broken_record_done(monkeypatch):
    def fail(*_args, **_kwargs):
        raise RuntimeError("Datastore is down")
    monkeypatch.setattr(template_service, "record_done", fail)


def test_s1_a_failing_record_done_still_saves_the_workout(client, library, signed_in, broken_record_done):
    headers = signed_in["headers"]
    body = workout_body(new_id())
    response = client.post(WORKOUTS, json=body, headers=headers)
    assert response.status_code == 201
    assert response.get_json()["id"] == body["id"]
    assert client.get(f"{WORKOUTS}/{body['id']}", headers=headers).status_code == 200


def test_s1_a_failing_record_done_still_answers_a_repeat_with_200(client, library, signed_in, monkeypatch):
    headers = signed_in["headers"]
    body = workout_body(new_id())
    assert client.post(WORKOUTS, json=body, headers=headers).status_code == 201
    monkeypatch.setattr(template_service, "record_done",
                        lambda *a, **k: (_ for _ in ()).throw(RuntimeError("down")))
    again = client.post(WORKOUTS, json=body, headers=headers)
    assert again.status_code == 200
    assert again.get_json()["id"] == body["id"]


def test_s1_the_failure_is_logged(client, library, signed_in, broken_record_done, caplog):
    client.post(WORKOUTS, json=workout_body(new_id()), headers=signed_in["headers"])
    assert any("last done" in r.getMessage() for r in caplog.records)


# --- last_done_at on POST /templates ----------------------------------------------------------

def test_post_keeps_a_last_done_at(client, library, signed_in):
    body = template_body(last_done_at=DAY2)
    response = client.post(TEMPLATES, json=body, headers=signed_in["headers"])
    assert response.status_code == 201
    assert response.get_json()["last_done_at"] == DAY2
    assert listed(client, signed_in["headers"], body["id"])["last_done_at"] == DAY2


def test_post_without_last_done_at_is_null(client, library, signed_in):
    body = template_body()
    assert client.post(TEMPLATES, json=body, headers=signed_in["headers"]).get_json()["last_done_at"] is None


def test_post_with_null_last_done_at_is_null(client, library, signed_in):
    body = template_body(last_done_at=None)
    assert client.post(TEMPLATES, json=body, headers=signed_in["headers"]).get_json()["last_done_at"] is None


def stored_last_done(client, headers, template_id) -> datetime:
    text = listed(client, headers, template_id)["last_done_at"]
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def test_post_with_a_phone_clock_slightly_ahead_stores_server_now(client, library, signed_in):
    before = datetime.now(timezone.utc)
    body = template_body(last_done_at=iso(before + timedelta(minutes=2)))
    assert client.post(TEMPLATES, json=body, headers=signed_in["headers"]).status_code == 201
    stored = stored_last_done(client, signed_in["headers"], body["id"])
    assert before - timedelta(seconds=2) <= stored <= datetime.now(timezone.utc) + timedelta(seconds=2)


@pytest.mark.parametrize("value", ["yesterday", "2026-13-01T00:00:00Z", 42, True, ""])
def test_post_rejects_a_last_done_at_that_isnt_a_timestamp(client, library, signed_in, value):
    response = client.post(TEMPLATES, json=template_body(last_done_at=value), headers=signed_in["headers"])
    assert response.status_code == 400
    assert response.get_json()["error"]["code"] == "bad_request"


def test_a_phone_clock_1_hour_ahead_gives_201_and_server_now(client, library, signed_in):
    before = datetime.now(timezone.utc)
    body = template_body(last_done_at=iso(before + timedelta(hours=1)))
    response = client.post(TEMPLATES, json=body, headers=signed_in["headers"])
    after = datetime.now(timezone.utc)
    assert response.status_code == 201
    answered = datetime.fromisoformat(response.get_json()["last_done_at"].replace("Z", "+00:00"))
    assert before - timedelta(seconds=2) <= answered <= after + timedelta(seconds=2)
    assert stored_last_done(client, signed_in["headers"], body["id"]) == answered


@pytest.mark.parametrize("value", ["yesterday", 42, True, {"at": DAY2}])
def test_put_ignores_an_invalid_last_done_at(client, library, signed_in, value):
    headers = signed_in["headers"]
    body = template_body(last_done_at=DAY2)
    client.post(TEMPLATES, json=body, headers=headers)
    response = client.put(f"{TEMPLATES}/{body['id']}", json={**body, "name": "Push B", "last_done_at": value},
                          headers=headers)
    assert response.status_code == 200
    assert response.get_json()["name"] == "Push B"
    assert response.get_json()["last_done_at"] == DAY2


def test_put_ignores_last_done_at(client, library, signed_in):
    headers = signed_in["headers"]
    body = template_body(last_done_at=DAY2)
    client.post(TEMPLATES, json=body, headers=headers)
    changed = {**body, "name": "Push B", "last_done_at": "2026-11-03T17:02:00Z"}
    response = client.put(f"{TEMPLATES}/{body['id']}", json=changed, headers=headers)
    assert response.status_code == 200
    assert response.get_json()["name"] == "Push B"
    assert response.get_json()["last_done_at"] == DAY2


def test_a_repeat_post_keeps_the_stored_last_done_at(client, library, signed_in):
    headers = signed_in["headers"]
    body = template_body(last_done_at=DAY2)
    client.post(TEMPLATES, json=body, headers=headers)
    again = client.post(TEMPLATES, json={**body, "last_done_at": None}, headers=headers)
    assert again.status_code == 200
    assert again.get_json()["last_done_at"] == DAY2
