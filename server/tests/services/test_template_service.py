"""Saved-workout rules (specs/saved-workouts.llm.md, AC-3, AC-6, AC-7).

Pure logic: the real seed library and the server's muscle tables in memory.
No database and no Flask.
"""
from __future__ import annotations

import copy
import json
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

from services import exercise_service, template_service
from services.errors import ApiError

SEED = Path(__file__).resolve().parents[2] / "seed" / "exercises.json"

T0 = datetime(2026, 11, 2, 17, 2, tzinfo=timezone.utc)


def _load_seed() -> list[dict]:
    data = json.loads(SEED.read_text())
    return data["exercises"] if isinstance(data, dict) else data


@pytest.fixture(scope="module")
def library() -> dict[str, dict]:
    return {e["id"]: e for e in _load_seed()}


@pytest.fixture(scope="module")
def muscles() -> dict:
    return exercise_service.load_muscles()


def fake(slug: str, *muscle_weights: tuple) -> dict:
    """A made-up exercise: fake("x", ("chest_sternal", 1.0), ("triceps_long", 0.5, "secondary"))."""
    return {"id": slug, "name": slug, "muscles": [
        {"muscle_id": m[0], "role": m[2] if len(m) > 2 else "primary", "weight": m[1]}
        for m in muscle_weights]}


def item(slug: str, sets: int = 1) -> dict:
    return {"exercise_id": slug, "target_sets": sets, "target_reps": 8, "rest_s": 90}


def as_tuples(result: list[dict]) -> list[tuple]:
    return [(r["muscle_id"], r["level"]) for r in result]


# --- AC-6: top_muscles ----------------------------------------------------------------------

def test_ac6_bench_press_example(library, muscles):
    result = template_service.top_muscles([item("barbell_bench_press", 4)], library, muscles)
    assert [(r["muscle_id"], r["name"], r["level"]) for r in result] == [
        ("chest", "Chest", 4), ("delts", "Delts", 2), ("triceps", "Triceps", 2)]


def test_ac6_fourth_muscle_is_left_out(library, muscles):
    result = template_service.top_muscles([item("barbell_bench_press", 4)], library, muscles)
    assert len(result) == 3
    assert "serratus" not in [r["muscle_id"] for r in result]


def test_ac6_items_have_exactly_three_keys(library, muscles):
    result = template_service.top_muscles([item("barbell_bench_press", 4)], library, muscles)
    assert result, "bench press should give chips"
    assert all(set(r) == {"muscle_id", "name", "level"} for r in result)


def test_ac6_no_exercises_gives_no_chips_and_a_real_one_still_does(library, muscles):
    assert template_service.top_muscles([], {}, muscles) == []
    assert template_service.top_muscles([item("barbell_bench_press", 1)], library, muscles) != []


def test_ac6_fewer_than_three_parents_gives_fewer_chips(muscles):
    ex = {"x": fake("x", ("chest_sternal", 1.0), ("chest_clavicular", 0.6))}
    result = template_service.top_muscles([item("x", 2)], ex, muscles)
    assert as_tuples(result) == [("chest", 4)]


def test_ac6_heads_of_one_parent_add_up(muscles):
    # chest = 1.0 + 0.6 = 1.6 beats delts 1.5 (two heads of 0.75), so heads are summed, not compared alone.
    ex = {"x": fake("x", ("chest_sternal", 1.0), ("chest_clavicular", 0.6),
                    ("delts_front", 0.75), ("delts_side", 0.75))}
    result = template_service.top_muscles([item("x", 1)], ex, muscles)
    assert [r["muscle_id"] for r in result] == ["chest", "delts"]
    assert as_tuples(result) == [("chest", 4), ("delts", 4)]


def test_ac6_a_parent_id_adds_to_itself(muscles):
    ex = {"x": fake("x", ("triceps", 1.0), ("chest_sternal", 0.5))}
    result = template_service.top_muscles([item("x", 2)], ex, muscles)
    assert as_tuples(result) == [("triceps", 4), ("chest", 2)]


