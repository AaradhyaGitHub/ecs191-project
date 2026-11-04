"""Client for the course's hosted SMS sign-in service (llm.md, Decisions: "Sign-in").

The course service sends the text and checks the code; we never touch Twilio. Its API is
POST /v1/send_sms_code and POST /v1/verify_code (see the course repo's API.md).

- `app_token` is the course's key for real phone numbers. It comes from the SMS_APP_TOKEN
  environment variable and never ships in the iOS app. Without it, only the course's test
  numbers work, which is all development needs: +15305550000 with code 123456.
- Errors become ApiError with our own codes, so the app sees one error shape.
"""
from __future__ import annotations

import json
import os
import re
import urllib.error
import urllib.request

from services.errors import ApiError

COURSE_AUTH_URL = os.environ.get("COURSE_AUTH_URL", "https://ecs191-sms-authentication.uc.r.appspot.com")
# Scopes accounts on the course service: the same phone gets a different user_id per app.
APP_ID = "musclemap-ecs191"
TEST_PHONE = "+15305550000"
TEST_CODE = "123456"

E164 = re.compile(r"^\+[1-9]\d{1,14}$")
TIMEOUT_S = 10


def _post(path: str, payload: dict) -> tuple[int, dict]:
    """POSTs JSON to the course service and returns (status, body). Tests replace this."""
    request = urllib.request.Request(
        COURSE_AUTH_URL + path,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_S) as response:
            return response.status, _as_object(response.read())
    except urllib.error.HTTPError as err:
        return err.code, _as_object(err.read())


def _as_object(raw: bytes) -> dict:
    """The JSON body if it's an object; {} for empty, invalid or non-object JSON (e.g. a proxy page)."""
    try:
        body = json.loads(raw or b"{}")
    except ValueError:
        return {}
    return body if isinstance(body, dict) else {}


def _payload(phone_number: str, **extra) -> dict:
    payload = {"phone_number": phone_number, "app_id": APP_ID, **extra}
    token = os.environ.get("SMS_APP_TOKEN")
    if token:
        payload["app_token"] = token
    return payload


def _check_phone(phone_number) -> str:
    if not isinstance(phone_number, str) or not E164.match(phone_number):
        raise ApiError("bad_request", "Use a phone number in E.164 format, e.g. +15305550000.")
    return phone_number


def _call(path: str, payload: dict) -> dict:
    try:
        status, body = _post(path, payload)
    except (OSError, ValueError):
        raise ApiError("internal", "The sign-in service can't be reached right now. Try again.")

    if not isinstance(body, dict):
        body = {}
    if status == 200:
        return body
    message = str(body.get("error") or "Sign-in failed.")
    # Matches the course service's wording ("app_token is required" / "Invalid app_token").
    # Re-check it against the real service once our app token arrives (review finding S4).
    if status == 401 and "app_token" in message:
        raise ApiError("forbidden", "Real phone numbers can't sign in yet (the course app token isn't "
                                    f"set up). Use the test number {TEST_PHONE} with code {TEST_CODE}.")
    if status == 401:
        raise ApiError("unauthorized", message)
    if status == 400:
        raise ApiError("bad_request", message)
    raise ApiError("internal", "The sign-in service had a problem. Try again.")


def send_code(phone_number) -> None:
    """Texts a 6-digit code to the phone (or does nothing, for test numbers)."""
    _call("/v1/send_sms_code", _payload(_check_phone(phone_number)))


def check_code(phone_number, code) -> str:
    """Checks the code and returns the course's user_id for this phone and app."""
    _check_phone(phone_number)
    if not isinstance(code, str) or not code.strip():
        raise ApiError("bad_request", "Enter the 6-digit code from the text message.")
    body = _call("/v1/verify_code", _payload(phone_number, code=code.strip()))
    user_id = body.get("user_id")
    if not user_id:
        raise ApiError("internal", "The sign-in service didn't return a user.")
    return str(user_id)
