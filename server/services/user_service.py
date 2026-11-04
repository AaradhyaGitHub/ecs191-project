"""The signed-in user's profile (API.md, "GET /users/me" and "PUT /users/me").
No Flask here; api/users.py has the endpoints.
"""
from __future__ import annotations

import models
from services.errors import ApiError
from services.timestamps import iso

# The only fields PUT /users/me may change (API.md).
EDITABLE_FIELDS = ("display_name", "sex", "birth_year", "bodyweight_kg", "units", "experience")
UNITS = ("lb", "kg")
EXPERIENCE = ("beginner", "intermediate", "advanced")
DEFAULT_UNITS = "lb"


def _is_number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _text_or_null(value) -> bool:
    return value is None or isinstance(value, str)


def _whole_number_or_null(value) -> bool:
    return value is None or (isinstance(value, int) and not isinstance(value, bool))


# Each editable field and the rule its value must pass (API.md, "PUT /users/me").
_RULES = {
    "display_name": (_text_or_null, "text or null"),
    "sex": (_text_or_null, "text or null"),
    "birth_year": (_whole_number_or_null, "a whole number or null"),
    "bodyweight_kg": (lambda v: _is_number(v) and v > 0, "a number above 0"),
    "units": (lambda v: v in UNITS, "lb or kg"),
    "experience": (lambda v: v in EXPERIENCE, "beginner, intermediate or advanced"),
}


def _profile(user: dict) -> dict:
    """The stored user in API.md's shape: every field present; units "lb" until set (D-8)."""
    return {
        "id": user["id"],
        "display_name": user.get("display_name"),
        "sex": user.get("sex"),
        "birth_year": user.get("birth_year"),
        "bodyweight_kg": user.get("bodyweight_kg"),
        "units": user.get("units") or DEFAULT_UNITS,
        "experience": user.get("experience"),
        "created_at": iso(user.get("created_at")),
    }


def get_me(user_id: str) -> dict:
    """The full profile in API.md's shape. A new user gets units "lb" and nulls (D-8)."""
    user = models.get_user(user_id)
    if user is None:
        raise ApiError("not_found", "No profile for this sign-in. Sign in again.")
    return _profile(user)


def update_me(user_id: str, body: dict) -> dict:
    """Changes only the fields sent and returns the full profile.

    Raises ApiError("bad_request"), and changes nothing, for a bad value or an unknown field.
    """
    if not isinstance(body, dict):
        raise ApiError("bad_request", "Send the changes as a JSON object.")
    unknown = sorted(key for key in body if key not in EDITABLE_FIELDS)
    if unknown:
        raise ApiError("bad_request",
                       f"These fields can't be changed: {', '.join(unknown)}. "
                       f"Use only: {', '.join(EDITABLE_FIELDS)}.")
    for key, value in body.items():
        check, what = _RULES[key]
        if not check(value):
            raise ApiError("bad_request", f"{key} must be {what}.")
    if not body:
        return get_me(user_id)
    return _profile(models.update_user(user_id, dict(body)))