def test_ac6_unknown_muscle_ids_are_skipped(muscles):
    ex = {"x": fake("x", ("no_such_muscle", 5.0), ("chest_sternal", 1.0))}
    result = template_service.top_muscles([item("x", 1)], ex, muscles)
    assert as_tuples(result) == [("chest", 4)]


def test_ac6_all_roles_count(muscles):
    ex = {"x": fake("x", ("chest_sternal", 1.0, "primary"), ("delts_front", 1.0, "secondary"),
                    ("triceps_long", 1.0, "stabilizer"))}
    result = template_service.top_muscles([item("x", 1)], ex, muscles)
    assert {r["muscle_id"] for r in result} == {"chest", "delts", "triceps"}


def test_ac6_work_is_target_sets_times_weight_summed_over_exercises(muscles):
    ex = {"a": fake("a", ("chest_sternal", 1.0)), "b": fake("b", ("delts_front", 1.0))}
    # chest 2 x 1.0 = 2; delts 3 x 1.0 = 3
    result = template_service.top_muscles([item("a", 2), item("b", 3)], ex, muscles)
    assert as_tuples(result) == [("delts", 4), ("chest", 3)]  # ceil(4 * 2 / 3) = 3


def test_ac6_same_parent_from_two_exercises_adds_up(muscles):
    ex = {"a": fake("a", ("chest_sternal", 1.0)), "b": fake("b", ("chest_clavicular", 1.0)),
          "c": fake("c", ("delts_front", 1.0))}
    result = template_service.top_muscles([item("a", 1), item("b", 1), item("c", 2)], ex, muscles)
    assert as_tuples(result) == [("chest", 4), ("delts", 4)]


def test_ac6_level_is_ceiling_of_four_times_share(muscles):
    # top 8, others 3 (ceil 1.5 = 2), 1 (ceil 0.5 = 1)
    ex = {"a": fake("a", ("chest_sternal", 1.0)), "b": fake("b", ("delts_front", 1.0)),
          "c": fake("c", ("triceps_long", 1.0))}
    result = template_service.top_muscles([item("a", 8), item("b", 3), item("c", 1)], ex, muscles)
    assert as_tuples(result) == [("chest", 4), ("delts", 2), ("triceps", 1)]


def test_ac6_exact_half_is_level_two_not_three(muscles):
    ex = {"x": fake("x", ("chest_sternal", 1.0), ("delts_front", 0.5))}
    result = template_service.top_muscles([item("x", 1)], ex, muscles)
    assert as_tuples(result) == [("chest", 4), ("delts", 2)]


def test_ac6_top_chip_is_always_level_four(muscles):
    ex = {"x": fake("x", ("lats_latissimus", 0.01))}
    assert as_tuples(template_service.top_muscles([item("x", 1)], ex, muscles)) == [("lats", 4)]


def test_ac6_ties_follow_muscles_json_order_not_exercise_order(muscles):
    # delts comes before triceps and chest before delts in muscles.json
    ex = {"t": fake("t", ("triceps_long", 1.0)), "d": fake("d", ("delts_front", 1.0)),
          "c": fake("c", ("chest_sternal", 1.0)), "b": fake("b", ("biceps_short", 1.0))}
    result = template_service.top_muscles(
        [item("b"), item("t"), item("d"), item("c")], ex, muscles)
    assert [r["muscle_id"] for r in result] == ["chest", "delts", "triceps"]
    assert all(r["level"] == 4 for r in result)


def test_ac6_does_not_change_its_inputs(library, muscles):
    items = [item("barbell_bench_press", 4)]
    before = (copy.deepcopy(items), copy.deepcopy(library))
    assert template_service.top_muscles(items, library, muscles), "bench press should give chips"
    assert (items, library) == before


# --- AC-3: clean_input ----------------------------------------------------------------------

