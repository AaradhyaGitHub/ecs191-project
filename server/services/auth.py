"""Sign-in and sessions. No Flask here; api/auth.py has the endpoints and @require_user.

After the course service confirms a code, we make our own session: a random token the
app keeps in the Keychain. Only a SHA-256 hash of it is stored, so a database leak
doesn't hand out working sign-ins. Sessions don't expire for now (llm.md, Decisions).
"""
from __future__ import annotations

import hashlib
import secrets

import models
from services import sms_auth


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def start(phone_number) -> None:
    sms_auth.send_code(phone_number)


def verify(phone_number, code) -> dict:
    """Checks the code with the course service, then signs the user in.

    Returns {"token": ..., "user_id": ...}. Signing in again gives a new token for the
    same user_id; older tokens keep working.
    """
    user_id = sms_auth.check_code(phone_number, code)
    return sign_in(user_id)


def sign_in(user_id: str) -> dict:
    """Creates the user if new and a session for them. Also used by tests to sign in fast."""
    models.ensure_user(user_id)
    token = secrets.token_urlsafe(32)
    models.create_session(token_hash(token), user_id)
    return {"token": token, "user_id": user_id}


def user_id_for_token(token: str) -> str | None:
    if not token:
        return None
    return models.session_user_id(token_hash(token))
