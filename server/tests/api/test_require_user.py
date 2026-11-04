"""@require_user's header handling. No database: token lookups are replaced, so these run
in the fast suite on every change (review finding S2)."""
import pytest
from flask import Blueprint, jsonify

from api.auth import require_user
from services import auth as auth_service

KNOWN = {"good-token": "user_1"}


@pytest.fixture
def protected(app, monkeypatch):
    monkeypatch.setattr(auth_service, "user_id_for_token", lambda token: KNOWN.get(token))
    bp = Blueprint("require_user_probe", __name__)

    @bp.get("/probe")
    @require_user
    def probe(user_id):
        return jsonify({"user_id": user_id})

    app.register_blueprint(bp)
    return app.test_client()


@pytest.mark.parametrize("header", ["Bearer good-token", "bearer good-token", "BEARER good-token",
                                    "Bearer   good-token  "])
def test_a_valid_token_passes_the_user_id(protected, header):
    response = protected.get("/probe", headers={"Authorization": header})
    assert response.status_code == 200
    assert response.get_json() == {"user_id": "user_1"}


@pytest.mark.parametrize("header", [None, "", "Bearer", "Bearer ", "Bearer    ", "Token good-token",
                                    "good-token", "Basic Zm9vOmJhcg==", "Bearer unknown-token"])
def test_missing_malformed_or_unknown_token_is_unauthorized(protected, header):
    headers = {"Authorization": header} if header is not None else {}
    response = protected.get("/probe", headers=headers)
    assert response.status_code == 401
    assert response.get_json()["error"]["code"] == "unauthorized"


def test_the_401_never_echoes_the_token(protected):
    response = protected.get("/probe", headers={"Authorization": "Bearer unknown-token"})
    assert "unknown-token" not in response.get_data(as_text=True)
