"""D-23 at the endpoint: 31 different exercises are refused and nothing is saved.

Written by implementer (not test-writer). Needs the Datastore emulator.
"""
from __future__ import annotations

import json
import uuid
from pathlib import Path

import pytest

import models

pytestmark = pytest.mark.emulator

SEED = Path(__file__).resolve().parents[3] / "server" / "seed" / "exercises.json"


def test_31_different_exercises_is_400_and_saves_nothing(client, signed_in):
    data = json.loads(SEED.read_text())
    library = data["exercises"] if isinstance(data, dict) else data
    models.put_exercises(library)
    slugs = sorted(e["id"] for e in library)[:31]
    assert len(slugs) == 31
    body = {"id": str(uuid.uuid4()), "name": "Big day", "started_at": "2026-11-02T17:00:00Z",
            "ended_at": "2026-11-02T19:00:00Z", "timezone": "America/Los_Angeles",
            "local_date": "2026-11-02",
            "sets": [{"id": str(uuid.uuid4()), "exercise_id": slug, "order": n, "set_type": "working",
                      "reps": 5} for n, slug in enumerate(slugs, start=1)]}

    response = client.post("/api/v1/workouts", json=body, headers=signed_in["headers"])
    assert response.status_code == 400
    assert response.get_json()["error"]["code"] == "bad_request"
    listing = client.get("/api/v1/workouts", headers=signed_in["headers"])
    assert listing.get_json() == {"workouts": []}
