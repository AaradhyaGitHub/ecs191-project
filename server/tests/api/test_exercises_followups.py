"""Picker review follow-ups (Issue #44, S2): an empty `group=` is refused like an unknown group.

Written by implementer (not test-writer). The group check runs before any database read,
so these tests need no emulator.
"""
from __future__ import annotations

import pytest


@pytest.mark.parametrize("query", ["?group=", "?q=bench&group=", "?group=nonsense"])
def test_an_empty_or_unknown_group_is_400(client, query):
    response = client.get(f"/api/v1/exercises{query}")
    assert response.status_code == 400
    assert response.get_json()["error"]["code"] == "bad_request"
