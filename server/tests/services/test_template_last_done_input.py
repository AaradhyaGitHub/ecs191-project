"""`clean_input` reads the optional `last_done_at` of POST /templates (Sasa, Nov 4, 2026)."""
from __future__ import annotations

import json
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

from services import template_service
from services.errors import ApiError

SEED = Path(__file__).resolve().parents[2] / "seed" / "exercises.json"
NOW = datetime(2026, 11, 4, 20, 0, tzinfo=timezone.utc)


@pytest.fixture(scope="module")
def library() -> dict[str, dict]:
    return {e["id"]: e for e in json.loads(SEED.read_text())["exercises"]}


def body(**changes) -> dict:
    value = {"id": str(uuid.uuid4()), "name": "Push A",
             "exercises": [{"exercise_id": "barbell_bench_press", "target_sets": 2, "rest_s": 90}]}
    value.update(changes)
    return value


def test_missing_or_null_is_none(library):
    assert template_service.clean_input(body(), library, now=NOW)["last_done_at"] is None
    assert template_service.clean_input(body(last_done_at=None), library, now=NOW)["last_done_at"] is None


def test_a_timestamp_becomes_a_utc_datetime(library):
    cleaned = template_service.clean_input(body(last_done_at="2026-11-04T11:30:00-08:00"), library, now=NOW)
    assert cleaned["last_done_at"] == datetime(2026, 11, 4, 19, 30, tzinfo=timezone.utc)


def test_up_to_the_clock_skew_ahead_is_accepted(library):
    edge = (NOW + template_service.CLOCK_SKEW).isoformat()
    assert template_service.clean_input(body(last_done_at=edge), library, now=NOW)["last_done_at"] is not None


def test_past_the_clock_skew_is_bad_request(library):
    late = (NOW + template_service.CLOCK_SKEW + timedelta(seconds=1)).isoformat()
    with pytest.raises(ApiError) as caught:
        template_service.clean_input(body(last_done_at=late), library, now=NOW)
    assert caught.value.code == "bad_request"


def test_the_clock_skew_is_small():
    assert timedelta(0) < template_service.CLOCK_SKEW <= timedelta(minutes=10)


@pytest.mark.parametrize("value", ["soon", 1793725200, False, "", []])
def test_a_value_that_isnt_a_timestamp_is_bad_request(library, value):
    with pytest.raises(ApiError) as caught:
        template_service.clean_input(body(last_done_at=value), library, now=NOW)
    assert caught.value.code == "bad_request"
