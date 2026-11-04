"""The course-service client: what it sends, and how its errors map to our error codes.
No network and no database: `course_auth` replaces the HTTP call."""
import pytest

from services import sms_auth
from services.errors import ApiError


def test_start_sends_phone_and_our_app_id_without_a_token(course_auth):
    sms_auth.send_code("+15305550000")
    path, payload = course_auth.calls[-1]
    assert path == "/v1/send_sms_code"
    assert payload == {"phone_number": "+15305550000", "app_id": "musclemap-ecs191"}


def test_app_token_is_sent_when_configured(course_auth, monkeypatch):
    monkeypatch.setenv("SMS_APP_TOKEN", "staff-issued")
    sms_auth.send_code("+14155551234")
    assert course_auth.calls[-1][1]["app_token"] == "staff-issued"


@pytest.mark.parametrize("phone", ["4155551234", "+0123", "", None, 15305550000, "+1 530 555 0000"])
def test_bad_phone_is_refused_before_calling_the_course(course_auth, phone):
    with pytest.raises(ApiError) as err:
        sms_auth.send_code(phone)
    assert err.value.code == "bad_request"
    assert course_auth.calls == []


def test_verify_returns_the_course_user_id(course_auth):
    assert sms_auth.check_code("+15305550000", "123456") == "course_user_1"


def test_wrong_code_is_unauthorized(course_auth):
    with pytest.raises(ApiError) as err:
        sms_auth.check_code("+15305550002", "999999")
    assert err.value.code == "unauthorized"


def test_missing_code_is_bad_request(course_auth):
    with pytest.raises(ApiError) as err:
        sms_auth.check_code("+15305550000", "  ")
    assert err.value.code == "bad_request"
    assert course_auth.calls == []


def test_course_400_keeps_its_message(course_auth):
    with pytest.raises(ApiError) as err:
        sms_auth.send_code("+15305550001")
    assert err.value.code == "bad_request"
    assert "Invalid phone number" in err.value.message


def test_real_number_without_app_token_says_use_the_test_number(course_auth):
    with pytest.raises(ApiError) as err:
        sms_auth.send_code("+14155551234")
    assert err.value.code == "forbidden"
    assert "+15305550000" in err.value.message


def test_unreachable_service_is_internal(monkeypatch):
    def offline(path, payload):
        raise OSError("no route to host")

    monkeypatch.setattr(sms_auth, "_post", offline)
    with pytest.raises(ApiError) as err:
        sms_auth.send_code("+15305550000")
    assert err.value.code == "internal"
