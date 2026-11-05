"""onboarding_completed on GET/PUT /users/me against the Datastore emulator
(specs/onboarding.llm.md, AC-1 and AC-2).
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

pytestmark = pytest.mark.emulator

FIXTURES = Path(__file__).resolve().parents[3] / "shared" / "fixtures"
URL = "/api/v1/users/me"


def error_of(response) -> dict:
    body = response.get_json()
    assert set(body) == {"error"}
    assert set(body["error"]) == {"code", "message"}
    return body["error"]


# --- AC-1 ------------------------------------------------------------------------------------

def test_ac1_a_new_user_has_onboarding_completed_false(client, signed_in):
    response = client.get(URL, headers=signed_in["headers"])
    assert response.status_code == 200
    assert response.get_json()["onboarding_completed"] is False


# --- AC-2 ------------------------------------------------------------------------------------

def test_ac2_the_update_fixture_sets_it_and_a_later_get_agrees(client, signed_in):
    body = json.loads((FIXTURES / "user_update_onboarding.json").read_text())
    response = client.put(URL, json=body, headers=signed_in["headers"])
    assert response.status_code == 200
    assert response.get_json()["onboarding_completed"] is True
    assert client.get(URL, headers=signed_in["headers"]).get_json()["onboarding_completed"] is True


def test_ac2_it_can_be_set_back_to_false(client, signed_in):
    assert client.put(URL, json={"onboarding_completed": True},
                      headers=signed_in["headers"]).status_code == 200
    response = client.put(URL, json={"onboarding_completed": False}, headers=signed_in["headers"])
    assert response.status_code == 200
    assert response.get_json()["onboarding_completed"] is False


def test_ac2_setting_it_leaves_other_fields_alone(client, signed_in):
    client.put(URL, json={"units": "kg", "display_name": "Sasa"}, headers=signed_in["headers"])
    response = client.put(URL, json={"onboarding_completed": True}, headers=signed_in["headers"])
    user = response.get_json()
    assert user["units"] == "kg"
    assert user["display_name"] == "Sasa"


def test_ac2_saving_the_profile_does_not_set_it(client, signed_in):
    response = client.put(URL, json={"display_name": "Sasa", "units": "kg"},
                          headers=signed_in["headers"])
    assert response.status_code == 200
    assert response.get_json()["onboarding_completed"] is False


@pytest.mark.parametrize("value", ["true", "yes", 1, 0, None, []])
def test_ac2_a_non_boolean_is_400_and_changes_nothing(client, signed_in, value):
    first = client.get(URL, headers=signed_in["headers"])
    response = client.put(URL, json={"onboarding_completed": value}, headers=signed_in["headers"])
    assert response.status_code == 400
    assert error_of(response)["code"] == "bad_request"
    assert client.get(URL, headers=signed_in["headers"]).get_json() == first.get_json()


def test_ac2_a_bad_flag_next_to_a_good_field_changes_nothing(client, signed_in):
    first = client.get(URL, headers=signed_in["headers"])
    response = client.put(URL, json={"units": "kg", "onboarding_completed": "yes"},
                          headers=signed_in["headers"])
    assert response.status_code == 400
    assert client.get(URL, headers=signed_in["headers"]).get_json() == first.get_json()
