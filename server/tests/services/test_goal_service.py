"""Goal rules (specs/goals.llm.md, AC-1 to AC-9 at the service level).

Pure logic. `epley`, `strength_progress` and `frequency_progress` take plain dicts. The
functions that read and write goals run against an in-memory stand-in for `models`, so
there is no database and no Flask.
"""
from __future__ import annotations

import copy
import uuid
from datetime import date, datetime, timedelta, timezone

import pytest

import models
from services import goal_service
from services.errors import ApiError

TODAY = date(2026, 11, 4)  # a Wednesday; its week is Mon 2026-11-02 .. Sun 2026-11-08
BENCH = "barbell_bench_press"
T0 = datetime(2026, 10, 20, 18, 0, tzinfo=timezone.utc)

LIBRARY = {
    "barbell_bench_press": {"id": "barbell_bench_press", "name": "Bench Press", "load_type": "barbell"},
    "deadlift": {"id": "deadlift", "name": "Deadlift", "load_type": "barbell"},
    "push_up": {"id": "push_up", "name": "Push-up", "load_type": "bodyweight"},
    "plank": {"id": "plank", "name": "Plank", "load_type": "timed"},
}


def new_id() -> str:
    return str(uuid.uuid4())


def stored(**changes) -> dict:
    goal = {"id": new_id(), "type": "strength", "exercise_id": BENCH, "target": 100.0,
            "start_date": "2026-10-20", "deadline": None, "created_at": T0}
    goal.update(changes)
    return goal


def lift(weight_kg, reps, local_date="2026-10-25", set_type="working", exercise_id=BENCH, **extra) -> dict:
    return {"id": new_id(), "exercise_id": exercise_id, "order": 1, "set_type": set_type,
            "weight_kg": weight_kg, "reps": reps, "local_date": local_date, **extra}


def e1rm(weight_kg, reps) -> float:
    return weight_kg * (1 + reps / 30)


def assert_error(caught, code, status):
    assert caught.value.code == code
    assert caught.value.status == status


# --- AC-5: epley and strength progress ------------------------------------------------------

@pytest.mark.parametrize("weight,reps,expected", [
    (100, 1, 103.33333333), (100, 10, 133.33333333), (60, 5, 70.0), (82.5, 3, 90.75),
    (71.4408, 5, 83.3476)])
def test_ac5_epley_formula(weight, reps, expected):
    assert goal_service.epley(weight, reps) == pytest.approx(expected, rel=1e-6)


def test_ac5_current_is_the_highest_estimate_not_the_heaviest_or_latest():
    goal = stored(target=200.0)
    sets = [lift(100, 1, "2026-10-21"), lift(80, 10, "2026-10-22"), lift(90, 3, "2026-10-23")]
    # 103.33, 106.67, 99.0
    progress = goal_service.strength_progress(goal, sets)
    assert progress["current"] == pytest.approx(e1rm(80, 10))


def test_ac5_percent_and_remaining_follow_current_and_target():
    progress = goal_service.strength_progress(stored(target=100.0), [lift(70, 5)])
    assert progress["current"] == pytest.approx(81.6666667)
    assert progress["percent"] == pytest.approx(81.6666667)
    assert progress["remaining"] == pytest.approx(100.0 - 81.6666667)


def test_ac5_percent_is_not_rounded():
    progress = goal_service.strength_progress(stored(target=120.0), [lift(70, 5)])
    assert progress["percent"] == pytest.approx(70 * (1 + 5 / 30) / 120 * 100)


def test_ac5_no_sets_gives_nulls_not_zero():
    progress = goal_service.strength_progress(stored(), [])
    assert progress["current"] is None
    assert progress["percent"] is None
    assert progress["remaining"] is None
    assert progress["achieved_on"] is None


@pytest.mark.parametrize("bad_set", [
    lift(100, 5, set_type="warmup"),
    lift(100, 5, set_type="dropset"),
    lift(0, 5),
    lift(None, 5),
    lift(-20, 5),
    lift(100, 0),
    lift(100, 11),
    lift(100, 30),
    lift(100, None),
    lift(100, 5, exercise_id="deadlift"),
], ids=["warmup", "dropset", "zero_weight", "no_weight", "negative_weight", "zero_reps",
        "eleven_reps", "thirty_reps", "no_reps", "other_exercise"])
def test_ac5_ineligible_sets_are_ignored(bad_set):
    baseline = lift(10, 1, "2026-10-21")
    progress = goal_service.strength_progress(stored(), [bad_set, baseline])
    assert progress["current"] == pytest.approx(e1rm(10, 1))


def test_ac5_an_ineligible_set_does_not_beat_an_eligible_one():
    sets = [lift(60, 5), lift(200, 5, set_type="warmup"), lift(300, 5, exercise_id="deadlift"),
            lift(150, 11)]
    assert goal_service.strength_progress(stored(target=500.0), sets)["current"] == pytest.approx(70.0)


@pytest.mark.parametrize("reps", [1, 10])
def test_ac5_rep_boundaries_one_and_ten_are_eligible(reps):
    progress = goal_service.strength_progress(stored(target=500.0), [lift(100, reps)])
    assert progress["current"] == pytest.approx(e1rm(100, reps))


