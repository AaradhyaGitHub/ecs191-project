"""Checks shared/muscles.json, the muscle IDs the app and server share (llm.md, Decisions).

IDs are permanent once exercises use them, so the rules are enforced here:
every head ID is `<parent>_<head>`, IDs are unique, and every parent and group exists.
"""
import json
import re
from pathlib import Path

import pytest

MUSCLES = Path(__file__).resolve().parents[2] / "shared" / "muscles.json"
ID = re.compile(r"^[a-z][a-z0-9]*(_[a-z0-9]+)*$")


@pytest.fixture(scope="module")
def data():
    return json.loads(MUSCLES.read_text())


def test_ids_are_snake_case(data):
    every = [g["id"] for g in data["groups"]] + [p["id"] for p in data["parents"]] + [m["id"] for m in data["muscles"]]
    assert [i for i in every if not ID.match(i)] == []


def test_ids_are_unique_across_parents_and_heads(data):
    ids = [p["id"] for p in data["parents"]] + [m["id"] for m in data["muscles"]]
    assert len(ids) == len(set(ids))


def test_every_parent_and_group_exists(data):
    groups = {g["id"] for g in data["groups"]}
    parents = {p["id"]: p for p in data["parents"]}
    assert all(p["group"] in groups for p in parents.values())
    for m in data["muscles"]:
        assert m["parent"] in parents, m["id"]
        assert m["group"] == parents[m["parent"]]["group"], m["id"]


def test_head_ids_start_with_their_parent(data):
    assert [m["id"] for m in data["muscles"] if not m["id"].startswith(m["parent"] + "_")] == []


def test_every_parent_has_a_head(data):
    used = {m["parent"] for m in data["muscles"]}
    assert [p["id"] for p in data["parents"] if p["id"] not in used] == []


def test_every_muscle_has_names(data):
    for m in data["muscles"]:
        assert m["name"].strip() and m["short_name"].strip(), m["id"]
