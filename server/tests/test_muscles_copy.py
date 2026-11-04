"""AC-9: the server reads its own copy of the muscle tables, and the copy must not drift."""
from __future__ import annotations

import json
from pathlib import Path

from services import exercise_service

SERVER = Path(__file__).resolve().parents[1]
SERVER_COPY = SERVER / "muscles.json"
SHARED = SERVER.parent / "shared" / "muscles.json"


def test_ac9_server_copy_equals_shared_file():
    assert SERVER_COPY.exists(), "server/muscles.json is missing: copy shared/muscles.json to it"
    assert json.loads(SERVER_COPY.read_text()) == json.loads(SHARED.read_text())


def test_ac9_load_muscles_returns_the_shared_tables():
    assert exercise_service.load_muscles() == json.loads(SHARED.read_text())


def test_ac9_the_service_looks_at_the_server_copy_only():
    assert exercise_service.MUSCLES_PATH == SERVER_COPY