@pytest.mark.parametrize("set_type", ["working", "failure"])
def test_ac5_working_and_failure_sets_count(set_type):
    progress = goal_service.strength_progress(stored(target=500.0), [lift(100, 5, set_type=set_type)])
    assert progress["current"] == pytest.approx(e1rm(100, 5))


def test_ac5_a_tiny_positive_weight_is_eligible():
    progress = goal_service.strength_progress(stored(target=500.0), [lift(0.5, 5)])
    assert progress["current"] == pytest.approx(e1rm(0.5, 5))


def test_ac5_sets_before_the_start_date_count_too():
    goal = stored(start_date="2026-11-01", target=500.0)
    progress = goal_service.strength_progress(goal, [lift(100, 5, "2026-01-01")])
    assert progress["current"] == pytest.approx(e1rm(100, 5))


def test_ac5_does_not_change_its_inputs():
    goal, sets = stored(), [lift(70, 5), lift(60, 8)]
    before = copy.deepcopy((goal, sets))
    assert goal_service.strength_progress(goal, sets)["current"] is not None
    assert (goal, sets) == before


# --- AC-6: completion -----------------------------------------------------------------------

def test_ac6_reaching_the_target_gives_100_percent_zero_remaining():
    progress = goal_service.strength_progress(stored(target=100.0), [lift(100, 5, "2026-10-28")])
    assert progress["current"] == pytest.approx(e1rm(100, 5))
    assert progress["percent"] == 100
    assert progress["remaining"] == 0
    assert progress["achieved_on"] == "2026-10-28"


def test_ac6_current_exactly_at_the_target_is_achieved():
    progress = goal_service.strength_progress(stored(target=70.0), [lift(60, 5, "2026-10-26")])
    assert progress["current"] == pytest.approx(70.0)
    assert progress["percent"] == 100
    assert progress["remaining"] == 0
    assert progress["achieved_on"] == "2026-10-26"


def test_ac6_just_below_the_target_is_not_achieved():
    progress = goal_service.strength_progress(stored(target=70.01), [lift(60, 5)])
    assert progress["achieved_on"] is None
    assert progress["percent"] < 100
    assert progress["remaining"] > 0


def test_ac6_achieved_on_is_the_first_set_that_reached_it_not_the_best():
    sets = [lift(110, 5, "2026-11-02"), lift(100, 5, "2026-10-28"), lift(120, 5, "2026-11-03")]
    progress = goal_service.strength_progress(stored(target=100.0), sets)
    assert progress["achieved_on"] == "2026-10-28"
    assert progress["current"] == pytest.approx(e1rm(120, 5))


def test_ac6_achieved_on_skips_earlier_sets_that_fell_short():
    sets = [lift(60, 5, "2026-10-21"), lift(100, 5, "2026-11-01")]
    assert goal_service.strength_progress(stored(target=100.0), sets)["achieved_on"] == "2026-11-01"


def test_ac6_percent_never_goes_above_100_and_remaining_never_below_0():
    progress = goal_service.strength_progress(stored(target=50.0), [lift(200, 5)])
    assert progress["percent"] == 100
    assert progress["remaining"] == 0


def test_ac6_an_unmet_goal_has_no_achieved_on():
    progress = goal_service.strength_progress(stored(target=500.0), [lift(100, 5)])
    assert progress["current"] is not None
    assert progress["achieved_on"] is None


# --- AC-7: frequency progress ---------------------------------------------------------------

def day(local_date: str) -> dict:
    return {"id": new_id(), "local_date": local_date}


def freq(target=4, **changes) -> dict:
    return stored(type="frequency", exercise_id=None, target=target, start_date="2026-10-12", **changes)


def test_ac7_counts_workouts_in_the_week_containing_today():
    workouts = [day("2026-11-02"), day("2026-11-04")]
    progress = goal_service.frequency_progress(freq(4), workouts, TODAY)
    assert progress["current"] == 2
    assert progress["percent"] == pytest.approx(50.0)
    assert progress["remaining"] == 2
    assert progress["met_this_week"] is False
    assert progress["week_start"] == "2026-11-02"


def test_ac7_monday_and_sunday_are_inside_the_week():
    workouts = [day("2026-11-02"), day("2026-11-08")]
    assert goal_service.frequency_progress(freq(4), workouts, TODAY)["current"] == 2


def test_ac7_the_sunday_before_and_the_monday_after_are_outside():
    workouts = [day("2026-11-01"), day("2026-11-09"), day("2026-10-27")]
    assert goal_service.frequency_progress(freq(4), workouts, TODAY)["current"] == 0


@pytest.mark.parametrize("today", [date(2026, 11, 2), date(2026, 11, 8)])
def test_ac7_week_start_is_the_monday_whichever_day_today_is(today):
    progress = goal_service.frequency_progress(freq(4), [], today)
    assert progress["week_start"] == "2026-11-02"


