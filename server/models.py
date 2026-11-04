"""Entity helpers. All Datastore reads and writes go through this module (CLAUDE.md design rules).

Locally, set DATASTORE_EMULATOR_HOST=localhost:8081 so nothing touches the real database.
On App Engine, the project comes from the environment and no setup is needed.
"""
from __future__ import annotations

import os
from datetime import datetime, timezone
from functools import lru_cache

from google.cloud import datastore

LOCAL_PROJECT = "musclemap-local"

# Datastore writes at most 500 entities per commit.
_BATCH = 500


@lru_cache(maxsize=1)
def client() -> datastore.Client:
    """One Datastore client per process (the emulator's when DATASTORE_EMULATOR_HOST is set)."""
    if os.environ.get("DATASTORE_EMULATOR_HOST"):
        return datastore.Client(project=os.environ.get("DATASTORE_PROJECT_ID", LOCAL_PROJECT))
    return datastore.Client()


# --- Exercise (shared library; key = slug, e.g. "barbell_bench_press") -------------------

EXERCISE = "Exercise"
# Lists of embedded entities aren't queried, so they're kept out of the indexes.
_EXERCISE_UNINDEXED = ("muscles",)


def exercise_key(slug: str) -> datastore.Key:
    return client().key(EXERCISE, slug)


def _exercise_entity(data: dict) -> datastore.Entity:
    entity = datastore.Entity(key=exercise_key(data["id"]), exclude_from_indexes=_EXERCISE_UNINDEXED)
    fields = {k: v for k, v in data.items() if k != "id"}
    muscles = []
    for m in fields.pop("muscles", []):
        embedded = datastore.Entity()
        embedded.update(m)
        muscles.append(embedded)
    entity.update(fields)
    entity["muscles"] = muscles
    return entity


def _exercise_dict(entity: datastore.Entity) -> dict:
    data = {"id": entity.key.name, **dict(entity)}
    data["muscles"] = [dict(m) for m in entity.get("muscles", [])]
    return data


def put_exercises(exercises: list[dict]) -> int:
    """Creates or replaces exercises by slug, so loading the same list twice changes nothing."""
    entities = [_exercise_entity(e) for e in exercises]
    for start in range(0, len(entities), _BATCH):
        client().put_multi(entities[start:start + _BATCH])
    return len(entities)


def get_exercise(slug: str) -> dict | None:
    entity = client().get(exercise_key(slug))
    return _exercise_dict(entity) if entity else None


def all_exercises() -> list[dict]:
    """The whole shared library, sorted by name."""
    return sorted((_exercise_dict(e) for e in client().query(kind=EXERCISE).fetch()),
                  key=lambda e: e["name"].lower())


# --- User and Session --------------------------------------------------------------------
# User key = the course sign-in service's user_id. Session key = SHA-256 of the token
# (services/auth.py), so the raw token is never stored.

USER = "User"
SESSION = "Session"


def user_key(user_id: str) -> datastore.Key:
    return client().key(USER, user_id)


def ensure_user(user_id: str) -> None:
    """Creates the User the first time someone signs in; later sign-ins change nothing."""
    db = client()
    with db.transaction():
        if db.get(user_key(user_id)) is None:
            entity = datastore.Entity(key=user_key(user_id))
            entity["created_at"] = _now()
            db.put(entity)


def get_user(user_id: str) -> dict | None:
    entity = client().get(user_key(user_id))
    return {"id": entity.key.name, **dict(entity)} if entity else None


def create_session(token_hash: str, user_id: str) -> None:
    entity = datastore.Entity(key=client().key(SESSION, token_hash))
    entity.update({"user_id": user_id, "created_at": _now()})
    client().put(entity)


def session_user_id(token_hash: str) -> str | None:
    entity = client().get(client().key(SESSION, token_hash))
    return entity["user_id"] if entity else None


# --- UserExercise (User/{id}/UserExercise/{slug}; server_architecture.llm.md) -------------

USER_EXERCISE = "UserExercise"
# The last set is an embedded entity that is never queried.
_USER_EXERCISE_UNINDEXED = ("last_set",)


def user_exercise_key(user_id: str, slug: str) -> datastore.Key:
    return client().key(USER, user_id, USER_EXERCISE, slug)


def user_exercises(user_id: str) -> list[dict]:
    """This user's history with each exercise, one dict per UserExercise (`exercise_id` = slug)."""
    rows = []
    for entity in client().query(kind=USER_EXERCISE, ancestor=user_key(user_id)).fetch():
        row = {"exercise_id": entity.key.name, **dict(entity)}
        if row.get("last_set") is not None:
            row["last_set"] = dict(row["last_set"])
        rows.append(row)
    return rows


def put_user_exercise(user_id: str, slug: str, data: dict) -> None:
    """Creates or replaces one UserExercise. Only tests use it until POST /workouts exists."""
    entity = datastore.Entity(key=user_exercise_key(user_id, slug),
                              exclude_from_indexes=_USER_EXERCISE_UNINDEXED)
    fields = dict(data)
    if fields.get("last_set") is not None:
        embedded = datastore.Entity()
        embedded.update(fields["last_set"])
        fields["last_set"] = embedded
    entity.update(fields)
    client().put(entity)


def get_exercises(slugs) -> dict:
    """The library exercises with these slugs, as {slug: exercise}; unknown slugs are left out.

    #42 plans the same helper; whichever lands first adds it, the other reuses it.
    SCAFFOLD: returns {} until build mode.
    """
    return {}


# --- Template (User/{id}/Template/{uuid}; a saved workout, server_architecture.llm.md) ----
# SCAFFOLD: these return valid but wrong values until build mode.

TEMPLATE = "Template"


def template_key(user_id: str, template_id: str) -> datastore.Key:
    return client().key(USER, user_id, TEMPLATE, template_id)


def get_template(user_id: str, template_id: str) -> dict | None:
    """One of this user's saved workouts, or None."""
    return None


def user_templates(user_id: str) -> list[dict]:
    """All of this user's saved workouts, in no set order (the service sorts them)."""
    return []


def put_template(user_id: str, data: dict) -> None:
    """Creates or replaces one saved workout; `data["id"]` is its key."""
    return None


def delete_template(user_id: str, template_id: str) -> None:
    """Deletes one saved workout. A missing one is no error."""
    return None


def change_template(user_id: str, template_id: str, change) -> dict | None:
    """In one transaction: reads the template, calls change(old), writes the result if not None.

    Returns the written template, or None when the template is missing or nothing changed.
    """
    return None


def _now() -> datetime:
    return datetime.now(timezone.utc)
