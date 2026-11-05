"""Review fix S-2 against the Datastore emulator: concurrent POSTs can't pass the limit.

Each thread has its own test client. A transaction that loses to another may be aborted
by Datastore (any non-201 answer is fine here); what matters is what ends up stored.
"""
from __future__ import annotations

import json
import threading
import uuid
from datetime import date
from pathlib import Path

import pytest

import models
from services import goal_service

pytestmark = pytest.mark.emulator

SEED = Path(__file__).resolve().parents[2] / "seed" / "exercises.json"
GOALS = "/api/v1/goals"


@pytest.fixture
def library(emulator):
    data = json.loads(SEED.read_text())
    models.put_exercises(data["exercises"] if isinstance(data, dict) else data)


def strength(**changes) -> dict:
    return {"id": str(uuid.uuid4()), "type": "strength", "exercise_id": "barbell_bench_press",
            "target": 100.0, "start_date": "2026-10-20", **changes}


def frequency(**changes) -> dict:
    return {"id": str(uuid.uuid4()), "type": "frequency", "target": 4, "start_date": "2026-10-12", **changes}


def create(client, headers, body) -> None:
    assert client.post(GOALS, json=body, headers=headers).status_code == 201


def _post_together(app, headers, bodies) -> list[int]:
    statuses: list[int] = []
    start = threading.Barrier(len(bodies))

    def run(b):
        client = app.test_client()
        start.wait()
        statuses.append(client.post(GOALS, json=b, headers=headers).status_code)

    threads = [threading.Thread(target=run, args=(b,)) for b in bodies]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=30)
    return statuses


def test_s2_two_posts_at_once_at_two_active_never_store_four(app, client, library, signed_in):
    for _ in range(2):
        create(client, signed_in["headers"], strength())
    statuses = _post_together(app, signed_in["headers"], [strength(), strength(), strength()])
    assert statuses.count(201) >= 1
    active = [g for g in goal_service.list_goals(signed_in["user_id"], date(2026, 11, 4))
              if g["status"] == "active"]
    assert len(active) == 3


def test_s2_two_frequency_posts_at_once_store_one(app, library, signed_in):
    statuses = _post_together(app, signed_in["headers"], [frequency(), frequency(target=2)])
    assert statuses.count(201) >= 1
    stored = [g for g in models.user_goals(signed_in["user_id"]) if g["type"] == "frequency"]
    assert len(stored) == 1


def test_s2_models_add_goal_writes_once_and_a_retry_is_not_checked(library, signed_in):
    data = {"id": str(uuid.uuid4()), "type": "frequency", "exercise_id": None, "target": 4,
            "start_date": "2026-10-12", "deadline": None}
    seen = []
    stored, created = models.add_goal(signed_in["user_id"], data, seen.append)
    assert created and seen == [[]]
    stored, created = models.add_goal(signed_in["user_id"], {**data, "target": 7}, seen.append)
    assert created is False and stored["target"] == 4 and len(seen) == 1