def test_ac7_a_new_week_starts_again_at_zero_on_monday():
    workouts = [day("2026-11-02"), day("2026-11-03"), day("2026-11-05"), day("2026-11-06")]
    progress = goal_service.frequency_progress(freq(4), workouts, date(2026, 11, 9))
    assert progress["week_start"] == "2026-11-09"
    assert progress["current"] == 0
    assert progress["percent"] == 0
    assert progress["remaining"] == 4
    assert progress["met_this_week"] is False


def test_ac7_two_workouts_on_one_day_count_twice_a_workout_once():
    workouts = [day("2026-11-03"), day("2026-11-03")]
    assert goal_service.frequency_progress(freq(4), workouts, TODAY)["current"] == 2


def test_ac7_no_workouts_is_zero_not_null():
    progress = goal_service.frequency_progress(freq(3), [], TODAY)
    assert progress["current"] == 0
    assert progress["percent"] == 0
    assert progress["remaining"] == 3
    assert progress["met_this_week"] is False


def test_ac7_meeting_the_target_exactly():
    workouts = [day("2026-11-02"), day("2026-11-03"), day("2026-11-04")]
    progress = goal_service.frequency_progress(freq(3), workouts, TODAY)
    assert progress["percent"] == 100
    assert progress["remaining"] == 0
    assert progress["met_this_week"] is True


def test_ac7_one_short_of_the_target_is_not_met():
    workouts = [day("2026-11-02"), day("2026-11-03")]
    assert goal_service.frequency_progress(freq(3), workouts, TODAY)["met_this_week"] is False


def test_ac7_exceeding_the_target_is_capped_at_100_percent_and_zero_remaining():
    workouts = [day("2026-11-02"), day("2026-11-03"), day("2026-11-04"), day("2026-11-05")]
    progress = goal_service.frequency_progress(freq(2), workouts, TODAY)
    assert progress["current"] == 4
    assert progress["percent"] == 100
    assert progress["remaining"] == 0
    assert progress["met_this_week"] is True


@pytest.mark.parametrize("target,expected", [(1, 100), (7, 100 / 7)])
def test_ac7_target_boundaries(target, expected):
    progress = goal_service.frequency_progress(freq(target), [day("2026-11-03")], TODAY)
    assert progress["percent"] == pytest.approx(expected)


def test_ac7_the_week_crosses_a_month_and_year_boundary():
    workouts = [day("2026-12-28"), day("2027-01-03"), day("2027-01-04")]
    progress = goal_service.frequency_progress(freq(3), workouts, date(2026, 12, 31))
    assert progress["week_start"] == "2026-12-28"
    assert progress["current"] == 2


def test_ac7_strength_only_fields_stay_null():
    progress = goal_service.frequency_progress(freq(3), [day("2026-11-03")], TODAY)
    assert progress["current"] == 1
    assert progress["achieved_on"] is None


def test_ac7_does_not_change_its_inputs():
    goal, workouts = freq(), [day("2026-11-03")]
    before = copy.deepcopy((goal, workouts))
    assert goal_service.frequency_progress(goal, workouts, TODAY)["current"] == 1
    assert (goal, workouts) == before


# --- An in-memory stand-in for models, for the functions that read and write goals ----------

class Store:
    def __init__(self):
        self.goals: dict[tuple[str, str], dict] = {}
        self.sets: dict[str, list[dict]] = {}
        self.workouts: dict[str, list[str]] = {}
        self.puts = 0

    def add_goal(self, user_id, **changes) -> dict:
        goal = stored(**changes)
        self.goals[(user_id, goal["id"])] = goal
        return goal

    def add_sets(self, user_id, *sets):
        self.sets.setdefault(user_id, []).extend(sets)

    def add_workouts(self, user_id, *dates):
        self.workouts.setdefault(user_id, []).extend(dates)

    def ids(self, user_id) -> list[str]:
        return [g for (u, g) in self.goals if u == user_id]


@pytest.fixture
def store(monkeypatch) -> Store:
    s = Store()

    def put_goal(user_id, data):
        s.puts += 1
        s.goals[(user_id, data["id"])] = copy.deepcopy(data)

    monkeypatch.setattr(models, "put_goal", put_goal)
    monkeypatch.setattr(models, "get_goal", lambda user_id, goal_id: copy.deepcopy(s.goals.get((user_id, goal_id))))
    monkeypatch.setattr(models, "user_goals",
                        lambda user_id: [copy.deepcopy(g) for (u, _), g in s.goals.items() if u == user_id])
    monkeypatch.setattr(models, "delete_goal", lambda user_id, goal_id: s.goals.pop((user_id, goal_id), None) and None)
    monkeypatch.setattr(models, "user_sets",
                        lambda user_id, exercise_ids: [copy.deepcopy(x) for x in s.sets.get(user_id, [])
                                                       if x["exercise_id"] in set(exercise_ids)])
    monkeypatch.setattr(models, "user_workout_dates", lambda user_id: list(s.workouts.get(user_id, [])))
    monkeypatch.setattr(models, "get_exercise", lambda slug: copy.deepcopy(LIBRARY.get(slug)))
    monkeypatch.setattr(models, "get_exercises",
                        lambda slugs: {k: copy.deepcopy(v) for k, v in LIBRARY.items() if k in set(slugs)})
    monkeypatch.setattr(models, "all_exercises", lambda: [copy.deepcopy(v) for v in LIBRARY.values()])
    return s


