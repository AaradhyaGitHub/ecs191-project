"""Shared fixtures.

Tests marked `emulator` run only when DATASTORE_EMULATOR_HOST is set, so a missing
emulator skips them instead of ever reaching the real database.
"""
from __future__ import annotations

import os
import urllib.request

import pytest

from main import create_app


@pytest.fixture
def app():
    app = create_app()
    app.config.update(TESTING=True)
    return app


@pytest.fixture
def client(app):
    return app.test_client()


def pytest_collection_modifyitems(config, items):
    if os.environ.get("DATASTORE_EMULATOR_HOST"):
        return
    skip = pytest.mark.skip(reason="Datastore emulator not running (set DATASTORE_EMULATOR_HOST)")
    for item in items:
        if "emulator" in item.keywords:
            item.add_marker(skip)


@pytest.fixture
def emulator():
    """Empties the emulator before the test, so tests never see each other's data."""
    host = os.environ["DATASTORE_EMULATOR_HOST"]
    request = urllib.request.Request(f"http://{host}/reset", method="POST")
    urllib.request.urlopen(request, timeout=5).close()
    yield host
