"""Every error reaches the app in API.md's shape: {"error": {"code", "message"}}."""
from flask import Blueprint

from services.errors import ApiError


def add_route(app, rule, view, methods=("GET",)):
    bp = Blueprint(f"test_{view.__name__}", __name__)
    bp.add_url_rule(rule, view_func=view, methods=list(methods))
    app.register_blueprint(bp)


def test_unknown_route_is_not_found(client):
    response = client.get("/api/v1/no-such-thing")

    assert response.status_code == 404
    assert response.get_json()["error"]["code"] == "not_found"


def test_api_error_from_a_service_keeps_its_code_and_message(app):
    def missing():
        raise ApiError("not_found", "No workout with that id.")

    add_route(app, "/boom-api", missing)
    response = app.test_client().get("/boom-api")

    assert response.status_code == 404
    assert response.get_json() == {"error": {"code": "not_found", "message": "No workout with that id."}}


def test_wrong_method_uses_bad_request_code_with_its_own_status(client):
    response = client.delete("/api/v1/health")

    assert response.status_code == 405
    assert response.get_json()["error"]["code"] == "bad_request"


def test_unexpected_exception_is_internal_and_hides_details(app):
    def crash():
        raise RuntimeError("database password is hunter2")

    add_route(app, "/boom-crash", crash)
    app.config.update(PROPAGATE_EXCEPTIONS=False)
    response = app.test_client().get("/boom-crash")

    assert response.status_code == 500
    body = response.get_json()
    assert body["error"]["code"] == "internal"
    assert "hunter2" not in body["error"]["message"]