def body(**changes) -> dict:
    data = {"id": new_id(), "type": "strength", "exercise_id": BENCH, "target": 100.0,
            "start_date": "2026-10-20", "deadline": "2026-12-15"}
    data.update(changes)
    return data


def freq_body(**changes) -> dict:
    data = {"id": new_id(), "type": "frequency", "target": 4, "start_date": "2026-10-12"}
    data.update(changes)
    return data


GOAL_KEYS = {"id", "type", "exercise_id", "exercise_name", "target", "start_date", "deadline",
             "created_at", "status", "progress"}
PROGRESS_KEYS = {"current", "percent", "remaining", "achieved_on", "met_this_week", "week_start"}


# --- AC-1: create ---------------------------------------------------------------------------

def test_ac1_create_returns_the_full_goal_and_created_true(store):
    data = body()
    goal, created = goal_service.create_goal("u1", data, TODAY)
    assert created is True
    assert set(goal) == GOAL_KEYS
    assert set(goal["progress"]) == PROGRESS_KEYS
    assert goal["id"] == data["id"]
    assert goal["type"] == "strength"
    assert goal["exercise_id"] == BENCH
    assert goal["exercise_name"] == "Bench Press"
    assert goal["target"] == 100.0
    assert goal["start_date"] == "2026-10-20"
    assert goal["deadline"] == "2026-12-15"
    assert goal["status"] == "active"


def test_ac1_create_stores_one_goal_under_this_user(store):
    data = body()
    goal_service.create_goal("u1", data, TODAY)
    assert store.ids("u1") == [data["id"]]
    assert store.ids("u2") == []


def test_ac1_a_new_strength_goal_without_sets_has_null_progress(store):
    goal, _ = goal_service.create_goal("u1", body(), TODAY)
    assert goal["progress"]["current"] is None
    assert goal["progress"]["percent"] is None
    assert goal["progress"]["remaining"] is None


def test_ac1_target_is_stored_at_full_precision(store):
    goal, _ = goal_service.create_goal("u1", body(target=102.05828325), TODAY)
    assert goal["target"] == 102.05828325
    assert store.goals[("u1", goal["id"])]["target"] == 102.05828325


def test_ac1_computed_fields_are_not_stored(store):
    goal, _ = goal_service.create_goal("u1", body(), TODAY)
    saved = store.goals[("u1", goal["id"])]
    for field in ("progress", "status", "exercise_name"):
        assert field not in saved


def test_ac1_a_frequency_goal_has_null_exercise_and_deadline(store):
    goal, created = goal_service.create_goal("u1", freq_body(), TODAY)
    assert created is True
    assert goal["exercise_id"] is None
    assert goal["exercise_name"] is None
    assert goal["deadline"] is None
    assert goal["target"] == 4
    assert goal["progress"]["week_start"] == "2026-11-02"


def test_ac1_a_strength_goal_without_a_deadline_has_null_deadline(store):
    goal, _ = goal_service.create_goal("u1", body(deadline=None), TODAY)
    assert goal["deadline"] is None
    data = body()
    del data["deadline"]
    goal, _ = goal_service.create_goal("u1", data, TODAY)
    assert goal["deadline"] is None


def test_ac1_same_id_again_returns_the_stored_goal_and_changes_nothing(store):
    data = body()
    first, _ = goal_service.create_goal("u1", data, TODAY)
    puts = store.puts
    again, created = goal_service.create_goal("u1", data, TODAY)
    assert created is False
    assert again["id"] == first["id"]
    assert again["target"] == first["target"]
    assert store.puts == puts
    assert len(store.ids("u1")) == 1


def test_ac1_same_id_with_a_different_body_returns_the_stored_goal(store):
    data = body(target=100.0)
    goal_service.create_goal("u1", data, TODAY)
    again, created = goal_service.create_goal("u1", {**data, "target": 150.0}, TODAY)
    assert created is False
    assert again["target"] == 100.0
    assert store.goals[("u1", data["id"])]["target"] == 100.0


def test_ac1_a_retry_at_the_limit_is_not_a_conflict(store):
    first = body()
    goal_service.create_goal("u1", first, TODAY)
    goal_service.create_goal("u1", body(), TODAY)
    goal_service.create_goal("u1", body(), TODAY)
    again, created = goal_service.create_goal("u1", first, TODAY)
    assert created is False
    assert again["id"] == first["id"]


# --- AC-2: bad input ------------------------------------------------------------------------

