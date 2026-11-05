"""onboarding_completed on the profile (specs/onboarding.llm.md, AC-1 and AC-2).

No database: models is replaced, so a refused body must never reach a write.
"""
from __future__ import annotations

from datetime import datetime, timezone

import pytest

import models
from services import user_service
from services.errors import ApiError

BASE = {"id": "u_1", "created_at": datetime(2026, 11, 1, tzinfo=timezone.utc)}


def install(monkeypatch, stored: dict) -> list:
    """Reads return `stored`; every write is recorded and applied to a copy."""
    calls: list = []

    def fake_update(user_id, fields):
        calls.append((user_id, dict(fields)))
        return {**stored, **fields}

    monkeypatch.setattr(models, "update_user", fake_update)
    monkeypatch.setattr(models, "get_user", lambda user_id: dict(stored))
    return calls


# --- AC-1 ------------------------------------------------------------------------------------

def test_ac1_a_user_stored_before_the_field_existed_gets_false(monkeypatch):
    install(monkeypatch, dict(BASE))
    profile = user_service.get_me("u_1")
    assert "onboarding_completed" in profile
    assert profile["onboarding_completed"] is False


@pytest.mark.parametrize("stored_value", [True, False])
def test_ac1_a_stored_value_is_returned_as_a_bool(monkeypatch, stored_value):
    install(monkeypatch, {**BASE, "onboarding_completed": stored_value})
    assert user_service.get_me("u_1")["onboarding_completed"] is stored_value


def test_ac1_a_stored_none_counts_as_false(monkeypatch):
    install(monkeypatch, {**BASE, "onboarding_completed": None})
    assert user_service.get_me("u_1")["onboarding_completed"] is False


# --- AC-2 ------------------------------------------------------------------------------------

@pytest.mark.parametrize("value", [True, False])
def test_ac2_true_and_false_are_saved_and_returned(monkeypatch, value):
    calls = install(monkeypatch, dict(BASE))
    profile = user_service.update_me("u_1", {"onboarding_completed": value})
    assert calls == [("u_1", {"onboarding_completed": value})]
    assert profile["onboarding_completed"] is value


def test_ac2_it_can_be_sent_with_other_fields(monkeypatch):
    calls = install(monkeypatch, dict(BASE))
    profile = user_service.update_me("u_1", {"onboarding_completed": True, "units": "kg"})
    assert calls == [("u_1", {"onboarding_completed": True, "units": "kg"})]
    assert profile["onboarding_completed"] is True
    assert profile["units"] == "kg"


@pytest.mark.parametrize("value", ["true", "false", "yes", 1, 0, 1.0, None, [], {}, [True]])
def test_ac2_a_non_boolean_is_refused_and_nothing_is_written(monkeypatch, value):
    calls = install(monkeypatch, dict(BASE))
    with pytest.raises(ApiError) as caught:
        user_service.update_me("u_1", {"onboarding_completed": value})
    assert caught.value.code == "bad_request"
    assert calls == []


def test_ac2_one_good_field_does_not_slip_through_with_a_bad_flag(monkeypatch):
    calls = install(monkeypatch, dict(BASE))
    with pytest.raises(ApiError) as caught:
        user_service.update_me("u_1", {"units": "kg", "onboarding_completed": "yes"})
    assert caught.value.code == "bad_request"
    assert calls == []


def test_ac2_other_fields_keep_their_rules(monkeypatch):
    calls = install(monkeypatch, dict(BASE))
    with pytest.raises(ApiError) as caught:
        user_service.update_me("u_1", {"onboarding_completed": True, "units": "stone"})
    assert caught.value.code == "bad_request"
    assert calls == []
