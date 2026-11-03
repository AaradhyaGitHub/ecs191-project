# Muscle Map API

The contract between the iOS app and the Flask server. A new or changed endpoint lands here first, with example JSON in `shared/fixtures/`, in its own small PR (see `CLAUDE.md`, "Contract first").

**Status of each endpoint:** **agreed** = taken from the team's setup guide; **proposed** = drafted to fill a gap, needs a team OK before it's built.

## Conventions
- **Base URL:** `http://localhost:5000/api/v1` locally; `https://<PROJECT_ID>.<REGION_ID>.r.appspot.com/api/v1` deployed.
- **JSON** in and out, keys in `snake_case`. Timestamps are ISO 8601 in UTC (`2026-11-02T17:02:00Z`).
- **Auth:** every endpoint except sign-in requires `Authorization: Bearer <token>`.
- **Weights** are always kg, sent and stored at full precision (157.5 lb → 71.4408 kg), never rounded. The app converts to the user's units and rounds only for display. Dumbbell weights are one dumbbell's weight (pending team agreement).
- **IDs** for workouts, sets and saved workouts (templates) are UUIDs made on the phone. Sending the same thing twice changes nothing.
- **Lists are wrapped** in an object, e.g. `{"templates": [...]}`, never a bare array, so fields such as `next_cursor` can be added later without breaking the app (decided).
- **Errors** use one shape, with the matching HTTP status:
  ```json
  {"error": {"code": "not_found", "message": "No workout with that id."}}
  ```
  Codes (decided): `bad_request` 400 (malformed or invalid input), `unauthorized` 401 (not signed in, or token expired), `forbidden` 403 (someone else's data), `not_found` 404, `conflict` 409 (clashes with existing data), `internal` 500 (a server bug). Don't add codes without updating this list.

## Endpoints for the Lift tab

| Method and path | Purpose | Needed for | Status |
|---|---|---|---|
| `POST /auth/sms/start`, `POST /auth/sms/verify` | Sign in by phone code, return a token | Everything | agreed; shapes follow the course SMS example |
| `GET /users/me`, `PUT /users/me` | Read or update the profile | Onboarding | agreed; shapes proposed |
| `GET /exercises?q=bench` | Search exercises by name or alias | Adding exercises to a workout | agreed; shapes proposed |
| `GET /exercises/mine` | This user's exercises: recent, most used, last set | Exercise picker | agreed; shapes proposed |
| `GET /templates` | Saved workouts, with last-done time | Lift home | agreed; shapes proposed |
| `POST /templates`, `PUT /templates/{id}`, `DELETE /templates/{id}` | Create, edit or delete a saved workout | Lift home | agreed; shapes proposed |
| `POST /workouts` | Save a finished workout and all its sets | Finishing a workout | agreed |
| `GET /workouts?limit=20` | Recent workouts, newest first | History on Home | agreed; shapes proposed |
| `GET /workouts/{id}` | One workout with its sets | Workout detail | agreed; shapes proposed |

**Next, once Lift works:** `GET /muscle-map?window=7d` (Home), `GET` and `POST /goals`, `POST /smart-log/parse` (the AI feature). Home must also show where your muscles were at any past point, so the muscle map will need an end date as well as a window (for example `?window=7d&end=2026-10-01`); to be designed with Home.

---

### `POST /auth/sms/start` and `POST /auth/sms/verify`
Reuse the course's SMS authentication example. Request and response shapes will be copied from it once it's in the repo. `verify` returns the bearer token the app stores in the Keychain.

### `GET /users/me`  (proposed shape)
```json
{
  "id": "u_123",
  "display_name": "Sasa",
  "sex": null,
  "birth_year": null,
  "bodyweight_kg": 82.1,
  "units": "lb",
  "experience": "intermediate",
  "created_at": "2026-11-01T18:00:00Z"
}
```

### `PUT /users/me`  (decided: partial update)
Send only the fields to change; fields left out stay as they are. The response is the full user, as in `GET /users/me`.
```json
{"bodyweight_kg": 81.5, "units": "kg"}
```

### `GET /exercises?q=bench`  (proposed shape)
Matches name and aliases. Without `q`, returns the whole library.
```json
{
  "exercises": [
    {
      "id": "barbell_bench_press",
      "name": "Bench Press",
      "aliases": ["bench", "BP"],
      "load_type": "barbell",
      "bodyweight_fraction": null,
      "muscles": [
        {"muscle_id": "chest_sternal", "role": "primary", "weight": 1.0},
        {"muscle_id": "triceps_long", "role": "secondary", "weight": 0.5}
      ]
    }
  ]
}
```
Muscle IDs come from `shared/muscles.json` (not agreed yet; the IDs above are examples).

### `GET /exercises/mine`  (proposed shape)
```json
{
  "exercises": [
    {
      "exercise_id": "push_up",
      "use_count": 14,
      "last_used_at": "2026-11-01T18:10:00Z",
      "last_set": {"weight_kg": null, "added_load_kg": 0, "reps": 20, "duration_s": null, "effort_pct": 90},
      "best_e1rm_kg": null,
      "best_e1rm_at": null
    }
  ]
}
```
The app sorts by `last_used_at` for Recent and by `use_count` for Most used.

### `GET /templates`  (proposed shape)
```json
{
  "templates": [
    {
      "id": "tpl_push1",
      "name": "Push 1",
      "focus": "tricep focus",
      "exercises": [
        {"exercise_id": "barbell_bench_press", "target_sets": 4, "target_reps": 6, "rest_s": 180}
      ],
      "last_done_at": "2026-11-03T17:00:00Z",
      "top_muscles": [
        {"muscle_id": "chest", "level": 4},
        {"muscle_id": "delts", "level": 4},
        {"muscle_id": "triceps", "level": 3}
      ]
    }
  ]
}
```
`top_muscles` (decided): the 3 parent muscles the workout works most, computed by the server and never stored. `level` is 0–4, the intensity shade for the chip. The IDs above are examples until `shared/muscles.json` is agreed. "UP NEXT" is the template with the oldest `last_done_at` (never-done first); the app works that out from this list.

### `POST /templates` and `PUT /templates/{id}`  (proposed shape)
Request: `name`, `focus` and `exercises` as above. Response: the full template, `201` for create and `200` for update. `DELETE /templates/{id}` returns `204` with no body.

### `POST /workouts`  (agreed)
Saves the workout and its sets, adds to that day's DailyStats and updates the running totals in one transaction. The `id` fields are UUIDs made on the phone; repeating the request with the same IDs changes nothing.
```json
{
  "id": "6f1c2b1e-4b7a-4c3e-9d2a-0a1b2c3d4e5f",
  "name": "Push 1",
  "template_id": "tpl_push1",
  "started_at": "2026-11-02T17:02:00Z",
  "ended_at": "2026-11-02T19:33:00Z",
  "timezone": "America/Los_Angeles",
  "local_date": "2026-11-02",
  "bodyweight_kg": 82.1,
  "sets": [
    {"id": "a0b1c2d3-0000-4000-8000-000000000001",
     "exercise_id": "barbell_bench_press", "order": 1, "set_type": "working",
     "reps": 5, "weight_kg": 70.3, "effort_pct": 80,
     "started_at": "2026-11-02T17:10:05Z", "ended_at": "2026-11-02T17:10:40Z",
     "rest_before_s": 186, "time_source": "rest_timer", "input": "manual"},
    {"id": "a0b1c2d3-0000-4000-8000-000000000002",
     "exercise_id": "push_up", "order": 2, "superset_group": "a", "set_type": "working",
     "reps": 20, "added_load_kg": 0, "effort_pct": 90,
     "rest_before_s": 30, "time_source": "rest_timer", "input": "manual"}
  ]
}
```
Decided: this body is the setup guide's example plus the fields its data model adds ("Fields to add to the kinds above"): the workout's and each set's phone-made `id`, `timezone` and `local_date`. `local_date` is the user's own day, so streaks and daily stats don't shift at midnight UTC. `rep_offsets_ms` (optional, per set) comes later with the camera. Response (decided): `201` with the saved workout in the `GET /workouts/{id}` shape. A repeated request with the same `id` saves nothing and returns `200` with the same body; the app treats both as success.

### `GET /workouts?limit=20&before=<timestamp>`  (proposed shape)
Newest first. A summary per workout, without its sets.
- `limit` (default 20) is built first.
- `before` is **required by Home** and built with it: it returns workouts that started before that time, so the app can page back through all of history or jump to any date. Home's history is the core of the app ("where you are now, where you've been, where your muscles were"), so it must reach any point in time.
```json
{
  "workouts": [
    {"id": "6f1c2b1e-…", "name": "Push 1", "template_id": "tpl_push1",
     "started_at": "2026-11-02T17:02:00Z", "ended_at": "2026-11-02T19:33:00Z",
     "local_date": "2026-11-02", "set_count": 31, "exercise_count": 10}
  ]
}
```

### `GET /workouts/{id}`  (proposed shape)
The workout with every set, in the same fields as the `POST /workouts` body, plus `status`.
