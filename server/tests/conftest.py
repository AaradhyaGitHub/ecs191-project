"""Shared fixtures.

Tests marked `emulator` run only when DATASTORE_EMULATOR_HOST is set, so a missing
emulator skips them instead of ever reaching the real database.
"""
from __future__ import annotations

import os
import urllib.request

import pytest

from main import create_app


@pytest.fixture
def app():
    app = create_app()
    app.config.update(TESTING=True)
    return app


@pytest.fixture
def client(app):
    return app.test_client()


def pytest_collection_modifyitems(config, items):
    if os.environ.get("DATASTORE_EMULATOR_HOST"):
        return
    skip = pytest.mark.skip(reason="Datastore emulator not running (set DATASTORE_EMULATOR_HOST)")
    for item in items:
        if "emulator" in item.keywords:
            item.add_marker(skip)


@pytest.fixture
def emulator():
    """Empties the emulator before the test, so tests never see each other's data."""
    host = os.environ["DATASTORE_EMULATOR_HOST"]
    request = urllib.request.Request(f"http://{host}/reset", method="POST")
    urllib.request.urlopen(request, timeout=5).close()
    yield host


class FakeCourseAuth:
    """Stands in for the course's SMS sign-in service, with the same test-number behavior
    (course API.md, "Test Phone Numbers"). Records every call it gets."""

    def __init__(self):
        self.calls = []

    def __call__(self, path, payload):
        self.calls.append((path, payload))
        phone = payload.get("phone_number")
        if phone == "+15305550001":
            return 400, {"error": "Failed to send verification: Invalid phone number"}
        if phone == "+15305550004":
            return 400, {"error": "Failed to send verification: Service temporarily unavailable"}
        if not phone.startswith("+1530555") and "app_token" not in payload:
            return 401, {"error": "app_token is required"}
        if path == "/v1/send_sms_code":
            return 200, {"success": True}
        if phone == "+15305550000" and payload.get("code") == "123456":
            return 200, {"success": True, "token": "course-token", "user_id": "course_user_1"}
        return 401, {"error": "Invalid or expired code"}


@pytest.fixture
def course_auth(monkeypatch):
    """Replaces calls to the course sign-in service with FakeCourseAuth (no network)."""
    from services import sms_auth

    fake = FakeCourseAuth()
    monkeypatch.setattr(sms_auth, "_post", fake)
    monkeypatch.delenv("SMS_APP_TOKEN", raising=False)
    return fake


@pytest.fixture
def signed_in(emulator):
    """A signed-in user in one line: `def test_x(client, signed_in): client.get(..., headers=signed_in["headers"])`."""
    from services import auth

    session = auth.sign_in("test_user")
    return {"user_id": session["user_id"], "headers": {"Authorization": f"Bearer {session['token']}"}}