def good_body(**changes) -> dict:
    body = {
        "id": str(uuid.uuid4()),
        "name": "Push 1",
        "focus": "tricep focus",
        "exercises": [
            {"exercise_id": "barbell_bench_press", "target_sets": 4, "target_reps": 6, "rest_s": 180},
            {"exercise_id": "triceps_pushdown", "target_sets": 3, "target_reps": 12, "rest_s": 90,
             "superset_group": "a"},
            {"exercise_id": "plank", "target_sets": 3, "rest_s": 90, "superset_group": "a"},
        ],
    }
    body.update(changes)
    return body


def one_exercise(**changes) -> dict:
    ex = {"exercise_id": "barbell_bench_press", "target_sets": 4, "target_reps": 6, "rest_s": 180}
    ex.update(changes)
    return good_body(exercises=[ex])


def assert_bad_request(body, library):
    with pytest.raises(ApiError) as caught:
        template_service.clean_input(body, library)
    assert caught.value.code == "bad_request"
    assert caught.value.status == 400


def test_ac3_a_good_body_passes_and_keeps_its_fields(library):
    cleaned = template_service.clean_input(good_body(), library)
    assert cleaned["name"] == "Push 1"
    assert cleaned["focus"] == "tricep focus"
    assert [e["exercise_id"] for e in cleaned["exercises"]] == [
        "barbell_bench_press", "triceps_pushdown", "plank"]
    assert [e["target_sets"] for e in cleaned["exercises"]] == [4, 3, 3]
    assert [e["rest_s"] for e in cleaned["exercises"]] == [180, 90, 90]
    assert [e.get("target_reps") for e in cleaned["exercises"]] == [6, 12, None]
    assert [e.get("superset_group") for e in cleaned["exercises"]] == [None, "a", "a"]


@pytest.mark.parametrize("bad_id", [
    "", "not-a-uuid", "3C9D7E1A-5B2F-4C8D-A6E4-7F8A9B0C1D2E", "3c9d7e1a5b2f4c8da6e47f8a9b0c1d2e",
    "3c9d7e1a-5b2f-4c8d-a6e4-7f8a9b0c1d2", None, 42])
def test_ac3_id_must_be_a_lowercase_uuid(library, bad_id):
    assert_bad_request(good_body(id=bad_id), library)


def test_ac3_missing_id_is_bad_request(library):
    body = good_body()
    del body["id"]
    assert_bad_request(body, library)


@pytest.mark.parametrize("name", ["", "   ", "\t\n", None, 7, "x" * 61, " " + "x" * 61])
def test_ac3_bad_names(library, name):
    assert_bad_request(good_body(name=name), library)


def test_ac3_missing_name_is_bad_request(library):
    body = good_body()
    del body["name"]
    assert_bad_request(body, library)


@pytest.mark.parametrize("name,expected", [("x", "x"), ("x" * 60, "x" * 60),
                                            ("  Push 1  ", "Push 1"), (" " + "x" * 60 + " ", "x" * 60)])
def test_ac3_good_names_are_trimmed(library, name, expected):
    assert template_service.clean_input(good_body(name=name), library)["name"] == expected


def test_ac3_focus_over_60_is_bad_request(library):
    assert_bad_request(good_body(focus="f" * 61), library)


@pytest.mark.parametrize("focus,expected", [("f" * 60, "f" * 60), ("  legs ", "legs"),
                                             ("", None), ("   ", None), (None, None)])
def test_ac3_good_focus_is_trimmed_and_empty_is_null(library, focus, expected):
    assert template_service.clean_input(good_body(focus=focus), library)["focus"] == expected


def test_ac3_left_out_focus_is_null(library):
    body = good_body()
    del body["focus"]
    assert template_service.clean_input(body, library)["focus"] is None


def test_ac3_empty_exercises_is_bad_request(library):
    assert_bad_request(good_body(exercises=[]), library)


def test_ac3_missing_exercises_is_bad_request(library):
    body = good_body()
    del body["exercises"]
    assert_bad_request(body, library)


