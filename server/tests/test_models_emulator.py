"""Proves the server reaches the Datastore emulator (runs only when it's up)."""
import pytest

import models


@pytest.mark.emulator
def test_round_trip_through_the_emulator(emulator):
    db = models.client()
    key = db.key("Probe", "one")
    entity = models.datastore.Entity(key=key)
    entity["value"] = 42
    db.put(entity)

    assert db.get(key)["value"] == 42
