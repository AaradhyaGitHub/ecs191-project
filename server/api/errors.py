"""Turns every error into API.md's shape: {"error": {"code": ..., "message": ...}}."""
from __future__ import annotations

import logging

from flask import Flask, jsonify
from werkzeug.exceptions import HTTPException

from services.errors import STATUS_BY_CODE, ApiError

log = logging.getLogger(__name__)

CODE_BY_STATUS = {status: code for code, status in STATUS_BY_CODE.items()}


def _body(code: str, message: str):
    return jsonify({"error": {"code": code, "message": message}})


def register_error_handlers(app: Flask) -> None:
    @app.errorhandler(ApiError)
    def handle_api_error(err: ApiError):
        return jsonify(err.to_dict()), err.status

    @app.errorhandler(HTTPException)
    def handle_http_error(err: HTTPException):
        # Flask's own errors (unknown route, wrong method, bad JSON). Statuses outside our
        # list, such as 405, keep their status and use the closest code, bad_request.
        status = err.code or 500
        code = CODE_BY_STATUS.get(status, "internal" if status >= 500 else "bad_request")
        return _body(code, err.description or err.name), status

    @app.errorhandler(Exception)
    def handle_unexpected(err: Exception):
        # Never leak internals to the client; the details go to the server log.
        log.exception("Unhandled error")
        return _body("internal", "Something went wrong on the server."), 500