BAD_STRENGTH = {
    "id_not_a_uuid": {"id": "nope"},
    "id_uppercase": {"id": "7B1E4C2A-9D3F-4E8A-B5C6-1A2B3C4D5E6F"},
    "id_missing_dashes": {"id": "7b1e4c2a9d3f4e8ab5c61a2b3c4d5e6f"},
    "id_null": {"id": None},
    "id_number": {"id": 7},
    "type_unknown": {"type": "volume"},
    "type_null": {"type": None},
    "type_uppercase": {"type": "Strength"},
    "exercise_unknown": {"exercise_id": "no_such_exercise"},
    "exercise_null": {"exercise_id": None},
    "exercise_bodyweight": {"exercise_id": "push_up"},
    "exercise_timed": {"exercise_id": "plank"},
    "target_zero": {"target": 0},
    "target_negative": {"target": -5},
    "target_string": {"target": "100"},
    "target_null": {"target": None},
    "target_bool": {"target": True},
    "target_nan": {"target": float("nan")},
    "target_inf": {"target": float("inf")},
    "target_over_max": {"target": 1500.01},
    "start_not_a_date": {"start_date": "20 Oct"},
    "start_slashes": {"start_date": "2026/10/20"},
    "start_not_real": {"start_date": "2026-02-30"},
    "start_null": {"start_date": None},
    "deadline_not_a_date": {"deadline": "soon"},
    "deadline_not_real": {"deadline": "2026-13-01"},
    "deadline_before_start": {"deadline": "2026-10-19"},
    "deadline_over_five_years": {"deadline": "2031-10-21"},
}


@pytest.mark.parametrize("changes", BAD_STRENGTH.values(), ids=BAD_STRENGTH.keys())
def test_ac2_bad_strength_body_is_400_and_saves_nothing(store, changes):
    with pytest.raises(ApiError) as caught:
        goal_service.create_goal("u1", body(**changes), TODAY)
    assert_error(caught, "bad_request", 400)
    assert store.ids("u1") == []


@pytest.mark.parametrize("field", ["id", "type", "start_date", "target", "exercise_id"])
def test_ac2_a_missing_required_strength_field_is_400(store, field):
    data = body()
    del data[field]
    with pytest.raises(ApiError) as caught:
        goal_service.create_goal("u1", data, TODAY)
    assert_error(caught, "bad_request", 400)
    assert store.ids("u1") == []


BAD_FREQUENCY = {
    "target_zero": {"target": 0},
    "target_eight": {"target": 8},
    "target_negative": {"target": -1},
    "target_fraction": {"target": 2.5},
    "target_string": {"target": "3"},
    "target_nan": {"target": float("nan")},
    "target_inf": {"target": float("inf")},
    "target_null": {"target": None},
    "has_exercise": {"exercise_id": "barbell_bench_press"},
    "has_deadline": {"deadline": "2026-12-15"},
    "start_not_a_date": {"start_date": "yesterday"},
}


@pytest.mark.parametrize("changes", BAD_FREQUENCY.values(), ids=BAD_FREQUENCY.keys())
def test_ac2_bad_frequency_body_is_400_and_saves_nothing(store, changes):
    with pytest.raises(ApiError) as caught:
        goal_service.create_goal("u1", freq_body(**changes), TODAY)
    assert_error(caught, "bad_request", 400)
    assert store.ids("u1") == []


@pytest.mark.parametrize("target", [1, 7])
def test_ac2_frequency_target_boundaries_pass(store, target):
    goal, created = goal_service.create_goal("u1", freq_body(target=target), TODAY)
    assert created is True
    assert goal["target"] == target


def test_ac2_a_whole_number_sent_as_a_float_is_accepted_for_frequency(store):
    goal, created = goal_service.create_goal("u1", freq_body(target=3.0), TODAY)
    assert created is True
    assert goal["target"] == 3


def test_ac2_frequency_exercise_and_deadline_may_be_null(store):
    _, created = goal_service.create_goal("u1", freq_body(exercise_id=None, deadline=None), TODAY)
    assert created is True


@pytest.mark.parametrize("changes", [
    {"target": 0.001}, {"target": 1500}, {"deadline": "2026-10-20"}, {"deadline": "2031-10-20"},
    {"deadline": None}], ids=["tiny", "max", "deadline_on_start", "deadline_five_years", "no_deadline"])
def test_ac2_strength_boundaries_pass(store, changes):
    _, created = goal_service.create_goal("u1", body(**changes), TODAY)
    assert created is True


@pytest.mark.parametrize("data", [None, [], "goal", 5])
def test_ac2_a_body_that_is_not_an_object_is_400(store, data):
    with pytest.raises(ApiError) as caught:
        goal_service.create_goal("u1", data, TODAY)
    assert_error(caught, "bad_request", 400)


# --- AC-3: the limit ------------------------------------------------------------------------

def test_ac3_a_fourth_active_goal_is_409_and_saves_nothing(store):
    for _ in range(3):
        goal_service.create_goal("u1", body(), TODAY)
    with pytest.raises(ApiError) as caught:
        goal_service.create_goal("u1", body(), TODAY)
    assert_error(caught, "conflict", 409)
    assert len(store.ids("u1")) == 3


def test_ac3_the_third_goal_is_allowed(store):
    goal_service.create_goal("u1", body(), TODAY)
    goal_service.create_goal("u1", body(), TODAY)
    _, created = goal_service.create_goal("u1", body(), TODAY)
    assert created is True


