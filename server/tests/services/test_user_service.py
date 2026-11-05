"""Profile update rules (specs/log-workout.llm.md, AC-10).

No database: models is replaced, so a refused body must never reach a write.
"""
from __future__ import annotations

from datetime import datetime, timezone

import pytest

import models
from services import user_service
from services.errors import ApiError

STORED = {"id": "u_1", "created_at": datetime(2026, 11, 1, tzinfo=timezone.utc)}


@pytest.fixture
def writes(monkeypatch):
    """Records every write to the User; reads return a stored user."""
    calls: list = []

    def fake_update(user_id, fields):
        calls.append((user_id, dict(fields)))
        return {**STORED, **fields}

    monkeypatch.setattr(models, "update_user", fake_update)
    monkeypatch.setattr(models, "get_user", lambda user_id: dict(STORED))
    return calls


@pytest.mark.parametrize("body", [
    {"units": "stone"},
    {"units": "LB"},
    {"units": 5},
    {"bodyweight_kg": 0},
    {"bodyweight_kg": -3},
    {"bodyweight_kg": "heavy"},
    {"bodyweight_kg": True},
    {"experience": "expert"},
    {"email": "a@b.c"},
    {"id": "someone_else"},
    {"created_at": "2026-01-01T00:00:00Z"},
    {"units": "kg", "email": "a@b.c"},          # one good field must not slip through
    {"units": "kg", "bodyweight_kg": -1},
])
def test_ac10_a_bad_body_is_refused_and_nothing_is_written(writes, body):
    with pytest.raises(ApiError) as caught:
        user_service.update_me("u_1", body)
    assert caught.value.code == "bad_request"
    assert writes == []
