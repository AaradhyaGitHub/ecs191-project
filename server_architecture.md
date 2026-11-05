# Server architecture

## Stack

Flask on App Engine, Python 3.13, Firestore in Datastore mode, region `us-west2`. The region cannot be changed.

## Layers, and why

`api/` only parses requests, `services/` holds the logic with no Flask, and `models.py` is the only code that touches Datastore. This lets the logic be tested without a database.

## Endpoints that exist

- `auth/sms/start` and `auth/sms/verify`
- `GET` and `PUT /users/me`
- `GET /exercises` and `GET /exercises/mine`
- `/templates`: `GET`, `POST`, `PUT`, `DELETE`
- `/workouts`: `POST`, `GET` list, `GET` by id

Full request and response shapes are in `API.md`.

## Data model

- **User:** Profile and units.
- **Exercise:** Shared library entry and its muscle weights.
- **Template:** A saved workout.
- **Workout:** One session.
- **SetEntry:** One set, the source data everything else is computed from.
- **UserExercise:** Last set and best e1RM per exercise, used to prefill the next set.

`shared/muscles.json` defines 6 groups, 20 parent muscles, and 50 heads. For example, `triceps_long` → `triceps` → `arms`. Muscle IDs are never renamed or reused.

An exercise lists its muscles with a role (`primary`, `secondary`, or `stabilizer`) and a weight from 0 to 1.

## Rules

"Store what happened, compute everything else."

- Only sets are stored. e1RM, volume, muscle levels, and `top_muscles` are computed on request.
- Weights are stored in exact kg. For example, 157.5 lb is stored as 71.4408 kg, never rounded.
- IDs are UUIDs made on the phone, so `POST /workouts` is safe to retry. It saves in one transaction. The first request returns 201; a repeated request returns 200 with the same response body.

## Sign-in

Sign-in passes through to the course SMS service, then creates our own session. The course `app_token` stays on the server. The test number `+15305550000` and code `123456` work without it. Sessions don't expire yet.

**Why:** The professor said not to spend time on auth.

## Errors

Errors use one JSON shape: `{"error": {"code": "...", "message": "..."}}`. The six codes are `bad_request`, `unauthorized`, `forbidden`, `not_found`, `conflict`, and `internal`.

## Development and deploy

- Local runs use the Datastore emulator, never the real database.
- CI runs the tests and a secret scan.
- Deploys go from `main` only.