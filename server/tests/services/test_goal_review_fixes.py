"""Review fix S-2: the goal limit checks and the write happen in one transaction.

No database: `models.goal_transaction` is replaced by a recorder, and the goal reads and
writes by an in-memory store that notes whether each call ran inside the transaction.
"""
from __future__ import annotations

import contextlib
import copy
import uuid
from datetime import date, datetime, timezone

import pytest

import models
from services import goal_service
from services.errors import ApiError

TODAY = date(2026, 11, 4)
USER = "u1"
BENCH = "barbell_bench_press"
LIBRARY = {BENCH: {"id": BENCH, "name": "Bench Press", "load_type": "barbell"}}


class Recorder:
    def __init__(self):
        self.goals: dict[str, dict] = {}
        self.sets: list[dict] = []
        self.inside = False
        self.transactions = 0
        self.rolled_back = 0
        self.calls: list[tuple[str, bool]] = []

    @contextlib.contextmanager
    def transaction(self):
        self.transactions += 1
        self.inside = True
        try:
            yield
        except Exception:
            self.rolled_back += 1
            raise
        finally:
            self.inside = False

    def note(self, name):
        self.calls.append((name, self.inside))

    def add(self, **changes) -> dict:
        goal = {"id": str(uuid.uuid4()), "type": "strength", "exercise_id": BENCH, "target": 100.0,
                "start_date": "2026-10-20", "deadline": None,
                "created_at": datetime(2026, 10, 20, tzinfo=timezone.utc)}
        goal.update(changes)
        self.goals[goal["id"]] = goal
        return goal


@pytest.fixture
def rec(monkeypatch) -> Recorder:
    r = Recorder()

    def get_goal(user_id, goal_id):
        r.note("get_goal")
        return copy.deepcopy(r.goals.get(goal_id))

    def user_goals(user_id):
        r.note("user_goals")
        return [copy.deepcopy(g) for g in r.goals.values()]

    def put_goal(user_id, data):
        r.note("put_goal")
        r.goals[data["id"]] = copy.deepcopy(data)

    def user_sets(user_id, exercise_ids):
        r.note("user_sets")
        return [copy.deepcopy(s) for s in r.sets if s["exercise_id"] in set(exercise_ids)]

    monkeypatch.setattr(models, "goal_transaction", r.transaction)
    monkeypatch.setattr(models, "get_goal", get_goal)
    monkeypatch.setattr(models, "user_goals", user_goals)
    monkeypatch.setattr(models, "put_goal", put_goal)
    monkeypatch.setattr(models, "user_sets", user_sets)
    monkeypatch.setattr(models, "user_workout_dates", lambda user_id: [])
    monkeypatch.setattr(models, "get_exercise", lambda slug: copy.deepcopy(LIBRARY.get(slug)))
    monkeypatch.setattr(models, "get_exercises",
                        lambda slugs: {k: copy.deepcopy(v) for k, v in LIBRARY.items() if k in set(slugs)})
    return r


def body(**changes) -> dict:
    data = {"id": str(uuid.uuid4()), "type": "strength", "exercise_id": BENCH, "target": 100.0,
            "start_date": "2026-10-20"}
    data.update(changes)
    return data


def calls_named(rec, name):
    return [inside for n, inside in rec.calls if n == name]


def test_s2_create_reads_the_goals_and_writes_inside_one_transaction(rec):
    rec.add()
    goal, created = goal_service.create_goal(USER, body(), TODAY)
    assert created and goal["status"] == "active"
    assert rec.transactions == 1
    assert calls_named(rec, "get_goal") == [True]
    assert calls_named(rec, "user_goals") == [True]
    assert calls_named(rec, "put_goal") == [True]


def test_s2_a_create_refused_by_the_limit_rolls_back_without_writing(rec):
    for _ in range(3):
        rec.add()
    with pytest.raises(ApiError) as caught:
        goal_service.create_goal(USER, body(), TODAY)
    assert caught.value.code == "conflict"
    assert rec.rolled_back == 1
    assert calls_named(rec, "user_goals") == [True]
    assert calls_named(rec, "put_goal") == []
    assert len(rec.goals) == 3


def test_s2_a_second_frequency_goal_is_refused_inside_the_transaction(rec):
    rec.add(type="frequency", exercise_id=None, target=4)
    with pytest.raises(ApiError) as caught:
        goal_service.create_goal(USER, body(type="frequency", exercise_id=None, target=3), TODAY)
    assert caught.value.code == "conflict"
    assert rec.rolled_back == 1
    assert calls_named(rec, "user_goals") == [True]
    assert calls_named(rec, "put_goal") == []


def test_s2_a_retry_at_the_limit_is_still_200_and_checks_nothing(rec):
    for _ in range(3):
        rec.add()
    again = rec.goals[next(iter(rec.goals))]
    goal, created = goal_service.create_goal(USER, body(id=again["id"]), TODAY)
    assert created is False and goal["id"] == again["id"]
    assert calls_named(rec, "user_goals") == []
    assert calls_named(rec, "put_goal") == []


def test_s2_reopening_a_completed_goal_checks_the_limit_inside_the_transaction(rec):
    rec.sets.append({"id": "s1", "exercise_id": BENCH, "set_type": "working", "weight_kg": 100.0,
                     "reps": 5, "local_date": "2026-10-28"})
    done = rec.add(target=100.0)
    for _ in range(3):
        rec.add(target=900.0)
    with pytest.raises(ApiError) as caught:
        goal_service.update_goal(USER, done["id"], {"target": 900.0}, TODAY)
    assert caught.value.code == "conflict"
    assert rec.rolled_back == 1
    assert calls_named(rec, "get_goal") == [True]
    assert calls_named(rec, "user_goals") == [True]
    assert calls_named(rec, "put_goal") == []
    assert rec.goals[done["id"]]["target"] == 100.0


def test_s2_an_update_writes_inside_the_transaction(rec):
    goal = rec.add(target=120.0)
    result = goal_service.update_goal(USER, goal["id"], {"target": 130.0, "deadline": "2026-12-01"}, TODAY)
    assert result["target"] == 130.0 and result["deadline"] == "2026-12-01"
    assert rec.transactions == 1
    assert calls_named(rec, "put_goal") == [True]


def test_s2_an_update_of_a_missing_goal_is_404_and_writes_nothing(rec):
    with pytest.raises(ApiError) as caught:
        goal_service.update_goal(USER, str(uuid.uuid4()), {"target": 130.0}, TODAY)
    assert caught.value.code == "not_found"
    assert calls_named(rec, "put_goal") == []


def test_s2_models_add_goal_does_not_call_check_for_a_taken_id(rec):
    taken = rec.add()
    checked = []
    stored, created = models.add_goal(USER, {**taken, "target": 5.0}, checked.append)
    assert created is False and stored["target"] == taken["target"]
    assert checked == []


def test_s2_models_change_goal_passes_the_other_goals_and_keeps_the_id(rec):
    mine, other = rec.add(), rec.add()
    seen = []

    def change(old, others):
        seen.append([g["id"] for g in others])
        return {**old, "id": "something-else", "target": 150.0}

    new = models.change_goal(USER, mine["id"], change)
    assert seen == [[other["id"]]]
    assert new["id"] == mine["id"] and rec.goals[mine["id"]]["target"] == 150.0
