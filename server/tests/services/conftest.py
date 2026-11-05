"""Service unit tests run without a database.

`models.goal_transaction` would open a real Datastore transaction, so here it is a plain
`with` block; the goal reads and writes inside it are the tests' in-memory stand-ins. The
transaction itself is covered against the emulator in tests/api/test_goal_review_fixes.py.
"""
from __future__ import annotations

import contextlib

import pytest

import models


@pytest.fixture(autouse=True)
def no_goal_transaction(monkeypatch):
    monkeypatch.setattr(models, "goal_transaction", contextlib.nullcontext)
