"""Sign-in end to end through Flask and the emulator (the course service is faked)."""
import pytest
from flask import Blueprint, jsonify

import models
from api.auth import require_user
from services.auth import token_hash

pytestmark = pytest.mark.emulator

START = "/api/v1/auth/sms/start"
VERIFY = "/api/v1/auth/sms/verify"
TEST_PHONE = {"phone_number": "+15305550000"}


@pytest.fixture
def protected(app):
    """A throwaway endpoint behind @require_user that echoes the user_id."""
    bp = Blueprint("protected_probe", __name__)

    @bp.get("/probe")
    @require_user
    def probe(user_id):
        return jsonify({"user_id": user_id})

    app.register_blueprint(bp)
    return app.test_client()


def sign_in(client):
    return client.post(VERIFY, json={**TEST_PHONE, "code": "123456"})


def test_start_with_the_test_number(client, emulator, course_auth):
    response = client.post(START, json=TEST_PHONE)
    assert response.status_code == 200
    assert response.get_json() == {"sent": True}


def test_verify_returns_a_token_and_user_id(client, emulator, course_auth):
    response = sign_in(client)
    assert response.status_code == 200
    body = response.get_json()
    assert body["user_id"] == "course_user_1"
    assert len(body["token"]) >= 32


def test_the_token_opens_protected_endpoints(protected, emulator, course_auth):
    token = sign_in(protected).get_json()["token"]
    response = protected.get("/probe", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert response.get_json() == {"user_id": "course_user_1"}


def test_first_sign_in_creates_the_user_once(client, emulator, course_auth):
    sign_in(client)
    sign_in(client)
    assert models.get_user("course_user_1") is not None


def test_signing_in_again_gives_a_new_token_and_old_ones_still_work(protected, emulator, course_auth):
    first = sign_in(protected).get_json()
    second = sign_in(protected).get_json()
    assert first["token"] != second["token"]
    assert first["user_id"] == second["user_id"]
    for token in (first["token"], second["token"]):
        assert protected.get("/probe", headers={"Authorization": f"Bearer {token}"}).status_code == 200


def test_only_a_hash_of_the_token_is_stored(client, emulator, course_auth):
    token = sign_in(client).get_json()["token"]
    assert models.session_user_id(token) is None
    assert models.session_user_id(token_hash(token)) == "course_user_1"


def test_unknown_token_is_unauthorized(protected, emulator):
    response = protected.get("/probe", headers={"Authorization": "Bearer not-a-real-token"})
    assert response.status_code == 401
    assert response.get_json()["error"]["code"] == "unauthorized"


def test_wrong_code_is_unauthorized(client, emulator, course_auth):
    response = client.post(VERIFY, json={**TEST_PHONE, "code": "000000"})
    assert response.status_code == 401
    assert response.get_json()["error"]["code"] == "unauthorized"


def test_non_json_body_is_bad_request(client, emulator, course_auth):
    response = client.post(START, data="phone=+15305550000")
    assert response.status_code == 400
    assert response.get_json()["error"]["code"] == "bad_request"


def test_signed_in_fixture_works(protected, signed_in):
    response = protected.get("/probe", headers=signed_in["headers"])
    assert response.get_json() == {"user_id": signed_in["user_id"]}