def test_ac3_thirty_exercises_pass_and_thirty_one_do_not(library):
    row = {"exercise_id": "barbell_bench_press", "target_sets": 1, "target_reps": 5, "rest_s": 60}
    assert len(template_service.clean_input(good_body(exercises=[row] * 30), library)["exercises"]) == 30
    assert_bad_request(good_body(exercises=[row] * 31), library)


def test_ac3_unknown_exercise_id_is_bad_request(library):
    assert_bad_request(one_exercise(exercise_id="no_such_exercise"), library)


@pytest.mark.parametrize("sets", [0, -1, 21, 100, None, "4", 2.5])
def test_ac3_bad_target_sets(library, sets):
    assert_bad_request(one_exercise(target_sets=sets), library)


@pytest.mark.parametrize("sets", [1, 20])
def test_ac3_target_sets_boundaries_pass(library, sets):
    cleaned = template_service.clean_input(one_exercise(target_sets=sets), library)
    assert cleaned["exercises"][0]["target_sets"] == sets


@pytest.mark.parametrize("reps", [0, -1, 101, "6", 6.5])
def test_ac3_bad_target_reps(library, reps):
    assert_bad_request(one_exercise(target_reps=reps), library)


@pytest.mark.parametrize("reps", [1, 100, None])
def test_ac3_target_reps_boundaries_and_null_pass(library, reps):
    cleaned = template_service.clean_input(one_exercise(target_reps=reps), library)
    assert cleaned["exercises"][0].get("target_reps") == reps


@pytest.mark.parametrize("rest", [-1, 601, None, "90", 90.5])
def test_ac3_bad_rest(library, rest):
    assert_bad_request(one_exercise(rest_s=rest), library)


@pytest.mark.parametrize("rest", [0, 600])
def test_ac3_rest_boundaries_pass(library, rest):
    cleaned = template_service.clean_input(one_exercise(rest_s=rest), library)
    assert cleaned["exercises"][0]["rest_s"] == rest


def test_ac3_a_bad_row_among_good_rows_is_bad_request(library):
    rows = good_body()["exercises"] + [{"exercise_id": "plank", "target_sets": 0, "rest_s": 60}]
    assert_bad_request(good_body(exercises=rows), library)


# --- AC-7: next_last_done -------------------------------------------------------------------

def stored(last_done_at) -> dict:
    return {"id": str(uuid.uuid4()), "name": "Push 1", "focus": None,
            "exercises": [item("barbell_bench_press", 4)], "last_done_at": last_done_at,
            "created_at": T0 - timedelta(days=30)}


def test_ac7_empty_last_done_is_set():
    result = template_service.next_last_done(stored(None), T0)
    assert result is not None
    assert result["last_done_at"] == T0


def test_ac7_an_older_last_done_moves_forward():
    result = template_service.next_last_done(stored(T0 - timedelta(days=3)), T0)
    assert result is not None
    assert result["last_done_at"] == T0


def test_ac7_last_done_only_moves_forward():
    assert template_service.next_last_done(stored(T0 - timedelta(seconds=1)), T0) is not None
    assert template_service.next_last_done(stored(T0), T0) is None
    assert template_service.next_last_done(stored(T0 + timedelta(seconds=1)), T0) is None


def test_ac7_one_second_newer_moves_forward():
    result = template_service.next_last_done(stored(T0 - timedelta(seconds=1)), T0)
    assert result is not None and result["last_done_at"] == T0


def test_ac7_other_fields_are_kept():
    old = stored(None)
    result = template_service.next_last_done(old, T0)
    assert result is not None
    assert {k: v for k, v in result.items() if k != "last_done_at"} == \
           {k: v for k, v in old.items() if k != "last_done_at"}


def test_ac7_the_input_is_not_changed():
    old = stored(None)
    assert template_service.next_last_done(old, T0) is not None
    assert old["last_done_at"] is None


def test_ac7_applying_the_result_again_is_no_change():
    first = template_service.next_last_done(stored(None), T0)
    assert first is not None
    assert template_service.next_last_done(first, T0) is None
