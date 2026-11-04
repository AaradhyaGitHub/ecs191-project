"""The app's bundled exercise library must match what the server returns (Sasa, Nov 4, 2026).

The app ships ios/MuscleMapKit/Sources/LiftCore/Resources/exercise_library.json, made by
seed/export_library.py from the server's own code. These tests fail while it is out of date.
"""
from __future__ import annotations

import json

import pytest

import models
from seed import export_library

FIX = "Regenerate it: cd server && .venv/bin/python -m seed.export_library"


def bundled() -> dict:
    return json.loads(export_library.LIBRARY_PATH.read_text())


def test_the_bundled_library_exists():
    assert export_library.LIBRARY_PATH.exists(), f"{export_library.LIBRARY_PATH} is missing. {FIX}"


def test_the_bundled_library_is_what_the_server_returns_for_the_seed():
    assert bundled() == export_library.library(), f"The app's exercise library is out of date. {FIX}"


def test_the_bundled_file_has_the_generated_text():
    assert export_library.LIBRARY_PATH.read_text() == export_library.library_text(), \
        f"The app's exercise library isn't in the generated format. {FIX}"


def test_every_seed_exercise_is_bundled_with_groups_and_primary_muscles():
    seed = json.loads(export_library.SEED.read_text())["exercises"]
    exercises = bundled()["exercises"]
    assert sorted(e["id"] for e in exercises) == sorted(e["id"] for e in seed)
    assert all(e["groups"] and e["primary_muscles"] for e in exercises)


def test_the_bundled_library_is_a_to_z():
    names = [e["name"].lower() for e in bundled()["exercises"]]
    assert names == sorted(names)


@pytest.mark.emulator
def test_the_bundled_library_equals_get_exercises(client, emulator):
    """The real endpoint, with the seed loaded, returns exactly the bundled file."""
    models.put_exercises(json.loads(export_library.SEED.read_text())["exercises"])
    response = client.get("/api/v1/exercises")
    assert response.status_code == 200
    assert response.get_json() == bundled(), f"The app's exercise library is out of date. {FIX}"
