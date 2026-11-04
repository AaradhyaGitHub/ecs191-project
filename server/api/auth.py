"""Sign-in endpoints (API.md, "Sign-in") and @require_user for every other endpoint.

Usage in any Blueprint:

    @bp.get("")
    @require_user
    def list_things(user_id):
        ...
"""
from __future__ import annotations

from functools import wraps

from flask import Blueprint, jsonify, request

from services import auth as auth_service
from services.errors import ApiError

bp = Blueprint("auth", __name__)


def _body() -> dict:
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        raise ApiError("bad_request", "Send a JSON object.")
    return data


@bp.post("/sms/start")
def sms_start():
    auth_service.start(_body().get("phone_number"))
    return jsonify({"sent": True})


@bp.post("/sms/verify")
def sms_verify():
    data = _body()
    return jsonify(auth_service.verify(data.get("phone_number"), data.get("code")))


def require_user(view):
    """Rejects requests without a valid `Authorization: Bearer <token>`; passes `user_id` first."""
    @wraps(view)
    def wrapper(*args, **kwargs):
        header = request.headers.get("Authorization", "")
        if not header.startswith("Bearer ") or not header[7:].strip():
            raise ApiError("unauthorized", "Sign in first: send Authorization: Bearer <token>.")
        user_id = auth_service.user_id_for_token(header[7:].strip())
        if user_id is None:
            raise ApiError("unauthorized", "That sign-in isn't valid anymore. Sign in again.")
        return view(user_id, *args, **kwargs)
    return wrapper
