"""Review fixes for saved workouts (S-1, S-2), against the Datastore emulator.

S-1: `models.add_template` reads and writes in one transaction, so a repeat id writes nothing.
S-2: a long `superset_group` is 400, and a long DELETE id is 204; neither is 500.
"""
from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone
from pathlib import Path

import pytest

import models

pytestmark = pytest.mark.emulator

SEED = Path(__file__).resolve().parents[2] / "seed" / "exercises.json"
URL = "/api/v1/templates"
T0 = datetime(2026, 11, 2, 17, 2, tzinfo=timezone.utc)
T1 = datetime(2026, 11, 3, 9, 30, tzinfo=timezone.utc)


@pytest.fixture
def library(emulator):
    data = json.loads(SEED.read_text())
    models.put_exercises(data["exercises"] if isinstance(data, dict) else data)


def template(template_id: str, **changes) -> dict:
    data = {"id": template_id, "name": "Push 1", "focus": None,
            "exercises": [{"exercise_id": "barbell_bench_press", "target_sets": 4, "target_reps": 6,
                           "rest_s": 180, "superset_group": None}],
            "last_done_at": None, "created_at": T0}
    data.update(changes)
    return data


# --- S-1: create in one transaction ---------------------------------------------------------

def test_s1_first_add_creates(signed_in):
    template_id = str(uuid.uuid4())
    stored, created = models.add_template(signed_in["user_id"], template(template_id))
    assert created is True
    assert stored["id"] == template_id
    assert models.get_template(signed_in["user_id"], template_id)["name"] == "Push 1"


def test_s1_second_add_changes_nothing(signed_in):
    user_id, template_id = signed_in["user_id"], str(uuid.uuid4())
    models.add_template(user_id, template(template_id))
    # The saved workout is done once, then a late retry of the first POST arrives.
    models.change_template(user_id, template_id, lambda old: {**old, "last_done_at": T1})
    before = models.get_template(user_id, template_id)

    stored, created = models.add_template(
        user_id, template(template_id, name="Other", created_at=T1, last_done_at=None))

    assert created is False
    assert stored == before
    after = models.get_template(user_id, template_id)
    assert after == before
    assert after["created_at"] == T0
    assert after["last_done_at"] == T1


# --- S-2: no 500 for long text --------------------------------------------------------------

def test_s2a_long_superset_group_is_400(client, library, signed_in):
    body = {"id": str(uuid.uuid4()), "name": "Push 1", "exercises": [
        {"exercise_id": "barbell_bench_press", "target_sets": 4, "target_reps": 6, "rest_s": 180,
         "superset_group": "g" * 2000}]}
    response = client.post(URL, json=body, headers=signed_in["headers"])
    assert response.status_code == 400
    assert response.get_json()["error"]["code"] == "bad_request"


def test_s2b_long_delete_id_is_204(client, signed_in):
    response = client.delete(f"{URL}/{'x' * 2000}", headers=signed_in["headers"])
    assert response.status_code == 204
    assert response.get_data() == b""
