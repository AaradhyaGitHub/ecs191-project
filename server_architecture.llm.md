# Server architecture: Claude's notes

LLM-written summary of the team's setup guide. The human-written `server_architecture.md` takes precedence.

## Layers
| Layer | Holds | Rule |
|---|---|---|
| `main.py` | `create_app()`, registers one Blueprint per resource under `/api/v1/<resource>` | App Engine runs Gunicorn on `main:app` (no `entrypoint` in `app.yaml`) |
| `api/` | One Blueprint per resource | Parse the request, call a service, return JSON. Nothing else |
| `services/` | Business logic: `workout_service`, `auth` (`require_user`), later `stats_service`, `sharing_service`, `social_service` | No Flask imports, so it's testable without a request |
| `models.py` | Entity helpers: to and from Datastore | The only place that reads or writes Datastore |
| `seed/` | `exercises.json` plus a seed script | About 40 starter exercises |
| `tests/` | pytest | Pure logic first (scoring needs no database), then endpoints against the emulator |

**Deploy config:** `app.yaml` uses `runtime: python313`, `instance_class: F1`, `automatic_scaling.max_instances: 2`. `requirements.txt` has Flask, google-cloud-datastore and gunicorn; pytest goes in `requirements-dev.txt`. `.gcloudignore` excludes `.git`, virtual envs, `__pycache__`, `tests/` and `.env`.

**Local run:** the Datastore-mode emulator on `localhost:8081`, with `DATASTORE_EMULATOR_HOST` set; Flask on port 5000. Reset the emulator between tests with `POST http://localhost:8081/reset`.

## Key structure
Everything a user owns hangs under their `User` key, so one ancestor query fetches it all.
```
User/{user_id}
├── Workout/{uuid}              one session; id made on the phone
│   └── SetEntry/{uuid}         one logged set; id made on the phone
├── Template/{id}               a saved workout ("Push 1")
├── UserExercise/{slug}         this user's history with one exercise
├── Goal/{id}
├── DailyStats/{YYYY-MM-DD}     one row per local day trained
└── Stats/totals                running all-time totals and streak
Exercise/{slug}                 shared library; slugs are stable and never reused
SharedWorkout/{share_code}      root kind: no user in the key
Friendship/{user_a}_{user_b}    ids sorted, so each pair has one key
Challenge/{id}
shared/muscles.json             muscle IDs, names, groups (a file, not a kind)
```

## Kinds and fields
**User:** `display_name`, `sex`, `birth_year` (optional, for strength standards), `bodyweight_kg`, `units` (`lb` | `kg`, display only), `experience` (`beginner` | `intermediate` | `advanced`), `created_at`. Later: `share_consent {anonymous, decided_at}`, `handle` (unique, optional, kept apart from the phone number), `timezone`.

**Exercise** (shared, key = slug such as `barbell_bench_press`): `name`, `aliases` (help search and Smart Log: "bench", "BP"), `load_type` (`barbell` | `dumbbell` | `machine` | `cable` | `bodyweight` | `timed`; picks the set-entry screen), `bodyweight_fraction` (bodyweight exercises, e.g. about 0.64 for a push-up), `implement_count` (1 or 2 dumbbells; sets log one dumbbell's weight and volume multiplies by this; pending team agreement), `muscles` (list of `{muscle_id, role, weight}`; role is `primary` | `secondary` | `stabilizer`, weight 0–1 is what scoring multiplies by), `source` (`dataset` | `hand_tuned` | `user`), `weights_version`, `owner_id` (null = shared).

**Template** (a saved workout): `name`, `focus`, `exercises` (ordered `{exercise_id, target_sets, target_reps, rest_s}`), `last_done_at` (copied from the latest Workout, so the list needs no query). Later: `visibility` (`private` | `anonymous` | `public`), `shared_id`, `origin {shared_id, version}`.

**Workout** (one session): `template_id` (null for an empty workout), `name`, `status` (`active` | `finished`), `started_at`, `ended_at`, `bodyweight_kg` (snapshot), `timezone`, `local_date`.

**SetEntry** (the row everything else is computed from): `exercise_id`, `order` (position in the session), `superset_group` (same value = done back to back), `set_type` (`warmup` | `working` | `dropset` | `failure`; warm-ups don't count toward scores), `reps` (null for timed holds), `duration_s`, `weight_kg`, `added_load_kg` (bodyweight exercises: + weighted, − assisted), `effort_pct` (0–100; 100 = failure), `started_at`, `ended_at`, `rest_before_s`, `time_source` (`rest_timer` | `manual` | `camera` | `none`), `input` (`manual` | `text` | `voice` | `photo` | `camera` | `import`). Later: `rep_offsets_ms`.

**UserExercise** (`User/{id}/UserExercise/{slug}`, updated on every saved workout): `use_count`, `last_used_at`, `last_set {weight_kg, added_load_kg, reps, duration_s, effort_pct}` (pre-fills the next set), `best_e1rm_kg`, `best_e1rm_at`. Served by `GET /api/v1/exercises/mine`.

**DailyStats** (user's local date): `workouts`, `sets`, `reps`, `volume_kg`, `active_seconds`. **Stats/totals:** `total_volume_kg`, `total_reps`, `total_sets`, `current_streak`, `longest_streak`, `last_workout_date`.

**Goal:** `type` (`streak` | `volume` | `reps` | `sets` | `frequency` | `muscle_volume` | `strength`), `target`, `period` (`week` | `month` | `all_time` | `custom`, with `start_date` and `end_date`), `muscle_id`, `exercise_id`, `challenge_id`.

**SharedWorkout** (key = `share_code`, e.g. `k7Qm2xPa`): `visibility` (`anonymous` | `public`), `author_handle` (public only), `name`, `tags`, `exercises` (a full snapshot with no personal weights), `muscle_summary`, `version`, `status` (`active` | `removed`), `import_count`, `created_at`.

**Friendship:** `status` (`pending` | `accepted`), `requested_by`, `created_at`. **Challenge:** `metric`, `start_date`, `end_date`, `participants`, `created_by`, `status`. Scores are never stored; they're summed from each participant's DailyStats.

## Computed, never stored
Style (strength, hypertrophy or endurance, from reps and rest), e1RM, volume, each muscle's level per style, neglect flags, goal progress. Volume for bodyweight exercises = (bodyweight × `bodyweight_fraction` + added load) × reps. Volume for dumbbell exercises = weight × `implement_count` × reps (pending team agreement). Weights are stored as the exact kg value, never rounded. Bumping an exercise's `weights_version` lets history be recomputed.

## Write path
`POST /workouts` does three things in **one transaction**: save the workout and its sets, add to that day's DailyStats, update Stats/totals. If the user has consented, it then refreshes the shared copy of the template. Repeating the request with the same UUIDs changes nothing.

## Indexes
One composite index early, for an exercise's history (newest first):
```yaml
indexes:
- kind: SetEntry
  ancestor: yes
  properties:
  - name: exercise_id
  - name: started_at
    direction: desc
```

## Built for later
The data is shaped so these can be added without a migration: an anonymous workout library, public sharing links (`https://<domain>/w/{share_code}`), the strength / hypertrophy / endurance split, the exercise-to-muscle database, and goals and challenges with friends.
