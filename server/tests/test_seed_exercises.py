"""Checks server/seed/exercises.json, the starter exercise library, against
shared/muscles.json and the data model (server_architecture.llm.md, "Exercise").
"""
import json
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SEED = ROOT / "server" / "seed" / "exercises.json"
MUSCLES = ROOT / "shared" / "muscles.json"

LOAD_TYPES = {"barbell", "dumbbell", "machine", "cable", "bodyweight", "timed"}
ROLES = {"primary", "secondary", "stabilizer"}
SLUG = re.compile(r"^[a-z][a-z0-9]*(_[a-z0-9]+)*$")


@pytest.fixture(scope="module")
def exercises():
    return json.loads(SEED.read_text())["exercises"]


@pytest.fixture(scope="module")
def muscles():
    data = json.loads(MUSCLES.read_text())
    heads = {m["id"]: m["parent"] for m in data["muscles"]}
    parents = {p["id"] for p in data["parents"]}
    return heads, parents


def test_ids_are_unique_slugs(exercises):
    ids = [e["id"] for e in exercises]
    assert len(ids) == len(set(ids))
    assert [i for i in ids if not SLUG.match(i)] == []


def test_names_and_aliases_are_unique_case_insensitively(exercises):
    seen = {}
    for e in exercises:
        for term in [e["name"], *e["aliases"]]:
            key = term.lower()
            assert key not in seen, f"{term!r} is used by both {seen[key]} and {e['id']}"
            seen[key] = e["id"]


def test_load_types_are_known(exercises):
    assert {e["load_type"] for e in exercises} <= LOAD_TYPES


def test_every_muscle_id_exists(exercises, muscles):
    heads, parents = muscles
    unknown = [(e["id"], m["muscle_id"]) for e in exercises for m in e["muscles"]
               if m["muscle_id"] not in heads and m["muscle_id"] not in parents]
    assert unknown == []


def test_muscle_entries_are_valid(exercises):
    for e in exercises:
        assert e["muscles"], e["id"]
        assert any(m["role"] == "primary" for m in e["muscles"]), f"{e['id']} has no primary muscle"
        for m in e["muscles"]:
            assert m["role"] in ROLES, e["id"]
            assert 0 < m["weight"] <= 1, e["id"]


def test_no_muscle_is_counted_twice(exercises, muscles):
    """An exercise can't list a parent and one of its heads, or the same muscle twice."""
    heads, _ = muscles
    for e in exercises:
        ids = [m["muscle_id"] for m in e["muscles"]]
        assert len(ids) == len(set(ids)), e["id"]
        parents_listed = {i for i in ids if i not in heads}
        overlap = [i for i in ids if heads.get(i) in parents_listed]
        assert overlap == [], f"{e['id']} lists both a parent and its head: {overlap}"


def test_bodyweight_fraction_only_on_bodyweight_exercises(exercises):
    for e in exercises:
        if e["load_type"] == "bodyweight":
            assert 0 < e["bodyweight_fraction"] <= 1, e["id"]
        else:
            assert e["bodyweight_fraction"] is None, e["id"]


def test_implement_count_only_on_dumbbell_exercises(exercises):
    """Dumbbell sets log one dumbbell's weight; volume multiplies by implement_count (#6)."""
    for e in exercises:
        if e["load_type"] == "dumbbell":
            assert e["implement_count"] in (1, 2), e["id"]
        else:
            assert "implement_count" not in e, e["id"]


def test_starter_library_covers_the_lift_mockups(exercises):
    names = {e["name"] for e in exercises}
    in_mockups = {"Bench Press", "Incline Bench Press", "Pec Fly", "Barbell Overhead Press",
                  "Dumbbell Shoulder Press", "Push-up", "Inverted Row", "Dips", "Face Pull",
                  "Plank", "Back Squat"}
    assert in_mockups <= names
