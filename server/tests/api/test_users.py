"""Profile endpoints against the Datastore emulator (specs/log-workout.llm.md, AC-1, AC-9, AC-10)."""
from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path

import pytest

pytestmark = pytest.mark.emulator

FIXTURES = Path(__file__).resolve().parents[3] / "shared" / "fixtures"
USER_KEYS = {"id", "display_name", "sex", "birth_year", "bodyweight_kg", "units", "experience",
             "onboarding_completed", "created_at"}
URL = "/api/v1/users/me"


def error_of(response) -> dict:
    body = response.get_json()
    assert set(body) == {"error"}
    assert set(body["error"]) == {"code", "message"}
    return body["error"]


# --- AC-1 ------------------------------------------------------------------------------------

@pytest.mark.parametrize("method", ["get", "put"])
def test_ac1_without_a_token_is_401(client, emulator, method):
    kwargs = {"json": {"units": "kg"}} if method == "put" else {}
    response = getattr(client, method)(URL, **kwargs)
    assert response.status_code == 401
    assert error_of(response)["code"] == "unauthorized"


@pytest.mark.parametrize("method", ["get", "put"])
def test_ac1_with_an_unknown_token_is_401(client, emulator, method):
    kwargs = {"json": {"units": "kg"}} if method == "put" else {}
    response = getattr(client, method)(URL, headers={"Authorization": "Bearer nope"}, **kwargs)
    assert response.status_code == 401
    assert error_of(response)["code"] == "unauthorized"


# --- AC-9 ------------------------------------------------------------------------------------

def test_ac9_a_new_user_gets_defaults_and_every_field(client, signed_in):
    response = client.get(URL, headers=signed_in["headers"])
    assert response.status_code == 200
    user = response.get_json()
    assert set(user) == USER_KEYS
    assert user["id"] == signed_in["user_id"]
    assert user["display_name"] is None
    assert user["units"] == "lb"
    for key in ("sex", "birth_year", "bodyweight_kg", "experience"):
        assert user[key] is None, key
    assert isinstance(user["created_at"], str)
    datetime.fromisoformat(user["created_at"].replace("Z", "+00:00"))


def test_ac9_matches_the_new_user_fixture_except_id_and_time(client, signed_in):
    expected = json.loads((FIXTURES / "user_new.json").read_text())
    response = client.get(URL, headers=signed_in["headers"])
    assert response.status_code == 200
    user = response.get_json()
    for key in expected:
        if key not in ("id", "created_at"):
            assert user[key] == expected[key], key


# --- AC-10 -----------------------------------------------------------------------------------

def test_ac10_the_update_fixture_changes_those_fields_and_returns_the_full_user(client, signed_in):
    body = json.loads((FIXTURES / "user_update.json").read_text())
    response = client.put(URL, json=body, headers=signed_in["headers"])
    assert response.status_code == 200
    user = response.get_json()
    assert set(user) == USER_KEYS
    assert user["bodyweight_kg"] == 81.5
    assert user["units"] == "kg"
    assert user["display_name"] is None
    assert user["id"] == signed_in["user_id"]
    assert client.get(URL, headers=signed_in["headers"]).get_json() == user


def test_ac10_only_the_fields_sent_change(client, signed_in):
    first = client.put(URL, json={"units": "kg", "bodyweight_kg": 81.5}, headers=signed_in["headers"])
    assert first.status_code == 200
    second = client.put(URL, json={"display_name": "Sasa"}, headers=signed_in["headers"])
    assert second.status_code == 200
    user = second.get_json()
    assert user["display_name"] == "Sasa"
    assert user["units"] == "kg"
    assert user["bodyweight_kg"] == 81.5


def test_ac10_an_empty_body_changes_nothing(client, signed_in):
    first = client.get(URL, headers=signed_in["headers"])
    assert first.status_code == 200
    response = client.put(URL, json={}, headers=signed_in["headers"])
    assert response.status_code == 200
    assert response.get_json() == first.get_json()


@pytest.mark.parametrize("body", [
    {"units": "lb"}, {"units": "kg"},
    {"bodyweight_kg": 0.1}, {"bodyweight_kg": 100},
    {"experience": "beginner"}, {"experience": "intermediate"}, {"experience": "advanced"},
])
def test_ac10_good_values_are_accepted(client, signed_in, body):
    response = client.put(URL, json=body, headers=signed_in["headers"])
    assert response.status_code == 200
    for key, value in body.items():
        assert response.get_json()[key] == value


@pytest.mark.parametrize("body", [
    {"units": "stone"},
    {"bodyweight_kg": 0},
    {"bodyweight_kg": -5},
    {"bodyweight_kg": "heavy"},
    {"experience": "expert"},
    {"email": "a@b.c"},
    {"id": "someone_else"},
    {"units": "kg", "email": "a@b.c"},
    {"units": "kg", "bodyweight_kg": -1},
])
def test_ac10_a_bad_body_is_400_and_changes_nothing(client, signed_in, body):
    first = client.get(URL, headers=signed_in["headers"])
    assert first.status_code == 200
    response = client.put(URL, json=body, headers=signed_in["headers"])
    assert response.status_code == 400
    assert error_of(response)["code"] == "bad_request"
    assert client.get(URL, headers=signed_in["headers"]).get_json() == first.get_json()
