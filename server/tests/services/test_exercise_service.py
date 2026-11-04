"""Exercise search rules (specs/exercise-search.llm.md, AC-2 to AC-6).

Pure logic: runs on seed/exercises.json in memory, with shared/muscles.json as the muscle
tables. No database and no Flask.
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

import models
from services import exercise_service

SERVER = Path(__file__).resolve().parents[2]
SEED = SERVER / "seed" / "exercises.json"
SHARED_MUSCLES = SERVER.parent / "shared" / "muscles.json"


def _load_seed() -> list[dict]:
    data = json.loads(SEED.read_text())
    return data["exercises"] if isinstance(data, dict) else data


@pytest.fixture(scope="module")
def library() -> list[dict]:
    return _load_seed()


@pytest.fixture(scope="module")
def muscles() -> dict:
    return json.loads(SHARED_MUSCLES.read_text())


def names(results: list[dict]) -> list[str]:
    return [r["name"] for r in results]


def by_name(results: list[dict], name: str) -> dict:
    matches = [r for r in results if r["name"] == name]
    assert matches, f"{name!r} is not in the results"
    return matches[0]


def run(library, muscles, q=None, group=None) -> list[dict]:
    return exercise_service.search(library, q, group, muscles)


# --- AC-2: matching ----------------------------------------------------------------------

def test_ac2_blank_text_returns_the_whole_library(library, muscles):
    assert len(library) > 0
    for q in (None, "", "   "):
        assert len(run(library, muscles, q)) == len(library), repr(q)


def test_ac2_blank_text_is_a_to_z_by_name(library, muscles):
    result = names(run(library, muscles, None))
    assert result == sorted(result, key=str.lower)
    assert len(result) == len(library)


def test_ac2_ignores_case(library, muscles):
    assert "Bench Press" in names(run(library, muscles, "BEN"))
    assert names(run(library, muscles, "BEN")) == names(run(library, muscles, "ben"))


def test_ac2_matches_an_alias(library, muscles):
    assert "Bench Press" in names(run(library, muscles, "bp"))


def test_ac2_ignores_spaces_around_the_text(library, muscles):
    assert names(run(library, muscles, "  bench  ")) == names(run(library, muscles, "bench"))
    assert names(run(library, muscles, "  bench  ")) != []


def test_ac2_does_not_match_inside_a_word(library, muscles):
    assert "Bench Press" in names(run(library, muscles, "bench"))
    assert run(library, muscles, "ench") == []


def test_ac2_matches_a_later_word_in_the_name(library, muscles):
    assert names(run(library, muscles, "split squat")) == ["Bulgarian Split Squat"]


def test_ac2_a_hyphen_starts_a_word(library, muscles):
    assert "Push-up" in names(run(library, muscles, "up"))


def test_ac2_text_that_matches_nothing_gives_an_empty_list(library, muscles):
    assert len(run(library, muscles, None)) == len(library)
    assert run(library, muscles, "zzzzqqq") == []


# --- AC-3: order -------------------------------------------------------------------------

def test_ac3_bench_order(library, muscles):
    assert names(run(library, muscles, "bench")) == [
        "Bench Press", "Dumbbell Bench Press", "Incline Bench Press"]


def test_ac3_squat_order(library, muscles):
    assert names(run(library, muscles, "squat")) == [
        "Back Squat", "Bulgarian Split Squat", "Front Squat", "Goblet Squat"]


def test_ac3_press_name_matches_first_then_alias_only(library, muscles):
    result = names(run(library, muscles, "press"))
    assert len(result) == 10
    assert result[7:] == ["Overhead Triceps Extension", "Push-up", "Triceps Pushdown"]
    first = result[:7]
    assert first == sorted(first, key=str.lower)
    assert all("press" in n.lower() for n in first)


def test_ac3_up_order(library, muscles):
    assert names(run(library, muscles, "up")) == ["Chin-up", "Pull-up", "Push-up", "Inverted Row"]


# --- AC-4: groups and primary_muscles ------------------------------------------------------

def test_ac4_every_exercise_has_both_fields(library, muscles):
    group_ids = {g["id"] for g in muscles["groups"]}
    results = run(library, muscles, None)
    assert len(results) == len(library)
    for item in results:
        assert isinstance(item.get("groups"), list), item["name"]
        assert isinstance(item.get("primary_muscles"), list), item["name"]
        assert item["groups"], f"{item['name']} has no group"
        assert set(item["groups"]) <= group_ids
        assert len(set(item["groups"])) == len(item["groups"])
        assert len(set(item["primary_muscles"])) == len(item["primary_muscles"])


@pytest.mark.parametrize("name, groups, primary", [
    ("Deadlift", ["legs", "back"], ["Glutes", "Lower back", "Hamstrings"]),
    ("Dips", ["chest", "arms"], ["Chest", "Triceps"]),
    ("Hanging Leg Raise", ["core", "legs"], ["Abs", "Hip flexors"]),
    ("Barbell Curl", ["arms"], ["Biceps"]),
])
def test_ac4_known_exercises(library, muscles, name, groups, primary):
    item = by_name(run(library, muscles, None), name)
    assert item["groups"] == groups
    assert item["primary_muscles"] == primary


def test_ac4_only_three_exercises_have_two_groups(library, muscles):
    multi = sorted(i["name"] for i in run(library, muscles, None) if len(i["groups"]) > 1)
    assert multi == ["Deadlift", "Dips", "Hanging Leg Raise"]


def test_ac4_strongest_muscle_comes_first_whatever_the_list_order(muscles):
    exercise = {"id": "x", "name": "X", "aliases": [], "load_type": "barbell", "muscles": [
        {"muscle_id": "hamstrings", "role": "primary", "weight": 0.8},
        {"muscle_id": "glutes_max", "role": "primary", "weight": 1.0},
    ]}
    assert exercise_service.primary_muscles_of(exercise, muscles) == ["Glutes", "Hamstrings"]
    assert exercise_service.groups_of(exercise, muscles) == ["legs"]


def test_ac4_two_heads_of_one_parent_count_once(muscles):
    exercise = {"id": "x", "name": "X", "aliases": [], "load_type": "dumbbell", "muscles": [
        {"muscle_id": "biceps_long", "role": "primary", "weight": 1.0},
        {"muscle_id": "biceps_short", "role": "primary", "weight": 0.9},
    ]}
    assert exercise_service.primary_muscles_of(exercise, muscles) == ["Biceps"]
    assert exercise_service.groups_of(exercise, muscles) == ["arms"]


def test_ac4_secondary_and_stabilizer_muscles_are_left_out(muscles):
    exercise = {"id": "x", "name": "X", "aliases": [], "load_type": "barbell", "muscles": [
        {"muscle_id": "chest_sternal", "role": "primary", "weight": 1.0},
        {"muscle_id": "triceps_long", "role": "secondary", "weight": 0.5},
        {"muscle_id": "abs_rectus", "role": "stabilizer", "weight": 0.2},
    ]}
    assert exercise_service.primary_muscles_of(exercise, muscles) == ["Chest"]
    assert exercise_service.groups_of(exercise, muscles) == ["chest"]


def test_ac4_no_primary_muscle_gives_empty_lists(muscles):
    control = {"id": "c", "name": "C", "aliases": [], "load_type": "barbell", "muscles": [
        {"muscle_id": "chest_sternal", "role": "primary", "weight": 1.0}]}
    assert exercise_service.groups_of(control, muscles) == ["chest"]
    exercise = {"id": "x", "name": "X", "aliases": [], "load_type": "barbell", "muscles": [
        {"muscle_id": "triceps_long", "role": "secondary", "weight": 0.5}]}
    assert exercise_service.primary_muscles_of(exercise, muscles) == []
    assert exercise_service.groups_of(exercise, muscles) == []


# --- AC-5: group filter --------------------------------------------------------------------

@pytest.mark.parametrize("group, expected", [
    ("back", ["Deadlift"]),
    ("arms", ["Dips"]),
    ("legs", ["Deadlift", "Hanging Leg Raise"]),
    ("chest", ["Dips"]),
])
def test_ac5_group_includes_exercises_with_a_second_group(library, muscles, group, expected):
    result = run(library, muscles, None, group)
    for name in expected:
        assert name in names(result)


@pytest.mark.parametrize("group", ["chest", "back", "shoulders", "arms", "legs", "core"])
def test_ac5_group_keeps_only_that_group(library, muscles, group):
    result = run(library, muscles, None, group)
    assert result, f"no exercises in {group}"
    assert all(group in item["groups"] for item in result)
    expected = [e for e in run(library, muscles, None) if group in e["groups"]]
    assert names(result) == names(expected)


def test_ac5_group_works_together_with_text(library, muscles):
    assert names(run(library, muscles, "dip", "chest")) == ["Dips"]
    assert names(run(library, muscles, "dip", "arms")) == ["Dips"]
    assert run(library, muscles, "dip", "legs") == []
    assert "Hanging Leg Raise" in names(run(library, muscles, "leg", "core"))
    assert all("core" in i["groups"] for i in run(library, muscles, "leg", "core"))


def test_ac5_no_group_means_all_groups(library, muscles):
    assert len(run(library, muscles, None, None)) == len(library)


# --- AC-6: unknown group -------------------------------------------------------------------

def test_ac6_unknown_group_is_a_bad_request(monkeypatch, library):
    monkeypatch.setattr(models, "all_exercises", lambda: library)
    with pytest.raises(Exception) as caught:
        exercise_service.find_exercises(None, "biceps")
    assert type(caught.value).__name__ == "ApiError"
    assert getattr(caught.value, "code", None) == "bad_request"


def test_ac6_a_known_group_is_not_an_error(monkeypatch, library):
    monkeypatch.setattr(models, "all_exercises", lambda: library)
    result = exercise_service.find_exercises(None, "chest")
    assert "Dips" in names(result)
