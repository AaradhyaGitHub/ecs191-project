Status: Approved by Sasa, Nov 3, 2026
Branch: feat/43-saved-workouts

# Plan: saved workouts on Lift home (#43; spec `specs/saved-workouts.md`)
LLM-written. This is the plan for `specs/saved-workouts.md`. Sasa's spec wins where they differ. A *saved workout* is a `Template` in the code and the API. It fits #42's plan (`specs/log-workout.llm.md`, Draft) and assumes #42's recommendations.

## What the user sees (mockup: `client_architecture.llm.md`, "Lift screens", `LiftHomeView`)
- Large title "Lift". From #42, when needed: the "Resume workout" card and the outbox banner ("1 workout not uploaded yet"). Then CREATE: *Empty workout* (#8/#15) and *Custom plan* ("A multi-week program", disabled, "Soon" pill).
- SAVED WORKOUTS · n. One card per saved workout: name; "Tricep focus · 5 exercises"; "6 days ago"; up to 3 muscle chips; Start.
- The UP NEXT card has an accent border, an UP NEXT badge and an accent Start button. Other cards have a plain Start button.
- Start opens #42's active workout with the exercises and their target sets, reps and rest. While a workout is open, every Start is disabled, as Empty workout is (D18).
- After Finish (D10): Lift home shows a sheet "Save as a workout": Name (filled with the workout's name), Focus (optional), Save, Not now.
- Rename and delete (D11): long-press a card for a menu with Rename and Delete. Rename shows an alert with Name and Focus. Delete asks first.
- The mockup's Edit button stays hidden until editing a saved workout's exercises is built.

## Rules
- **UP NEXT:** never-done saved workouts first, then the oldest `last_done_at`. Ties go to the one first in server order. One saved workout is also UP NEXT.
- **Card order:** the UP NEXT card first, then the others in server order (oldest-created first). The server stores `created_at` and sorts in Python, so no new index.
- **"6 days ago":** calendar days in the phone's time zone. 0 → "Today", 1 → "Yesterday", 2–13 → "N days ago", 14–59 → "N weeks ago", 60+ → "N months ago" (days ÷ 30). Never done → "Not done yet". A future time → "Today".
- **Subtitle:** focus (left out when empty), then "1 exercise" or "N exercises", joined by " · ".
- **Top 3 muscles (server, never stored):** for each exercise and each of its muscles (all roles), add `target_sets × weight` to the muscle's parent. A head adds to its parent; a parent ID adds to itself. Unknown IDs are skipped. Keep the 3 parents with the most work; ties in `muscles.json` order. `level` = ceil(4 × work ÷ top work) (D3, D4). Items: `muscle_id`, `name`, `level` (D1).
- **Start → active workout:** `ActiveWorkout(name: template.name, templateId: template.id, …)`. Exercises go in template order. Neighbours with the same `superset_group` form one superset block. Each block gets the targets of its first exercise. Exercises not in the library are skipped.
- **Finished workout → saved workout:** exercises in the order of their first set. Warm-ups don't count. `target_sets` = the other sets (at least 1); `target_reps` = the most common reps, ties to the first logged, `null` for timed holds (D6); `rest_s` = the median `rest_before_s` of the 2nd and later sets, rounded to 15 s, else 90 s; `superset_group` copied (D7, D8).
- **Offer "Save as a workout"** only when the workout has sets and didn't start from a saved workout (D9).
- **Names:** trimmed, 1–60 characters. Focus: trimmed, up to 60; empty → `null`. Names may repeat.
- **Last done:** the workout's `started_at`; it only moves forward (D13). Right after Finish, the app also sets it on the card, so UP NEXT moves even while the workout waits in the outbox (D19).

## Empty and error states
- No saved workouts: one card, "No saved workouts yet. Finish a workout, then save it to start it again with one tap."
- Server unreachable, nothing loaded: "Couldn't load your saved workouts." and Try again. A list already on screen stays, with a short error line above it. Pull to refresh.
- No token (Release builds until sign-in exists; Debug signs in on launch, #42 OQ-9): "Sign in to see your saved workouts." No request is sent. The list loads once a token exists (D15).
- Delete confirm: "Delete Push 1? Your past workouts stay." Delete (red) and Cancel. If the server fails, the card comes back with an error line.
- Save or rename fails: the sheet or alert stays open with the error and Try again. The same id is sent again, so a retry is safe.

## Scope
- In: the four `/templates` endpoints, top muscles, `record_done`, Lift home cards, UP NEXT, Start, "Save as a workout", rename, delete, the disabled Custom plan tile.
- Later: editing a saved workout's exercises (and Edit), "Update Push 1 with today's changes", a smarter UP NEXT, every muscle on tap, saved workouts kept on the phone, sharing.

## Acceptance criteria
Server (`/api/v1/templates`, all need sign-in)
- **AC-1** No valid token → `401 unauthorized` on every endpoint. `GET` → `200 {"templates": [...]}`: only this user's, oldest-created first, API.md shape; a new user gets `[]`.
- **AC-2** `POST` with a new lowercase UUID `id` → `201` and the full template, `last_done_at` `null`, `top_muscles` computed. The same `id` again → `200` with the stored template; nothing changes.
- **AC-3** `POST`/`PUT` → `400 bad_request` when: `id` isn't a lowercase UUID; name blank or over 60; focus over 60; `exercises` empty or over 30; an unknown `exercise_id`; `target_sets` not 1–20; `target_reps` not 1–100 or `null`; `rest_s` not 0–600.
- **AC-4** `PUT /templates/{id}` replaces name, focus and exercises, keeps `last_done_at` → `200`. Unknown id, or another user's → `404 not_found`.
- **AC-5** `DELETE /templates/{id}` → `204`, no body, also when already gone. After it, `GET` doesn't list it.
- **AC-6** `top_muscles` follows the rule. Example: 4 sets of seed Bench Press (`chest_sternal` 1.0, `chest_clavicular` 0.6, `delts_front` 0.5, `triceps` 0.5, `serratus_anterior` 0.15) → Chest 4, Delts 2, Triceps 2 (Delts first by `muscles.json` order; Serratus 4th).
- **AC-7** `record_done(user_id, template_id, done_at)` sets `last_done_at` when it is empty or older; an older `done_at` changes nothing; a missing template is no error. Calling it twice is the same as once. After `POST /workouts` with a `template_id` (first time or a repeat), `GET /templates` shows the workout's `started_at`.

App (`MuscleMapKit`)
- **AC-8** `templates.json` decodes with muscle names; a `TemplateInput` encodes to `template_post.json`.
- **AC-9** `upNextID` and `homeOrder` follow "UP NEXT" and "Card order"; an empty list gives `nil` and `[]`.
- **AC-10** `lastDoneText` follows "6 days ago", also across a month end and a daylight-saving change.
- **AC-11** `cardSubtitle` follows "Subtitle".
- **AC-12** `templateInput(from:name:focus:)` follows "Finished workout → saved workout"; `nil` for an invalid name. `canSaveAsTemplate` follows "Offer".
- **AC-13** `activeWorkout(from:library:startedAt:)` follows "Start → active workout" (after #42's `ActiveWorkout` exists).

App (by hand on the simulator, screenshots in the PR)
- **AC-14** Lift home: cards, UP NEXT style, the Soon tile, and the empty, error and no-token states, next to #42's Resume card.
- **AC-15** Rename and delete work, with the confirm; the list reloads after each.
- **AC-16** (after #42) Start opens the active workout with targets; Start is disabled while one is open. After Finish, UP NEXT moves on, and "Save as a workout" adds a card.

## Interface
API.md: `/templates` **changes** from "proposed shape" to agreed: request and response details, `name` on `top_muscles` items, nullable `target_reps`, optional `superset_group`, UUID ids. It lands first in its own small PR.
```python
# server/services/template_service.py  (no Flask)
def top_muscles(items: list[dict], exercises: dict[str, dict], muscles: dict) -> list[dict]  # [{muscle_id, name, level}]
def clean_input(body: dict, exercises: dict[str, dict]) -> dict      # ApiError("bad_request")
def next_last_done(template: dict, done_at: datetime) -> dict | None   # pure; None = no change
def list_templates(user_id: str) -> list[dict]
def create_template(user_id: str, body: dict) -> tuple[dict, bool]    # (template, created)
def update_template(user_id: str, template_id: str, body: dict) -> dict   # ApiError("not_found")
def delete_template(user_id: str, template_id: str) -> None
def record_done(user_id: str, template_id: str, done_at: datetime) -> None
# server/models.py (hot spot): get_template, user_templates, put_template, delete_template,
#   change_template(user_id, id, change) -> dict | None   (one transaction: read, change(old), write if not None)
#   get_exercises(slugs) -> dict  — #42 plans the same helper; whichever lands first adds it, the other reuses it
# server/api/templates.py: bp; GET "", POST "", PUT "/<template_id>", DELETE "/<template_id>", all @require_user
```
```swift
// Models/Template.swift (hot spot, contract PR): TopMuscle gains `name: String`;
//   TemplateExercise.targetReps becomes `Int?` and gains `supersetGroup: String?` (init default nil)
// LiftCore/SavedWorkouts.swift (new)
public func upNextID(_ templates: [Template]) -> String?
public func homeOrder(_ templates: [Template]) -> [Template]
public func lastDoneText(_ date: Date?, now: Date, calendar: Calendar) -> String
public func cardSubtitle(_ template: Template) -> String
public func cleanName(_ text: String) -> String?
public func canSaveAsTemplate(_ workout: Workout) -> Bool
public func templateInput(from workout: Workout, name: String, focus: String?) -> TemplateInput?
public func activeWorkout(from template: Template, library: [Exercise], startedAt: Date) -> ActiveWorkout
```
`APIClient` already has `templates()`, `createTemplate`, `updateTemplate`, `deleteTemplate`; no change. No `WorkoutPlan` type: #42's `ActiveWorkout` is the start value.

## What this feature needs from #42 (D17), and who owns what
| Piece | Owner | Need |
|---|---|---|
| `WorkoutBlock` | #42 | Also holds `targetReps: Int?` and `restS: Int?` (nil for an empty workout) |
| `ActiveWorkout.add` | #42 | Takes `targetSets:`, `targetReps:`, `restS:` (all default nil), so this feature never edits #42's file |
| `SetDraft.prefill` | #42 | Uses the block's `targetReps` and `restS` before `LastSet` and defaults |
| Starting a workout from Lift | #42 | One entry point that takes an `ActiveWorkout`, saves it to `WorkoutStorage` and opens `ActiveWorkoutView`. The picker's Add and this feature's Start both call it. It also says whether a workout is open, to disable Start |
| Finish | #42 | After `WorkoutOutbox.finish`, `ActiveWorkoutView` calls `onFinished(Workout)` with `finished(at:)`. Discard calls nothing |
| `LiftView.swift` | both | #42: Resume card, outbox banner, presenting. #43: the Custom plan tile and `SavedWorkoutsSection` (two insertions) |
| `record_done` and `next_last_done` | #43 | Tested here |
| The call in `workout_service.save_workout` | whichever merges second | One line after `models.save_workout` returns, on every request, created or repeat (D13). #42's transaction doesn't change |

## Files
- Contract PR (hot spots): `API.md` (the `/templates` section, plus the `template_id` value in the two workout examples, D2); `shared/fixtures/templates.json`, `workout_post.json`, `workout_detail.json`, `workouts_list.json` (the `template_id` value only); new `shared/fixtures/template_post.json`; `ios/MuscleMapKit/Sources/Models/Template.swift`. #42's contract PR touches `API.md`, `user_new.json`, `User.swift` and `FixtureTests.swift`, and none of these fixture files.
- Server: new `server/api/templates.py`, `server/services/template_service.py`; changed `server/models.py` (hot spot: Template helpers), `server/main.py` (hot spot: one line). `server/index.yaml` doesn't change.
- iOS package: new `Sources/LiftCore/SavedWorkouts.swift`. `Package.swift` doesn't change.
- iOS app (`Features/Lift/`): new `SavedWorkoutsSection.swift`, `SavedWorkoutCard.swift`, `SavedWorkoutsModel.swift` (`@Observable`), `SaveAsWorkoutSheet.swift`; changed `LiftView.swift` (two insertions), `PreviewData/PreviewData.swift` (muscle names; #42 changes it too). New files go in through the Xcode MCP.
- **Issue #43 owns only these files** (#42 owns the rest of `LiftCore/` and `Features/Lift/`): `server/api/templates.py`, `server/services/template_service.py`, `server/tests/services/test_template_service.py`, `server/tests/api/test_templates.py`, `shared/fixtures/template_post.json`, `ios/MuscleMapKit/Sources/LiftCore/SavedWorkouts.swift`, `ios/MuscleMapKit/Tests/LiftCoreTests/SavedWorkoutsTests.swift`, and in `ios/MuscleMap/Features/Lift/`: `SavedWorkoutsSection.swift`, `SavedWorkoutCard.swift`, `SavedWorkoutsModel.swift`, `SaveAsWorkoutSheet.swift`. Shared, small edits: `LiftView.swift`, `PreviewData.swift` and the hot spots above.

## Reuse
`require_user`, `ApiError`, `exercise_service.load_muscles()` (#8), `models.get_exercises` (#42), #42's shared ISO helper (`services.timestamps.iso`). `APIClient` template methods, `searchExercises()` for the library, `Template`, `TemplateInput`, `ClientID`, `Workout`, #42's `ActiveWorkout`. `CardView` (`isHighlighted`), `MuscleChip`, `PrimaryButton`, `SectionHeader`, `Theme`, `PreviewData.templates`. SwiftUI `contextMenu`, `alert` with text fields, `confirmationDialog`, `refreshable`. No new dependency.

## Tests
- Server unit (AC-3, 6, 7 logic): `server/tests/services/test_template_service.py`, with `seed/exercises.json` and `server/muscles.json` in memory.
- Server emulator (AC-1–5, 7): `server/tests/api/test_templates.py`. The `POST /workouts` part of AC-7 is added once both features are merged.
- iOS unit: AC-8 in `Tests/ModelsTests/FixtureTests.swift`; AC-9–13 in `Tests/LiftCoreTests/SavedWorkoutsTests.swift`.
- AC-14–16 by hand; a preview for each state.

## Build order (each step a commit that leaves things working)
1. **Contract PR** (now).
2. **Server** (after the picker PR #45 merges, for `load_muscles`): Template helpers, service, Blueprint, `record_done`.
3. **LiftCore rules:** all but `activeWorkout(from:)` now; that one after #42's `ActiveWorkout` exists.
4. **Screens** (after #42 merges): section, cards, states, rename, delete, Custom plan tile, Start into the active workout, the "Save as a workout" sheet, and the `record_done` line if #42 didn't add it.
- Where: the server part builds in the lane folder `/Users/santunovic/Developer/ecs191-impl-2` (its Datastore emulator is on `localhost:8083`). Paths in this plan stay relative to the repo root.

## Filled in from design docs and decisions
- UP NEXT = oldest `last_done_at`, never-done first, worked out by the app: llm.md Decisions (Sasa, Nov 3); API.md `GET /templates`.
- Template ids are lowercase UUIDs made on the phone: llm.md Decisions; API.md "IDs"; `TemplateInput.id`.
- Top 3 chips: parent muscles, `target_sets × weight`, shaded 0–4, computed by the server and never stored; heads roll up to parents: llm.md Decisions.
- `last_done_at` is copied onto the Template so the list needs no query: `server_architecture.llm.md`. #42 leaves it to this feature: `log-workout.llm.md` OQ-3.
- Card contents, UP NEXT style, Edit, Custom plan "Soon": `client_architecture.llm.md` "Lift screens"; llm.md Decisions.
- Resume card, one active workout, Empty workout disabled, outbox, Debug sign-in: `log-workout.llm.md` (OQ-9, OQ-16).
- Lists wrapped, error codes, `201`/`200`/`204`, `404` for another user's id: API.md "Conventions"; `log-workout.llm.md` OQ-6.
- Layers (no Flask in services; only `models.py` touches Datastore): `server_architecture.llm.md`; CLAUDE.md.
- `LiftView` stays the name of the Lift home (the notes call it `LiftHomeView`); no rename, so #8 and #42 don't clash.

## Test-writer may read
- `server/services/template_service.py`
- `server/api/templates.py`
- `server/models.py`
- `server/services/auth.py`
- `server/services/exercise_service.py`
- `ios/MuscleMapKit/Sources/LiftCore/SavedWorkouts.swift`
- `ios/MuscleMapKit/Sources/LiftCore/ActiveWorkout.swift` (#42's; holds `ActiveWorkout` and `WorkoutBlock`)
- `ios/MuscleMapKit/Sources/Models/Template.swift`
- `ios/MuscleMapKit/Sources/Models/Workout.swift`
- `ios/MuscleMapKit/Sources/Models/Exercise.swift`
- `ios/MuscleMapKit/Sources/Models/APIJSON.swift`

## Decided (Sasa, Nov 3, 2026)
A reference such as "D13" in the plan points to this list. Sasa took every recommendation.
1. **Chip names:** the server adds `name` to each `top_muscles` item, as `primary_muscles` does.
2. **`tpl_push1`:** this contract PR changes it to a lowercase UUID in `templates.json`, the three `workout_*.json` fixtures and the two API.md workout examples. #42's contract PR leaves those lines alone.
3. **Chip shade:** relative to the top muscle, ceil(4 × work ÷ top work). The top chip is always 4.
4. **Which work counts:** all roles; heads of one parent add up.
5. **Exercises on Start:** the app gets the public library (`GET /exercises`) once per launch and looks up the IDs.
6. **Timed holds:** `target_reps` may be `null`. Target duration comes later.
7. **Supersets:** optional `superset_group` on template exercises, now.
8. **Targets from a finished workout:** as in Rules (non-warm-up count, most common reps, median rest rounded to 15 s, 90 s default).
9. **Offer "Save as a workout"** only for workouts not started from a saved workout.
10. **"Save as a workout" UI:** a sheet on Lift home after Finish, through `onFinished`.
11. **Rename and delete UI:** a long-press menu. The Edit button waits for exercise editing.
12. **Card order:** UP NEXT first, then oldest-created.
13. **Recording "last done":** the workout's `started_at`. `workout_service.save_workout` calls `record_done` after `models.save_workout`, on every request. It uses its own small transaction, only moves forward and is safe to repeat. Whichever feature merges second adds that line.
14. **Endpoint details:** repeat `POST` → `200`; `PUT` full replace; `DELETE` of a missing id → `204`; the AC-3 limits; names may repeat; another user's id → `404`.
15. **No token:** Debug signs in on launch (#42). Without a token, the card says "Sign in to see your saved workouts" and no request is sent.
16. **Small text rules:** as in Rules ("6 days ago" steps, "1 exercise", UP NEXT on a single card).
17. **Additions to #42's plan:** #42's plan adds them now (the table above). No file has two owners.
18. **Start while a workout is open:** disabled, as Empty workout is.
19. **UP NEXT right after Finish:** the app sets `last_done_at` on the card at once; the server catches up when the outbox sends.

## Open questions
None.

## Progress
- [x] Plan approved (369fb8b)
- [x] Scaffold (9e214e9, server + LiftCore rules; part 2: fb75854, activeWorkout(from:) after merging main 81bbc49 and the record_done call 702c180)
- [x] Tests red (75d4aa1; part 2: 758a6ff)
- [x] Build green (abf9f83, server + LiftCore rules; activeWorkout(from:), screens and the record_done call after #42)
- [ ] Review
- [ ] PR
