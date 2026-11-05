"""D-23 (Sasa, Nov 4, 2026): a workout has at most 30 different exercises.

Written by implementer (not test-writer), because the decision came after the tests.
"""
from __future__ import annotations

import uuid

import pytest

from services import workout_service
from services.errors import ApiError

KNOWN = {f"exercise_{n}" for n in range(40)}


def body_with(exercise_count: int, sets_each: int = 1) -> dict:
    sets = []
    for n in range(exercise_count):
        for _ in range(sets_each):
            sets.append({"id": str(uuid.uuid4()), "exercise_id": f"exercise_{n}",
                         "order": len(sets) + 1, "set_type": "working", "reps": 5})
    return {"id": str(uuid.uuid4()), "name": "Big day", "started_at": "2026-11-02T17:00:00Z",
            "ended_at": "2026-11-02T19:00:00Z", "timezone": "America/Los_Angeles",
            "local_date": "2026-11-02", "sets": sets}


def test_30_different_exercises_are_valid():
    clean = workout_service.validate_workout(body_with(30), KNOWN)
    assert clean["workout"]["exercise_count"] == 30


def test_31_different_exercises_are_refused():
    with pytest.raises(ApiError) as caught:
        workout_service.validate_workout(body_with(31), KNOWN)
    assert caught.value.code == "bad_request"


def test_many_sets_of_few_exercises_are_valid():
    clean = workout_service.validate_workout(body_with(10, sets_each=30), KNOWN)
    assert len(clean["sets"]) == 300