def test_ac3_a_frequency_goal_counts_toward_the_limit(store):
    goal_service.create_goal("u1", freq_body(), TODAY)
    goal_service.create_goal("u1", body(), TODAY)
    goal_service.create_goal("u1", body(), TODAY)
    with pytest.raises(ApiError) as caught:
        goal_service.create_goal("u1", body(), TODAY)
    assert_error(caught, "conflict", 409)


def test_ac3_completed_strength_goals_do_not_count(store):
    store.add_sets("u1", lift(200, 5))
    store.add_goal("u1", target=100.0)  # completed
    store.add_goal("u1", target=100.0)  # completed
    store.add_goal("u1", target=100.0)  # completed
    for _ in range(3):
        _, created = goal_service.create_goal("u1", body(exercise_id="deadlift"), TODAY)
        assert created is True


def test_ac3_another_users_goals_do_not_count(store):
    for _ in range(3):
        store.add_goal("u2")
    _, created = goal_service.create_goal("u1", body(), TODAY)
    assert created is True


def test_ac3_a_second_frequency_goal_is_409(store):
    goal_service.create_goal("u1", freq_body(), TODAY)
    with pytest.raises(ApiError) as caught:
        goal_service.create_goal("u1", freq_body(target=2), TODAY)
    assert_error(caught, "conflict", 409)
    assert len(store.ids("u1")) == 1


def test_ac3_invalid_input_is_400_even_at_the_limit(store):
    for _ in range(3):
        goal_service.create_goal("u1", body(), TODAY)
    with pytest.raises(ApiError) as caught:
        goal_service.create_goal("u1", body(target=-1), TODAY)
    assert_error(caught, "bad_request", 400)


def test_ac3_strength_goals_may_repeat_an_exercise(store):
    goal_service.create_goal("u1", body(target=100.0), TODAY)
    _, created = goal_service.create_goal("u1", body(target=120.0), TODAY)
    assert created is True


# --- AC-4 and AC-6: listing and status ------------------------------------------------------

def test_ac4_a_new_user_has_no_goals(store):
    assert goal_service.list_goals("u1", TODAY) == []


def test_ac4_only_this_users_goals(store):
    mine = store.add_goal("u1")
    store.add_goal("u2")
    assert [g["id"] for g in goal_service.list_goals("u1", TODAY)] == [mine["id"]]


def test_ac4_each_goal_has_the_api_shape_and_a_status(store):
    store.add_goal("u1")
    store.add_goal("u1", type="frequency", exercise_id=None, target=3)
    goals = goal_service.list_goals("u1", TODAY)
    assert len(goals) == 2
    for goal in goals:
        assert set(goal) == GOAL_KEYS
        assert set(goal["progress"]) == PROGRESS_KEYS
        assert goal["status"] in ("active", "completed")


def test_ac4_exercise_name_comes_from_the_library(store):
    store.add_goal("u1", exercise_id="deadlift")
    assert goal_service.list_goals("u1", TODAY)[0]["exercise_name"] == "Deadlift"


def test_ac4_active_goals_are_oldest_created_first(store):
    c = store.add_goal("u1", created_at=T0 + timedelta(days=3))
    a = store.add_goal("u1", created_at=T0)
    b = store.add_goal("u1", created_at=T0 + timedelta(days=1))
    assert [g["id"] for g in goal_service.list_goals("u1", TODAY)] == [a["id"], b["id"], c["id"]]


def test_ac4_completed_goals_follow_active_ones_newest_achieved_first(store):
    store.add_sets("u1",
                   lift(100, 5, "2026-10-25", exercise_id="barbell_bench_press"),
                   lift(100, 5, "2026-11-01", exercise_id="deadlift"))
    old_done = store.add_goal("u1", exercise_id="barbell_bench_press", target=100.0, created_at=T0)
    new_done = store.add_goal("u1", exercise_id="deadlift", target=100.0, created_at=T0 + timedelta(days=1))
    active = store.add_goal("u1", exercise_id="barbell_bench_press", target=900.0, created_at=T0 + timedelta(days=2))
    listed = goal_service.list_goals("u1", TODAY)
    assert [g["id"] for g in listed] == [active["id"], new_done["id"], old_done["id"]]
    assert [g["status"] for g in listed] == ["active", "completed", "completed"]


def test_ac6_a_goal_whose_current_reaches_the_target_is_completed(store):
    store.add_sets("u1", lift(100, 5, "2026-10-28"))
    store.add_goal("u1", target=100.0)
    goal = goal_service.list_goals("u1", TODAY)[0]
    assert goal["status"] == "completed"
    assert goal["progress"]["percent"] == 100
    assert goal["progress"]["remaining"] == 0
    assert goal["progress"]["achieved_on"] == "2026-10-28"


def test_ac6_a_goal_below_the_target_is_active(store):
    store.add_sets("u1", lift(60, 5))
    store.add_goal("u1", target=100.0)
    goal = goal_service.list_goals("u1", TODAY)[0]
    assert goal["status"] == "active"
    assert goal["progress"]["achieved_on"] is None


