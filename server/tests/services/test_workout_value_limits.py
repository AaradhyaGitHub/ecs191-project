"""D-25 (Sasa, Nov 4, 2026): value limits on POST /workouts and PUT /users/me.

Written by implementer (not test-writer). Pure logic: no database.
"""
from __future__ import annotations

import copy
import json
import math
from pathlib import Path

import pytest

import models
from services import user_service, workout_service
from services.errors import ApiError

FIXTURE = Path(__file__).resolve().parents[3] / "shared" / "fixtures" / "workout_post.json"
KNOWN = {"barbell_bench_press", "push_up"}


def body() -> dict:
    return copy.deepcopy(json.loads(FIXTURE.read_text()))


def bench(**fields) -> dict:
    """The fixture with its first (barbell) set changed."""
    data = body()
    data["sets"][0].update(fields)
    return data


def push_up(**fields) -> dict:
    """The fixture with its second (bodyweight, superset) set changed."""
    data = body()
    data["sets"][1].update(fields)
    return data


def timed(seconds) -> dict:
    data = body()
    data["sets"][1].pop("reps")
    data["sets"][1]["duration_s"] = seconds
    return data


def workout(**fields) -> dict:
    data = body()
    data.update(fields)
    return data


def accepted(data: dict) -> bool:
    try:
        workout_service.validate_workout(data, KNOWN)
    except ApiError as error:
        assert error.code == "bad_request"
        return False
    return True


GOOD = [
    bench(reps=1), bench(reps=1000),
    timed(1), timed(3600),
    bench(rest_before_s=0), bench(rest_before_s=3600), bench(rest_before_s=None),
    bench(weight_kg=0), bench(weight_kg=1000),
    push_up(added_load_kg=-500), push_up(added_load_kg=500),
    workout(bodyweight_kg=0.1), workout(bodyweight_kg=500), workout(bodyweight_kg=None),
    bench(order=300),
    workout(name="x"), workout(name="x" * 60),
    push_up(superset_group="a"), push_up(superset_group="x" * 60),
    workout(timezone="x" * 64),
    workout(template_id=None),
]

BAD = [
    bench(reps=0), bench(reps=1001),
    timed(0), timed(3601),
    bench(rest_before_s=-1), bench(rest_before_s=3601),
    bench(weight_kg=1000.01), bench(weight_kg=math.nan), bench(weight_kg=math.inf),
    push_up(added_load_kg=-500.5), push_up(added_load_kg=500.5), push_up(added_load_kg=math.nan),
    workout(bodyweight_kg=0), workout(bodyweight_kg=500.1), workout(bodyweight_kg=math.inf),
    bench(effort_pct=math.nan),
    bench(order=0), bench(order=301),
    workout(name="x" * 61),
    push_up(superset_group=""), push_up(superset_group="x" * 61),
    workout(timezone="x" * 65),
    workout(template_id="not-a-uuid"), workout(template_id="3C9D7E1A-5B2F-4C8D-A6E4-7F8A9B0C1D2E"),
]


@pytest.mark.parametrize("data", GOOD)
def test_values_at_the_limits_are_accepted(data):
    assert accepted(data)


@pytest.mark.parametrize("data", BAD)
def test_values_past_the_limits_are_refused(data):
    assert not accepted(data)


@pytest.fixture
def no_writes(monkeypatch):
    writes = []
    def fake_update(user_id, fields):
        writes.append(fields)
        return {"id": user_id, **fields}

    monkeypatch.setattr(models, "update_user", fake_update)
    monkeypatch.setattr(models, "get_user", lambda user_id: {"id": user_id})
    return writes


@pytest.mark.parametrize("value", [500.1, math.inf, math.nan, 1e9])
def test_put_me_refuses_a_bodyweight_past_500(no_writes, value):
    with pytest.raises(ApiError) as caught:
        user_service.update_me("u_1", {"bodyweight_kg": value})
    assert caught.value.code == "bad_request"
    assert no_writes == []


def test_put_me_accepts_500(no_writes):
    user_service.update_me("u_1", {"bodyweight_kg": 500})
    assert no_writes == [{"bodyweight_kg": 500}]
