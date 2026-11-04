# Muscle Map API

The contract between the iOS app and the Flask server. A new or changed endpoint lands here first, with example JSON in `shared/fixtures/`, in its own small PR (see `CLAUDE.md`, "Contract first").

**Status of each endpoint:** **agreed** = taken from the team's setup guide, or settled in an approved plan (`specs/*.llm.md`); **proposed** = drafted to fill a gap, needs a team OK before it's built.

## Conventions
- **Base URL:** `http://localhost:5001/api/v1` locally; `https://<PROJECT_ID>.<REGION_ID>.r.appspot.com/api/v1` deployed.
- **JSON** in and out, keys in `snake_case`. Timestamps are ISO 8601 in UTC. The app sends `2026-11-02T17:02:00Z`; it also accepts fractional seconds and `+00:00` (Python's `isoformat()`), so the server may send either.
- **Examples as files:** every example below is also in `shared/fixtures/`. The iOS tests decode them, and server tests should produce the same shapes, so the two sides can't drift apart.
- **Auth:** every endpoint except sign-in, `GET /health` and `GET /exercises` requires `Authorization: Bearer <token>`.
- **Weights** are always kg, sent and stored at full precision (157.5 lb → 71.4408 kg), never rounded. The app converts to the user's units and rounds only for display. Dumbbell weights are one dumbbell's weight (pending team agreement).
- **IDs** for workouts, sets and saved workouts (templates) are UUIDs made on the phone, always **lowercase** (Datastore keys are case-sensitive, so a retry must match exactly). Sending the same thing twice changes nothing.
- **Lists are wrapped** in an object, e.g. `{"templates": [...]}`, never a bare array, so fields such as `next_cursor` can be added later without breaking the app (decided).
- **Errors** use one shape, with the matching HTTP status:
  ```json
  {"error": {"code": "not_found", "message": "No workout with that id."}}
  ```
  Codes (decided): `bad_request` 400 (malformed or invalid input), `unauthorized` 401 (not signed in, or token expired), `forbidden` 403 (someone else's data), `not_found` 404, `conflict` 409 (clashes with existing data), `internal` 500 (a server bug). Don't add codes without updating this list. Other HTTP errors keep their own status and use the nearest code (a wrong method is `405` with `bad_request`). A `500` never includes internal details.

## Endpoints for the Lift tab

| Method and path | Purpose | Needed for | Status |
|---|---|---|---|
| `GET /health` | Server is up: `{"status": "ok"}`. No auth | Deploy checks, the app's connection test | **built** |
| `POST /auth/sms/start`, `POST /auth/sms/verify` | Sign in by phone code, return a token. No auth | Everything | **built** |
| `GET /users/me`, `PUT /users/me` | Read or update the profile | Onboarding | agreed |
| `GET /exercises?q=bench&group=chest` | Search exercises by name or alias, optionally in one muscle group. No auth | Adding exercises to a workout | agreed |
| `GET /exercises/mine` | This user's exercises: recent, most used, last set | Exercise picker | agreed; shapes proposed |
| `GET /templates` | Saved workouts, with last-done time | Lift home | agreed |
| `POST /templates`, `PUT /templates/{id}`, `DELETE /templates/{id}` | Create, edit or delete a saved workout | Lift home | agreed |
| `POST /workouts` | Save a finished workout and all its sets | Finishing a workout | agreed |
| `GET /workouts?limit=20` | Recent workouts, newest first | History on Home | agreed (`before` comes with Home) |
| `GET /workouts/{id}` | One workout with its sets | Workout detail | agreed |

**Next, once Lift works:** `GET /muscle-map?window=7d` (Home), `GET` and `POST /goals`, `POST /smart-log/parse` (the AI feature). Home must also show where your muscles were at any past point, so the muscle map will need an end date as well as a window (for example `?window=7d&end=2026-10-01`); to be designed with Home.

---

### Sign-in: `POST /auth/sms/start` and `POST /auth/sms/verify`  (built)
Our server passes these through to the course's SMS sign-in service, so we run no SMS provider of our own. **For development, use the test number `+15305550000` with code `123456`**: no text is sent and no setup is needed. Real phone numbers need the course `app_token` on the server (`SMS_APP_TOKEN`); until it's set they get `403 forbidden`.

`POST /auth/sms/start` texts a 6-digit code:
```json
{"phone_number": "+15305550000"}
```
→ `200 {"sent": true}`. Phone numbers are E.164 (`+` and digits, no spaces). Errors: `400 bad_request` (bad format, or the course service refused the number), `403 forbidden` (real number, no app token yet), `500 internal` (course service unreachable).

`POST /auth/sms/verify` checks the code and signs in:
```json
{"phone_number": "+15305550000", "code": "123456"}
```
→ `200`
```json
{"token": "example-session-token-not-real", "user_id": "5642800292954112"}
```
The app stores `token` in the Keychain and sends it on every other request as `Authorization: Bearer <token>`. Signing in again returns a new token for the same `user_id`; older tokens keep working. Tokens don't expire for now; logout comes later. Errors: `401 unauthorized` (wrong or expired code), `400 bad_request` (missing code).

Any endpoint that needs sign-in answers `401 unauthorized` when the header is missing or the token isn't valid; the app then shows the sign-in screen.

### `GET /users/me`  (agreed)
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
Every field is always present. `units` is `lb` or `kg` (display only); `experience` is `beginner`, `intermediate`, `advanced` or `null`. A new user has `display_name: null`, `units: "lb"`, and `null` for every other field except `id` and `created_at` (`shared/fixtures/user_new.json`):
```json
{
  "id": "u_456",
  "display_name": null,
  "sex": null,
  "birth_year": null,
  "bodyweight_kg": null,
  "units": "lb",
  "experience": null,
  "created_at": "2026-11-03T18:00:00Z"
}
```

### `PUT /users/me`  (agreed: partial update)
Send only the fields to change; fields left out stay as they are. The response is the full user, as in `GET /users/me`.
```json
{"bodyweight_kg": 81.5, "units": "kg"}
```
Errors: `400 bad_request`, and nothing changes, when `units` is not `lb` or `kg`, `bodyweight_kg` is not a number above 0, `experience` is not one of the three values, or the body has any other field. Only `display_name`, `sex`, `birth_year`, `bodyweight_kg`, `units` and `experience` can be changed.

### `GET /exercises?q=bench&group=chest`
No auth: the library is the same for everyone. Both parameters are optional.
- **`q`:** an exercise matches when a word in its name or in one of its aliases starts with `q`. A word starts at the beginning, or after a space or a hyphen. Case doesn't matter, and spaces around `q` are ignored. So `squat` matches "Bulgarian Split Squat", and `up` matches "Push-up". Without `q` (or with a blank one), the whole library is returned.
- **Order:** first exercises whose name starts with `q`, then those where a later word of the name does, then those that match only through an alias. Ties are A–Z by name. Without `q`, everything is A–Z.
- **`group`:** one of the group IDs in `shared/muscles.json` (`chest`, `back`, `shoulders`, `arms`, `legs`, `core`). Keeps only exercises whose `groups` contain it. An unknown group is `400 bad_request`.

Each exercise also has two fields the server works out from `shared/muscles.json`:
- **`groups`:** the groups of all its `primary` muscles, the strongest muscle's group first, no repeats. Deadlift is in both Legs and Back.
- **`primary_muscles`:** the display names of the parent muscles of its `primary` muscles, strongest first, no repeats. The app shows them under the name: "Glutes, Lower back, Hamstrings · Barbell".
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
      ],
      "groups": ["chest"],
      "primary_muscles": ["Chest"]
    },
    {
      "id": "deadlift",
      "name": "Deadlift",
      "aliases": ["conventional deadlift", "dl"],
      "load_type": "barbell",
      "bodyweight_fraction": null,
      "muscles": [
        {"muscle_id": "glutes_max", "role": "primary", "weight": 1.0},
        {"muscle_id": "lower_back_erectors", "role": "primary", "weight": 0.9},
        {"muscle_id": "hamstrings", "role": "primary", "weight": 0.8},
        {"muscle_id": "quads", "role": "secondary", "weight": 0.5}
      ],
      "groups": ["legs", "back"],
      "primary_muscles": ["Glutes", "Lower back", "Hamstrings"]
    }
  ]
}
```
The example is in `shared/fixtures/exercises_search.json` (the muscle lists are shortened).

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

### `GET /templates`  (agreed)
This user's saved workouts, oldest-created first. A new user gets `{"templates": []}`.
```json
{
  "templates": [
    {
      "id": "3c9d7e1a-5b2f-4c8d-a6e4-7f8a9b0c1d2e",
      "name": "Push 1",
      "focus": "tricep focus",
      "exercises": [
        {"exercise_id": "barbell_bench_press", "target_sets": 4, "target_reps": 6, "rest_s": 180, "superset_group": null},
        {"exercise_id": "triceps_pushdown", "target_sets": 3, "target_reps": 12, "rest_s": 90, "superset_group": "a"},
        {"exercise_id": "plank", "target_sets": 3, "target_reps": null, "rest_s": 90, "superset_group": "a"}
      ],
      "last_done_at": "2026-11-02T17:02:00Z",
      "top_muscles": [
        {"muscle_id": "triceps", "name": "Triceps", "level": 4},
        {"muscle_id": "chest", "name": "Chest", "level": 3},
        {"muscle_id": "abs", "name": "Abs", "level": 3}
      ]
    }
  ]
}
```
- **`exercises`** are in the order the user does them. `target_reps` is `null` for a timed hold (plank). Neighbours with the same `superset_group` form one superset; `null` means no superset. Responses always include both fields.
- **`last_done_at`:** the `started_at` of the latest workout saved with this `template_id` (see `POST /workouts`), or `null` if never done.
- **`top_muscles`** (decided): the 3 parent muscles the workout works most, computed by the server and never stored. For each exercise and each of its muscles (every role), add `target_sets × weight` to that muscle's parent in `shared/muscles.json`. A head adds to its parent; a parent ID adds to itself; unknown IDs are skipped. Keep the 3 parents with the most work, ties in `muscles.json` order. `name` is the parent's display name. `level` (0–4, the chip's shade) is ceil(4 × work ÷ the top muscle's work), so the first chip is always 4. Example: 4 sets of Bench Press alone give Chest 4, Delts 2, Triceps 2.
- **UP NEXT** is the saved workout with the oldest `last_done_at` (never-done first); the app works that out from this list.

### `POST /templates`, `PUT /templates/{id}` and `DELETE /templates/{id}`  (agreed)
`POST` creates a saved workout. The `id` is a lowercase UUID made on the phone, so a retry is safe (`shared/fixtures/template_post.json`):
```json
{
  "id": "3c9d7e1a-5b2f-4c8d-a6e4-7f8a9b0c1d2e",
  "name": "Push 1",
  "focus": "tricep focus",
  "exercises": [
    {"exercise_id": "barbell_bench_press", "target_sets": 4, "target_reps": 6, "rest_s": 180},
    {"exercise_id": "triceps_pushdown", "target_sets": 3, "target_reps": 12, "rest_s": 90, "superset_group": "a"},
    {"exercise_id": "plank", "target_sets": 3, "rest_s": 90, "superset_group": "a"}
  ]
}
```
→ `201` with the full template, as in `GET /templates` (`last_done_at` is `null`). The same `id` again → `200` with the stored template; nothing changes.

`PUT /templates/{id}` takes the same body and replaces `name`, `focus` and `exercises`; `last_done_at` stays. The `id` in the path says which saved workout to change; the app also sends it in the body. → `200` with the full template.

`DELETE /templates/{id}` → `204` with no body, also when it is already gone. Past workouts that came from it stay.

The body (`POST` and `PUT`):
- `name`: required, 1–60 characters after trimming spaces. Names may repeat.
- `focus`: optional, up to 60 characters after trimming; empty or left out is `null`.
- `exercises`: 1–30 items. `exercise_id` must be in the library. `target_sets` 1–20. `target_reps` 1–100, or `null` or left out. `rest_s` 0–600. `superset_group` is text or `null`, at most 60 characters, and may be left out.

Errors: `400 bad_request` when `id` isn't a lowercase UUID or any rule above is broken. `404 not_found` for `PUT` with an unknown id, or another user's.

### `POST /workouts`  (agreed)
Saves the workout, its sets and this user's history for each exercise in it (UserExercise), in one transaction. The `id` fields are UUIDs made on the phone; repeating the request with the same IDs changes nothing. Daily stats and running totals are not saved; they come later with Home and Goals.
```json
{
  "id": "6f1c2b1e-4b7a-4c3e-9d2a-0a1b2c3d4e5f",
  "name": "Push 1",
  "template_id": "3c9d7e1a-5b2f-4c8d-a6e4-7f8a9b0c1d2e",
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
Decided: this body is the setup guide's example plus the fields its data model adds ("Fields to add to the kinds above"): the workout's and each set's phone-made `id`, `timezone` and `local_date`. `local_date` is the user's own day, so streaks and daily stats don't shift at midnight UTC. `rep_offsets_ms` (optional, per set) comes later with the camera. Response (decided): `201` with the saved workout in the `GET /workouts/{id}` shape. A repeated request with the same `id` saves nothing and returns `200` with the saved workout, even if the new body is different; the app treats both as success.

The fields:
- **Workout:** `id`, `name`, `started_at`, `ended_at`, `timezone` and `local_date` (`YYYY-MM-DD`) are required. `template_id` (the saved workout it started from) and `bodyweight_kg` may be `null` or left out.
- **Set:** `id`, `exercise_id`, `order`, `set_type`, and `reps` or `duration_s` (or both) are required. The rest may be `null` or left out. `set_type` is `warmup`, `working`, `dropset` or `failure`. `time_source` is `rest_timer`, `manual`, `camera` or `none`. `input` is `manual`, `text`, `voice`, `photo`, `camera` or `import`. `added_load_kg` is for bodyweight exercises: above 0 is added weight, below 0 is assistance.

Errors: `400 bad_request`, and nothing is saved, when:
- the workout's or a set's `id` is not a lowercase UUID, or two sets have the same `id` or the same `order`;
- an `exercise_id` is not in the library;
- `set_type`, `time_source` or `input` has a value not listed above;
- `effort_pct` is outside 0–100, or `weight_kg` is below 0;
- a set has neither `reps` nor `duration_s`;
- there are no sets, or more than 300;
- `ended_at` is before `started_at`, or `local_date` is not `YYYY-MM-DD`;
- `name`, `started_at`, `ended_at`, `timezone` or `local_date` is missing.

**History for each exercise.** A saved workout updates one UserExercise per exercise in it, as `GET /exercises/mine` shows:
- `use_count` goes up by 1 per workout, not per set.
- `last_used_at` becomes the workout's `ended_at`.
- `last_set` becomes the workout's last working or failure set of that exercise (highest `order`). With none, it is the exercise's last set.
- A workout that ended before the stored `last_used_at` (logged late) only adds to `use_count`; `last_used_at` and `last_set` stay.
- `best_e1rm_kg` and `best_e1rm_at` stay `null` until History and Goals are built.

**Last done for a saved workout.** When `template_id` names one of this user's saved workouts, its `last_done_at` becomes the workout's `started_at`, but only if that is later than the stored value. This also happens on a repeated request. An unknown `template_id` is not an error.

### `GET /workouts?limit=20&before=<timestamp>`  (agreed: `limit`; `before` comes with Home)
Newest `started_at` first. A summary per workout, without its sets. No workouts gives `{"workouts": []}`.
- `limit` (default 20) is built first. It must be 1–100; anything else is `400 bad_request`.
- `before` is **required by Home** and built with it: it returns workouts that started before that time, so the app can page back through all of history or jump to any date. Home's history is the core of the app ("where you are now, where you've been, where your muscles were"), so it must reach any point in time.
```json
{
  "workouts": [
    {"id": "6f1c2b1e-…", "name": "Push 1", "template_id": "3c9d7e1a-5b2f-4c8d-a6e4-7f8a9b0c1d2e",
     "started_at": "2026-11-02T17:02:00Z", "ended_at": "2026-11-02T19:33:00Z",
     "local_date": "2026-11-02", "set_count": 31, "exercise_count": 10}
  ]
}
```

### `GET /workouts/{id}`  (agreed)
The workout with every set, in the same fields as the `POST /workouts` body, plus `status` (always `finished` for now). Every workout and set field is present, `null` when it wasn't sent. Sets are sorted by `order`. Weights come back exactly as sent. An unknown id, or another user's, is `404 not_found`. Example: `shared/fixtures/workout_detail.json`.