def test_ac6_a_goal_with_no_sets_is_active_with_null_progress(store):
    store.add_goal("u1")
    goal = goal_service.list_goals("u1", TODAY)[0]
    assert goal["status"] == "active"
    assert goal["progress"]["current"] is None


def test_ac6_completion_is_not_stored(store):
    store.add_sets("u1", lift(200, 5))
    saved = store.add_goal("u1", target=100.0)
    assert goal_service.list_goals("u1", TODAY)[0]["status"] == "completed"
    assert store.goals[("u1", saved["id"])] == saved


def test_ac6_an_unmet_goal_with_a_passed_deadline_stays_active(store):
    store.add_sets("u1", lift(60, 5))
    store.add_goal("u1", target=100.0, deadline="2026-10-31")  # deadline passed relative to TODAY
    goal = goal_service.list_goals("u1", TODAY)[0]
    assert goal["status"] == "active"


def test_ac6_other_users_sets_do_not_count(store):
    store.add_sets("u2", lift(300, 5))
    store.add_goal("u1", target=100.0)
    assert goal_service.list_goals("u1", TODAY)[0]["status"] == "active"


def test_ac7_a_frequency_goal_is_always_active_and_counts_this_week(store):
    store.add_workouts("u1", "2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-10-30")
    store.add_goal("u1", type="frequency", exercise_id=None, target=2)
    goal = goal_service.list_goals("u1", TODAY)[0]
    assert goal["status"] == "active"
    assert goal["progress"]["current"] == 4
    assert goal["progress"]["percent"] == 100
    assert goal["progress"]["remaining"] == 0
    assert goal["progress"]["met_this_week"] is True
    assert goal["progress"]["week_start"] == "2026-11-02"


def test_ac7_the_today_argument_picks_the_week(store):
    store.add_workouts("u1", "2026-11-02", "2026-11-03")
    store.add_goal("u1", type="frequency", exercise_id=None, target=4)
    assert goal_service.list_goals("u1", date(2026, 11, 8))[0]["progress"]["current"] == 2
    assert goal_service.list_goals("u1", date(2026, 11, 9))[0]["progress"]["current"] == 0


def test_ac7_other_users_workouts_do_not_count(store):
    store.add_workouts("u2", "2026-11-02", "2026-11-03")
    store.add_goal("u1", type="frequency", exercise_id=None, target=4)
    assert goal_service.list_goals("u1", TODAY)[0]["progress"]["current"] == 0


# --- AC-8: update ---------------------------------------------------------------------------

def test_ac8_changes_the_target_and_returns_the_full_goal(store):
    saved = store.add_goal("u1", target=100.0)
    goal = goal_service.update_goal("u1", saved["id"], {"target": 120.0}, TODAY)
    assert set(goal) == GOAL_KEYS
    assert goal["target"] == 120.0
    assert store.goals[("u1", saved["id"])]["target"] == 120.0


def test_ac8_changes_a_strength_deadline_and_can_clear_it(store):
    saved = store.add_goal("u1", deadline="2026-12-15")
    goal = goal_service.update_goal("u1", saved["id"], {"target": 100.0, "deadline": "2027-01-31"}, TODAY)
    assert goal["deadline"] == "2027-01-31"
    goal = goal_service.update_goal("u1", saved["id"], {"target": 100.0, "deadline": None}, TODAY)
    assert goal["deadline"] is None


def test_ac8_other_fields_are_ignored(store):
    saved = store.add_goal("u1", target=100.0, start_date="2026-10-20")
    goal = goal_service.update_goal("u1", saved["id"], {
        "id": new_id(), "type": "frequency", "exercise_id": "deadlift", "start_date": "2026-01-01",
        "target": 110.0, "status": "completed", "progress": {"current": 999}}, TODAY)
    assert goal["id"] == saved["id"]
    assert goal["type"] == "strength"
    assert goal["exercise_id"] == BENCH
    assert goal["start_date"] == "2026-10-20"
    assert goal["status"] == "active"
    assert goal["target"] == 110.0
    assert store.ids("u1") == [saved["id"]]


def test_ac8_a_frequency_goal_target_can_change(store):
    saved = store.add_goal("u1", type="frequency", exercise_id=None, target=3, start_date="2026-10-12")
    goal = goal_service.update_goal("u1", saved["id"], {"target": 5}, TODAY)
    assert goal["target"] == 5


@pytest.mark.parametrize("changes", [
    {"target": 0}, {"target": -1}, {"target": "5"}, {"target": float("nan")},
    {"target": float("inf")}, {"target": 1500.5}, {"target": None},
    {"target": 100.0, "deadline": "tomorrow"},
    {"target": 100.0, "deadline": "2026-10-19"},   # before the stored start_date
    {"target": 100.0, "deadline": "2031-10-21"},   # over five years after the stored start_date
])
def test_ac8_invalid_strength_changes_are_400_and_change_nothing(store, changes):
    saved = store.add_goal("u1", target=100.0, start_date="2026-10-20")
    with pytest.raises(ApiError) as caught:
        goal_service.update_goal("u1", saved["id"], changes, TODAY)
    assert_error(caught, "bad_request", 400)
    assert store.goals[("u1", saved["id"])] == saved


