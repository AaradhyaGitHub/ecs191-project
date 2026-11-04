"""D-25 at the endpoint: NaN and Infinity in the JSON are refused and nothing is saved.

Written by implementer (not test-writer). Needs the Datastore emulator.
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

import models

pytestmark = pytest.mark.emulator

ROOT = Path(__file__).resolve().parents[3]


@pytest.mark.parametrize("bad", ["NaN", "Infinity", "-Infinity"])
def test_non_finite_numbers_are_400(client, signed_in, bad):
    data = json.loads((ROOT / "server" / "seed" / "exercises.json").read_text())
    models.put_exercises(data["exercises"] if isinstance(data, dict) else data)
    text = (ROOT / "shared" / "fixtures" / "workout_post.json").read_text()
    text = text.replace('"weight_kg": 70.3', f'"weight_kg": {bad}')
    assert bad in text

    response = client.post("/api/v1/workouts", data=text, content_type="application/json",
                           headers=signed_in["headers"])
    assert response.status_code == 400
    assert response.get_json()["error"]["code"] == "bad_request"
    listing = client.get("/api/v1/workouts", headers=signed_in["headers"])
    assert listing.get_json() == {"workouts": []}
