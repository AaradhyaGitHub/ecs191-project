"""Review fixes for saved workouts (S-2), without a database.

S-2a: `superset_group` is at most 60 characters. S-2b: DELETE with an id that isn't a
lowercase UUID never reaches the database.
"""
from __future__ import annotations

import json
import uuid
from pathlib import Path

import pytest

import models
from services import template_service
from services.errors import ApiError

SEED = Path(__file__).resolve().parents[2] / "seed" / "exercises.json"


@pytest.fixture(scope="module")
def library() -> dict[str, dict]:
    data = json.loads(SEED.read_text())
    rows = data["exercises"] if isinstance(data, dict) else data
    return {e["id"]: e for e in rows}


def body_with_group(group) -> dict:
    return {"id": str(uuid.uuid4()), "name": "Push 1", "exercises": [
        {"exercise_id": "barbell_bench_press", "target_sets": 4, "target_reps": 6, "rest_s": 180,
         "superset_group": group}]}


# --- S-2a: superset_group length ------------------------------------------------------------

def test_s2a_group_of_60_characters_is_kept(library):
    cleaned = template_service.clean_input(body_with_group("g" * 60), library)
    assert cleaned["exercises"][0]["superset_group"] == "g" * 60


@pytest.mark.parametrize("length", [61, 2000])
def test_s2a_longer_group_is_a_bad_request(library, length):
    with pytest.raises(ApiError) as caught:
        template_service.clean_input(body_with_group("g" * length), library)
    assert caught.value.code == "bad_request"
    assert "superset_group" in caught.value.message


def test_s2a_a_number_is_still_the_text_or_null_error(library):
    with pytest.raises(ApiError) as caught:
        template_service.clean_input(body_with_group(7), library)
    assert "text or null" in caught.value.message


# --- S-2b: DELETE with a bad id -------------------------------------------------------------

@pytest.mark.parametrize("bad_id", ["x" * 2000, "push-1", str(uuid.uuid4()).upper()])
def test_s2b_bad_id_never_reaches_the_database(monkeypatch, bad_id):
    calls = []
    monkeypatch.setattr(models, "delete_template", lambda *args: calls.append(args))
    assert template_service.delete_template("user_1", bad_id) is None
    assert calls == []


def test_s2b_good_id_still_deletes(monkeypatch):
    calls = []
    monkeypatch.setattr(models, "delete_template", lambda *args: calls.append(args))
    template_id = str(uuid.uuid4())
    template_service.delete_template("user_1", template_id)
    assert calls == [("user_1", template_id)]
