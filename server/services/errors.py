"""Errors that services raise. No Flask here: api/errors.py turns them into JSON responses.

The codes are the fixed list in API.md ("Errors"). Don't add one without updating API.md.
"""
from __future__ import annotations

STATUS_BY_CODE = {
    "bad_request": 400,
    "unauthorized": 401,
    "forbidden": 403,
    "not_found": 404,
    "conflict": 409,
    "internal": 500,
}


class ApiError(Exception):
    """An error the client should see, e.g. `raise ApiError("not_found", "No workout with that id.")`."""

    def __init__(self, code: str, message: str) -> None:
        if code not in STATUS_BY_CODE:
            raise ValueError(f"Unknown error code {code!r}; the codes are listed in API.md")
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = STATUS_BY_CODE[code]

    def to_dict(self) -> dict:
        return {"error": {"code": self.code, "message": self.message}}
