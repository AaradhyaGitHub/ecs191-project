"""Entity helpers. All Datastore reads and writes go through this module (CLAUDE.md design rules).

Locally, set DATASTORE_EMULATOR_HOST=localhost:8081 so nothing touches the real database.
On App Engine, the project comes from the environment and no setup is needed.
"""
from __future__ import annotations

import os
from functools import lru_cache

from google.cloud import datastore

LOCAL_PROJECT = "musclemap-local"


@lru_cache(maxsize=1)
def client() -> datastore.Client:
    """One Datastore client per process (the emulator's when DATASTORE_EMULATOR_HOST is set)."""
    if os.environ.get("DATASTORE_EMULATOR_HOST"):
        return datastore.Client(project=os.environ.get("DATASTORE_PROJECT_ID", LOCAL_PROJECT))
    return datastore.Client()
