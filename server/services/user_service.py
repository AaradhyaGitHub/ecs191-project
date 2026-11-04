"""The signed-in user's profile (API.md, "GET /users/me" and "PUT /users/me").
No Flask here; api/users.py has the endpoints.

SCAFFOLD: every function returns a valid but wrong value. Build mode fills them in.
"""
from __future__ import annotations

import models  # noqa: F401  (used in build mode)
from services.errors import ApiError  # noqa: F401  (used in build mode)

# The only fields PUT /users/me may change (API.md).
EDITABLE_FIELDS = ("display_name", "sex", "birth_year", "bodyweight_kg", "units", "experience")
UNITS = ("lb", "kg")
EXPERIENCE = ("beginner", "intermediate", "advanced")


def get_me(user_id: str) -> dict:
    """The full profile in API.md's shape. A new user gets units "lb" and nulls (D-8)."""
    return {}


def update_me(user_id: str, body: dict) -> dict:
    """Changes only the fields sent and returns the full profile.

    Raises ApiError("bad_request"), and changes nothing, for a bad value or an unknown field.
    """
    return {}
