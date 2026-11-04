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
    """Creates or replaces one UserExercise. Tests use it to seed history; real writes
    come from save_workout."""
    client().put(_user_exercise_entity(user_exercise_key(user_id, slug), data))


# --- Workout and SetEntry (User/{id}/Workout/{uuid}/SetEntry/{uuid}) ---------------------
# Plan: specs/log-workout.llm.md. Workouts don't change after they are saved.

WORKOUT = "Workout"
SET_ENTRY = "SetEntry"


def workout_key(user_id: str, workout_id: str) -> datastore.Key:
    return client().key(USER, user_id, WORKOUT, workout_id)


def _set_key(workout: datastore.Key, set_id: str) -> datastore.Key:
    return client().key(SET_ENTRY, set_id, parent=workout)


def get_exercises(slugs) -> dict:
    """The library exercises with these slugs, as {slug: exercise}. Unknown slugs are left out."""
    keys = [exercise_key(slug) for slug in sorted(set(slugs))]
    found = {}
    for start in range(0, len(keys), 1000):  # get_multi takes at most 1000 keys
        for entity in client().get_multi(keys[start:start + 1000]):
            found[entity.key.name] = _exercise_dict(entity)
    return found


def _workout_dict(entity: datastore.Entity) -> dict:
    return {"id": entity.key.name, **dict(entity)}


def _set_dict(entity: datastore.Entity) -> dict:
    return {"id": entity.key.name, **dict(entity)}


def _user_exercise_dict(entity: datastore.Entity) -> dict:
    data = dict(entity)
    if data.get("last_set") is not None:
        data["last_set"] = dict(data["last_set"])
    return data


def _user_exercise_entity(key: datastore.Key, data: dict) -> datastore.Entity:
    entity = datastore.Entity(key=key, exclude_from_indexes=_USER_EXERCISE_UNINDEXED)
    fields = dict(data)
    if fields.get("last_set") is not None:
        embedded = datastore.Entity()
        embedded.update(fields["last_set"])
        fields["last_set"] = embedded
    entity.update(fields)
    return entity


def _stored_sets(db: datastore.Client, key: datastore.Key) -> list[dict]:
    sets = [_set_dict(e) for e in db.query(kind=SET_ENTRY, ancestor=key).fetch()]
    return sorted(sets, key=lambda s: s["order"])


def save_workout(user_id: str, workout: dict, sets: list[dict], merge) -> tuple[dict, list[dict], bool]:
    """Saves a workout, its sets and its UserExercises in one transaction.

    If the Workout already exists, nothing is written and the stored one comes back.
    Otherwise reads this user's UserExercise for each exercise in `sets`, calls
    `merge(old_or_None, workout, sets_of_that_exercise)` for each, and writes everything.
    Returns (workout, sets, created).
    """
    db = client()
    key = workout_key(user_id, workout["id"])
    by_exercise: dict[str, list[dict]] = {}
    for s in sets:
        by_exercise.setdefault(s["exercise_id"], []).append(s)

    with db.transaction():
        existing = db.get(key)
        if existing is not None:
            return _workout_dict(existing), _stored_sets(db, key), False

        history_keys = [user_exercise_key(user_id, slug) for slug in sorted(by_exercise)]
        old = {e.key.name: _user_exercise_dict(e) for e in db.get_multi(history_keys)}

        entity = datastore.Entity(key=key)
        entity.update({k: v for k, v in workout.items() if k != "id"})
        entity["created_at"] = _now()
        to_write = [entity]
        for s in sets:
            set_entity = datastore.Entity(key=_set_key(key, s["id"]))
            set_entity.update({k: v for k, v in s.items() if k != "id"})
            to_write.append(set_entity)
        for history_key in history_keys:
            slug = history_key.name
            merged = merge(old.get(slug), workout, by_exercise[slug])
            to_write.append(_user_exercise_entity(history_key, merged))
        db.put_multi(to_write)

    return dict(workout), sorted((dict(s) for s in sets), key=lambda s: s["order"]), True


def get_workout(user_id: str, workout_id: str) -> tuple[dict, list[dict]] | None:
    """The stored workout and its sets, or None when this user has no workout with that id."""
    db = client()
    key = workout_key(user_id, workout_id)
    entity = db.get(key)
    if entity is None:
        return None
    return _workout_dict(entity), _stored_sets(db, key)


def list_workouts(user_id: str, limit: int) -> list[dict]:
    """This user's stored workouts (without sets), newest started_at first."""
    query = client().query(kind=WORKOUT, ancestor=user_key(user_id))
    query.order = ["-started_at"]
    return [_workout_dict(e) for e in query.fetch(limit=limit)]


def update_user(user_id: str, fields: dict) -> dict:
    """Sets these fields on the User and returns the stored user."""
    db = client()
    with db.transaction():
        entity = db.get(user_key(user_id))
        if entity is None:
            entity = datastore.Entity(key=user_key(user_id))
            entity["created_at"] = _now()
        entity.update(fields)
        db.put(entity)
    return {"id": entity.key.name, **dict(entity)}


def _now() -> datetime:
    return datetime.now(timezone.utc)
