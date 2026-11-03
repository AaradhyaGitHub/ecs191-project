# Muscle Map API

The contract between the iOS app and the Flask server. A new or changed endpoint lands here first, with example JSON in `shared/fixtures/`, in its own small PR (see `CLAUDE.md`, "Contract first").

**Status of each endpoint:** **agreed** = taken from the team's setup guide; **proposed** = drafted to fill a gap, needs a team OK before it's built.

## Conventions
- **Base URL:** `http://localhost:5000/api/v1` locally; `https://<PROJECT_ID>.<REGION_ID>.r.appspot.com/api/v1` deployed.
- **JSON** in and out, keys in `snake_case`. Timestamps are ISO 8601 in UTC (`2026-11-02T17:02:00Z`).
- **Auth:** every endpoint except sign-in requires `Authorization: Bearer <token>`.
- **Weights** are always kg. The app converts to the user's units for display.
- **IDs** for workouts and sets are UUIDs made on the phone. Sending the same workout twice changes nothing.
- **Errors** use one shape, with the matching HTTP status:
  ```json
  {"error": {"code": "not_found", "message": "No workout with that id."}}
  ```
  Codes (proposed): `bad_request` 400, `unauthorized` 401, `forbidden` 403, `not_found` 404, `conflict` 409, `internal` 500.

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

**Next, once Lift works:** `GET /muscle-map?window=7d` (Home), `GET` and `POST /goals`, `POST /smart-log/parse` (the AI feature).

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

### `PUT /users/me`  (proposed shape)
Send only the fields to change; the response is the full user, as in `GET /users/me`.
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
      "last_done_at": "2026-11-03T17:00:00Z"
    }
  ]
}
```

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
The setup guide's example has no `id`, `timezone` or `local_date`; they're added here because the guide's data model requires client-made UUIDs and a local date on every workout. Response (proposed): `201` with the saved workout in the `GET /workouts/{id}` shape; a repeated request returns `200` with the same body.

### `GET /workouts?limit=20`  (proposed shape)
Newest first. A summary per workout, without its sets.
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