@pytest.mark.parametrize("target", [0, 8, 2.5, "3", float("nan")])
def test_ac8_invalid_frequency_targets_are_400(store, target):
    saved = store.add_goal("u1", type="frequency", exercise_id=None, target=3)
    with pytest.raises(ApiError) as caught:
        goal_service.update_goal("u1", saved["id"], {"target": target}, TODAY)
    assert_error(caught, "bad_request", 400)
    assert store.goals[("u1", saved["id"])] == saved


def test_ac8_an_unknown_id_is_404(store):
    with pytest.raises(ApiError) as caught:
        goal_service.update_goal("u1", new_id(), {"target": 100.0}, TODAY)
    assert_error(caught, "not_found", 404)


def test_ac8_another_users_goal_is_404_and_untouched(store):
    theirs = store.add_goal("u2", target=100.0)
    with pytest.raises(ApiError) as caught:
        goal_service.update_goal("u1", theirs["id"], {"target": 5.0}, TODAY)
    assert_error(caught, "not_found", 404)
    assert store.goals[("u2", theirs["id"])] == theirs


def test_ac6_raising_the_target_above_current_makes_a_completed_goal_active_again(store):
    store.add_sets("u1", lift(100, 5, "2026-10-28"))  # e1rm 116.67
    saved = store.add_goal("u1", target=100.0)
    assert goal_service.list_goals("u1", TODAY)[0]["status"] == "completed"
    goal = goal_service.update_goal("u1", saved["id"], {"target": 130.0}, TODAY)
    assert goal["status"] == "active"
    assert goal["progress"]["achieved_on"] is None
    assert goal["progress"]["percent"] == pytest.approx(e1rm(100, 5) / 130 * 100)
    assert goal_service.list_goals("u1", TODAY)[0]["status"] == "active"


def test_ac6_lowering_the_target_to_current_completes_the_goal(store):
    store.add_sets("u1", lift(60, 5, "2026-10-28"))  # 70.0
    saved = store.add_goal("u1", target=100.0)
    goal = goal_service.update_goal("u1", saved["id"], {"target": 70.0}, TODAY)
    assert goal["status"] == "completed"
    assert goal["progress"]["achieved_on"] == "2026-10-28"


def test_ac3_reopening_a_completed_goal_with_three_active_is_409_and_changes_nothing(store):
    store.add_sets("u1", lift(100, 5, exercise_id="deadlift"))
    done = store.add_goal("u1", exercise_id="deadlift", target=100.0)
    for _ in range(3):
        store.add_goal("u1", exercise_id=BENCH, target=900.0)
    with pytest.raises(ApiError) as caught:
        goal_service.update_goal("u1", done["id"], {"target": 500.0}, TODAY)
    assert_error(caught, "conflict", 409)
    assert store.goals[("u1", done["id"])]["target"] == 100.0


def test_ac3_editing_an_active_goal_at_the_limit_is_fine(store):
    ids = [store.add_goal("u1", target=900.0)["id"] for _ in range(3)]
    goal = goal_service.update_goal("u1", ids[0], {"target": 800.0}, TODAY)
    assert goal["target"] == 800.0


# --- AC-9: delete ---------------------------------------------------------------------------

def test_ac9_deletes_the_goal(store):
    saved = store.add_goal("u1")
    assert goal_service.delete_goal("u1", saved["id"]) is None
    assert store.ids("u1") == []


def test_ac9_deleting_a_missing_goal_is_no_error(store):
    keep = store.add_goal("u1")
    gone = store.add_goal("u1")
    assert goal_service.delete_goal("u1", new_id()) is None
    goal_service.delete_goal("u1", gone["id"])
    assert store.ids("u1") == [keep["id"]]


def test_ac9_deleting_twice_is_no_error(store):
    saved = store.add_goal("u1")
    goal_service.delete_goal("u1", saved["id"])
    assert store.ids("u1") == []
    assert goal_service.delete_goal("u1", saved["id"]) is None


def test_ac9_another_users_goal_is_never_deleted(store):
    theirs = store.add_goal("u2")
    mine = store.add_goal("u1")
    goal_service.delete_goal("u1", theirs["id"])
    goal_service.delete_goal("u1", mine["id"])
    assert store.goals[("u2", theirs["id"])] == theirs
    assert store.ids("u1") == []


def test_ac9_other_goals_of_the_user_stay(store):
    keep = store.add_goal("u1")
    drop = store.add_goal("u1")
    goal_service.delete_goal("u1", drop["id"])
    assert store.ids("u1") == [keep["id"]]


def test_ac9_a_deleted_goal_frees_a_slot(store):
    ids = [goal_service.create_goal("u1", body(), TODAY)[0]["id"] for _ in range(3)]
    goal_service.delete_goal("u1", ids[0])
    _, created = goal_service.create_goal("u1", body(), TODAY)
    assert created is True
