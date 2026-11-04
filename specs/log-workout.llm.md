Status: Approved by Sasa, Nov 3, 2026
Branch: feat/42-log-workout

# Plan: log a workout (#42; spec `specs/log-workout.md`)
LLM-written. This is the plan for Sasa's spec. The spec wins where they differ. "D-n" points to a decision at the end (Sasa, Nov 3, 2026). Plan B (`specs/saved-workouts.llm.md`, #43) relies on the parts marked "for #43".

## What the user sees (mockups: `client_architecture.llm.md`, "Lift screens")
- **`ActiveWorkoutView`:** "‹ Lift" back button, workout clock, workout name, a segmented progress bar. An UP NEXT card: one exercise, or a superset ("Push-up + Inverted Row", "Round 2 · rest 90 s after round"), with Start. Below it, "then" and the next exercise. Then DONE · n, each finished exercise with its set count. At the bottom: Add exercise and Finish.
- **`SetLogView`** (title is the exercise, or "Superset A"): chips All plus one per exercise; "7 sets · in the order you did them". Each row: badge (W warm-up, F failure, else a number), exercise, rest before ("2:30 rest", or "First set · 6:02 PM"), reps, load ("BW", "BW +10 lb", "155 lb", "45 s"), an effort battery. A rest strip (countdown, −30s, +30s, Skip) and a + button that opens the sheet.
- **`SetEntrySheet`:** set number and type (Warm-up, Working, Drop set, Failure). A hero weight with "Same as last set" and "45 bar + 55 per side". The plate loader (barbells only), a REPS stepper (seconds for timed holds), REST AFTER ±30, EFFORT 60–100 %, and a primary button "Log 6 × 155 lb".

## Rules
- **Blocks.** "Add" in the picker adds the picks as blocks (a *block* is one exercise, or one superset). Without the superset flag, each pick is its own block, in tap order. With it, all picks form one superset block. Superset groups get letters in the order they are added: "a", "b", …
- **Up next.** UP NEXT is the first block that is not done. "then" is the block after it. A block is done when the user taps Done in its set log, or when each of its exercises has its target number of non-warm-up sets (templates only) (D-10). A done block can be opened again to log more.
- **Supersets and rounds.** In a superset, the sheet opens on the next exercise of the round: A, B, A, B… A *round* is one set of each exercise. The rest timer does not run between exercises in a round. It runs after the last one (D-11).
- **Rest timer.** Logging a set starts the timer with the sheet's REST AFTER value. The timer keeps an end time, so it survives an app restart. −30s and +30s change it and never go below 0. Skip stops it. At 0 the phone vibrates (app open only).
- **Set data.** `order` is 1, 2, 3… in the order sets are logged. Deleting a set renumbers the rest. `ended_at` is the time of the Log tap. `started_at` is null. `rest_before_s` is the time since the previous set's Log tap (null for the first set) (D-12).
- **Set types and effort.** Badge W for warm-up, F for failure, else the set's number among that exercise's non-warm-up sets. Effort is 60–100 % in steps of 10. Failure sets effort to 100.
- **Weight entry by load type** (one function, `entryKind(for:)`): barbell = plate loader; dumbbell = one dumbbell's weight, labelled "per dumbbell"; machine and cable = weight stepper; bodyweight = BW ± load (`added_load_kg`, 0 = plain BW, `weight_kg` null); timed = seconds (`duration_s`, `reps` null). Steppers move 5 lb or 2.5 kg, 5 s for seconds, 1 for reps.
- **Plates.** Reuse `PlateSet` (45 lb bar or 20 kg bar). Plate buttons add a pair. Tapping the bar removes the last pair. Reset leaves the empty bar. The breakdown text is "<bar> bar + <per side> per side". A typed weight that plates can't make shows the nearest lower load on the bar.
- **lb/kg.** The sheet shows the user's unit (from `GET /users/me`, lb until known). Every weight is sent as exact kg (`Weight`); only the display rounds (D-14).
- **Pre-fill.** The sheet's start values come from the block's targets first (`targetReps` for reps, `restS` for REST AFTER; set by a saved workout), then the last set of that exercise in this workout, then `last_set` in `GET /exercises/mine`, then defaults (D-13). "Same as last set" uses the last set only.
- **Starting a workout.** One entry point, `LiftSession.start(_:)`, takes an `ActiveWorkout`, saves it to `WorkoutStorage` and opens `ActiveWorkoutView`. The picker's Add uses it; #43's Start will too. `isWorkoutOpen` tells Lift to disable both while a workout is open. After Finish, `ActiveWorkoutView` calls `onFinished(Workout)`; Discard calls nothing (for #43).
- **What Finish sends.** `POST /workouts` with the workout (`id`, `name`, `template_id`, `started_at`, `ended_at` = Finish time, `timezone` and `local_date` from the start, `bodyweight_kg` from the profile or null) and all its sets. It is sent once; a retry sends the same ids and body.

## Empty and error states
- **No sets yet:** UP NEXT shows the first block; the set log says "No sets yet".
- **Finish with no sets:** an alert "No sets logged. Discard this workout?" with Discard and Keep going. Nothing is sent (D-16).
- **Finish while offline:** the workout moves to an *outbox* (finished workouts not yet sent, kept on the phone). Lift shows "1 workout not uploaded yet". The app tries again on launch, when it comes to the foreground, when Lift appears, and with "Try again".
- **App closed mid-workout:** the active workout is saved on the phone after every change. On the next launch, Lift shows a "Resume workout" card with the clock. Only one active workout exists at a time; Empty workout is disabled while one is open (D-16).
- **Server rejects (400):** the workout stays in the outbox, marked "Couldn't save: <server message>", with Try again and Delete (with confirmation). It is not retried by itself. 401, 5xx and no connection are retried (D-17).

## Scope for this feature
- **In:** the three screens; edit a logged set (tap) and delete it (swipe) (D-18); phone storage and outbox; `POST /workouts` with UserExercise; `GET /workouts?limit=`, `GET /workouts/{id}`, `GET`/`PUT /users/me`; `template_id` passes through from `ActiveWorkout` to the server; block targets, the start entry point and `onFinished` for #43.
- **Later:** start from a saved workout (#43 builds the `ActiveWorkout` with `templateId`, name and targets). `Template.last_done_at` (D-3): #43's decision 13 has `workout_service.save_workout` call `template_service.record_done` once after `models.save_workout` returns, on every request; whichever of #42 and #43 merges second adds that one line. Also later: DailyStats and Stats/totals (D-1); `best_e1rm` (D-2); `GET /workouts?before=` (Home); rename the workout; reorder or remove exercises; rest notification in the background; body-weight and units screens (D-15).

## Filled in from design docs and decisions
- Active workout on the phone (SwiftData), sent once on Finish; ids are lowercase UUIDs made on the phone: llm.md Decisions; API.md "Conventions".
- Repeat `POST /workouts` → `200` with the same body, first time `201`; response in the `GET /workouts/{id}` shape: llm.md Decisions; API.md.
- Weights exact kg, rounded only for display; plate sets for lb and kg: llm.md Decisions; `LiftCore/PlateSet.swift`.
- Dumbbells log one dumbbell's weight: llm.md, **pending team agreement** (D-22).
- Workout `status` is always `finished` for now: llm.md Decisions.
- `PUT /users/me` is a partial update: llm.md Decisions; API.md.
- Set fields, set types, `time_source`, `input`, UserExercise fields: `server_architecture.llm.md`, "Kinds and fields".
- Screen content, badges, effort battery, rest strip, plate loader, "Log 6 × 155 lb": `client_architecture.llm.md`, "Lift screens" and "Shared components".
- Index for an ancestor query sorted by time: `server_architecture.llm.md`, "Indexes" (same pattern).

## Acceptance criteria
Server (`/api/v1`)
- **AC-1** `POST /workouts`, `GET /workouts`, `GET /workouts/{id}`, `GET`/`PUT /users/me` without a valid token return `401 unauthorized`.
- **AC-2** `POST /workouts` with `shared/fixtures/workout_post.json` returns `201` and the workout in the `GET /workouts/{id}` shape: `status: "finished"`, every set field present (null when not sent), sets sorted by `order`, weights exactly as sent, `template_id` as sent (or null).
- **AC-3** The same request again returns `200` and the same body. A request with a saved `id` and a different body also returns `200` with the saved workout. Neither changes any stored data.
- **AC-4** These return `400 bad_request` and save nothing: workout or set `id` not a lowercase UUID; two sets with the same `id` or `order`; unknown `exercise_id`; unknown `set_type`, `time_source` or `input`; `effort_pct` outside 0–100; a negative weight; a set with neither `reps` nor `duration_s`; no sets; more than 300 sets; `ended_at` before `started_at`; `local_date` not `YYYY-MM-DD`; a missing `name`, `started_at`, `ended_at`, `timezone` or `local_date`.
- **AC-5** A saved workout updates one UserExercise per exercise in it: `use_count` +1 per workout (not per set); `last_used_at` = the workout's `ended_at`; `last_set` = the highest-`order` working or failure set, else its last set (D-4). `GET /exercises/mine` shows the result.
- **AC-6** A workout that ended before the stored `last_used_at` adds 1 to `use_count` but keeps `last_used_at` and `last_set`.
- **AC-7** `GET /workouts/{id}` returns the saved workout. An unknown id, or another user's, returns `404 not_found` (D-6).
- **AC-8** `GET /workouts` returns `{"workouts": [...]}`, newest `started_at` first, at most `limit` (default 20, 1–100, else `400`), in the API.md summary shape with `set_count` and `exercise_count`, without sets. No workouts gives `[]`.
- **AC-9** `GET /users/me` returns every API.md field. A new user gets `display_name: null`, `units: "lb"`, and null for the rest except `id` and `created_at` (D-8).
- **AC-10** `PUT /users/me` changes only the fields sent and returns the full user. `units` not `lb`/`kg`, `bodyweight_kg` not a number above 0, an unknown `experience`, or an unknown field returns `400` and changes nothing.

App logic (`swift test`)
- **AC-11** `User` decodes `shared/fixtures/user_new.json` (`displayName == nil`, units lb).
- **AC-12** `ActiveWorkout.add(_:asSuperset:targetSets:targetReps:restS:)` makes blocks as in "Rules": one block per pick, or one superset block with the next free letter. The three targets default to nil and are copied onto each new block.
- **AC-13** `upNext`, `then` and `done` follow "Up next". `markDone` moves a block to `done`; reaching every target set does too.
- **AC-14** `log` gives `order` 1…n, `endedAt` = the log time, `restBeforeS` = seconds since the previous set (nil for the first), the block's `supersetGroup`. `update` keeps the id. `delete` renumbers `order`.
- **AC-15** In a superset block, `nextExercise` goes A, B, A, B; `round` counts rounds; `startsRest` is true only after the last exercise of a round.
- **AC-16** `RestTimer`: `remaining(at:)`, `add(30)`, `add(-30)` (never below 0), `skip`; it encodes and decodes with the same end time.
- **AC-17** `entryKind(for:)` per load type as in "Rules". `SetDraft.entry` gives null `weightKg` for bodyweight and null `reps` for timed. Failure sets effort to 100. `SetDraft.prefill` uses the block's `targetReps` and `restS` first, then this workout's last set, then `LastSet`, then defaults.
- **AC-18** `PlateLoad` adds pairs, `removeLast`, `reset`, `total`; 155 lb gives "45 bar + 55 per side"; 100 kg gives "20 bar + 40 per side"; `nearestLoad` for 157 lb is 155 lb.
- **AC-19** Texts: `badge` ("W", "F", "2"), `loadText` ("BW", "BW +10 lb", "155 lb", "45 s"), `logButtonTitle` ("Log 6 × 155 lb"), `restText` ("First set · 6:02 PM", "2:30 rest").
- **AC-20** `finished(at:)` returns a `Workout` with `endedAt`, all sets, `templateId`, `timezone` and `localDate` from the start; nil with no sets.
- **AC-21** `WorkoutStorage` (in-memory SwiftData) saves, loads and clears the active workout unchanged, and keeps outbox items in the order they were added.
- **AC-22** `WorkoutOutbox.finish` moves the workout to the outbox and clears the active one. `sendPending` sends oldest first, with the same id and body each time. Success removes the item. No connection, 401 and 5xx keep it. 400 keeps it, marked rejected with the message, and later automatic sends skip it; `retry(id)` sends it again.
- **AC-22a** `LiftSession.start` saves the workout to `WorkoutStorage` and sets `isWorkoutOpen`; a second `start` while one is open returns false and changes nothing. `finish(at:)` calls `WorkoutOutbox.finish` and returns the `Workout`; nil with no sets. `discard()` clears it and adds nothing to the outbox.

App screens (by hand on the simulator, screenshots in the PR)
- **AC-23** "Add" in the picker opens `ActiveWorkoutView` through `LiftSession.start`. Finish calls `onFinished`; Discard does not. Add exercise opens the picker and adds blocks at the end.
- **AC-24** A full log: the sheet, the rest strip, the set log with filter chips, edit and delete.
- **AC-25** Finish against the local server saves it; the exercises then show in the picker's "Your exercises". Finish with the server stopped shows the outbox banner; starting the server and tapping Try again uploads it. A force-quit mid-workout resumes.

## Interface
**Contract (API.md, own small PR first):** `POST /workouts` changes: drop DailyStats and totals from its text (D-1), add the UserExercise update, the `400` cases of AC-4, and "response has every set field". `GET /workouts?limit=` and `GET /workouts/{id}` become agreed (`before` stays for Home; `404` rule). `GET`/`PUT /users/me` become agreed: new-user defaults, `display_name` nullable, the `400` cases of AC-10. New fixture `shared/fixtures/user_new.json`. `Models/User.swift`: `displayName: String?`.
```python
# server/services/workout_service.py (no Flask)
def validate_workout(body: dict, known_exercise_ids: set[str]) -> dict    # ApiError("bad_request") or the clean workout
def merge_user_exercise(old: dict | None, workout: dict, sets: list[dict]) -> dict   # pure; AC-5, AC-6
def to_detail(workout: dict, sets: list[dict]) -> dict; def to_summary(workout: dict, sets: list[dict]) -> dict
def save_workout(user_id: str, body: dict) -> tuple[dict, bool]          # (detail, created); #43 adds record_done after models.save_workout
def get_workout(user_id: str, workout_id: str) -> dict                   # ApiError("not_found")
def list_workouts(user_id: str, limit: int = 20) -> list[dict]
# server/services/user_service.py: get_me(user_id) -> dict; update_me(user_id, body: dict) -> dict
# server/models.py (hot spot): get_exercises(slugs) -> dict; save_workout(user_id, workout, sets, merge) -> tuple[dict, list[dict], bool]
#   (one transaction: if the Workout exists, return it unchanged; else read UserExercises, call merge, write all);
#   get_workout(user_id, id) -> tuple[dict, list[dict]] | None; list_workouts(user_id, limit) -> list[dict]; update_user(user_id, fields) -> dict
# server/api/workouts.py: bp; POST "", GET "", GET "/<workout_id>". server/api/users.py: bp; GET "/me", PUT "/me"
```
```swift
// LiftCore (Package.swift hot spot: LiftCore also depends on Networking)
public struct WorkoutBlock: Codable, Identifiable, Equatable, Sendable { id; exercises: [Exercise]; supersetGroup: String?; targetSets: Int?; targetReps: Int?; restS: Int?; isDone: Bool }
public struct ActiveWorkout: Codable, Equatable, Sendable {   // ActiveWorkout.swift
    public init(name: String = "Workout", templateId: String? = nil, startedAt: Date, timeZone: TimeZone = .current, bodyweightKg: Double? = nil)
    blocks, sets; mutating add(_ exercises: [Exercise], asSuperset: Bool, targetSets: Int? = nil, targetReps: Int? = nil, restS: Int? = nil); log(_ draft: SetDraft, in blockID: String, at: Date) -> SetEntry
    mutating update(_ set: SetEntry); delete(setID:); markDone(blockID:); upNext, then, done; nextExercise(in:), round(in:), startsRest(after:)
    func finished(at: Date) -> Workout? }
public enum EntryKind; public func entryKind(for: LoadType) -> EntryKind; public struct SetDraft { prefill(…); entry(...) }   // SetEntryRules.swift
public struct PlateLoad { add, removeLast, reset, total, breakdown, nearestLoad }   // PlateSet.swift (extend)
public struct RestTimer: Codable { start, remaining(at:), add(_:), skip }            // RestTimer.swift
public func badge, loadText, logButtonTitle, restText                              // SetTexts.swift
public protocol WorkoutStorage; public final class SwiftDataWorkoutStorage          // WorkoutStorage.swift (@Model with a JSON blob, D-20)
@MainActor public final class WorkoutOutbox { init(storage:, sender: any WorkoutSending); finish(_:at:); sendPending(); retry(id:); delete(id:); items }
public protocol WorkoutSending: Sendable { func saveWorkout(_: Workout) async throws -> Workout }  // APIClient conforms
@MainActor @Observable public final class LiftSession { init(storage:, outbox:); active: ActiveWorkout?; isWorkoutOpen: Bool   // LiftSession.swift
    func start(_: ActiveWorkout) -> Bool; finish(at: Date) -> Workout?; discard() }
// App: ActiveWorkoutView(session: LiftSession, onFinished: @escaping (Workout) -> Void)
```

## Files
- Contract PR: `API.md`, `shared/fixtures/user_new.json`, `ios/MuscleMapKit/Sources/Models/User.swift`, `ios/MuscleMapKit/Tests/ModelsTests/FixtureTests.swift` (all hot spots). It leaves the `template_id` values in the workout fixtures to #43's contract PR.
- Server: new `server/api/workouts.py`, `server/api/users.py`, `server/services/workout_service.py`, `server/services/user_service.py`; changed `server/main.py` (2 lines), `server/models.py` (workout and user helpers), `server/index.yaml` (one index: `Workout`, ancestor, `started_at` desc). All three are hot spots.
- iOS package: new `Sources/LiftCore/{ActiveWorkout,SetEntryRules,SetTexts,RestTimer,WorkoutStorage,WorkoutOutbox,LiftSession}.swift`; changed `PlateSet.swift`; `ios/MuscleMapKit/Package.swift` one line (hot spot).
- Added to Issue #42's paths: `ios/MuscleMapKit/Package.swift`, `ios/MuscleMapKit/Sources/Models/User.swift`, `ios/MuscleMap/DesignSystem/Components/`.
- iOS app: new `Features/Lift/{ActiveWorkoutView,ActiveWorkoutModel,SetLogView,SetEntrySheet}.swift`; new `DesignSystem/Components/{EffortBattery,RestStrip,PlateLoader}.swift`; changed `Features/Lift/LiftView.swift` (resume card, outbox banner, presenting the workout; #43 adds two insertions), `PreviewData/PreviewData.swift`, `App/MuscleMapApp.swift` (hot spot: model container, outbox, retry on foreground); delete `Features/Lift/PickedExercisesPlaceholder.swift`. New files go in through the Xcode MCP.

## Reuse
Server: `require_user`, `ApiError`, `models.client()`, `user_key`, `get_user`; from the picker branch `user_exercise_key`, `user_exercises` and `exercise_service._iso` (move it to a shared helper). The picker's `models.put_user_exercise` stays as a test helper for seeding history; real writes now come from `models.save_workout`. iOS: `Workout`, `SetEntry`, `SetType`, `ClientID`, `APIJSON`, `Weight`, `PlateSet`, `LastSet`, `APIClient.saveWorkout/workouts/workout/me/updateMe`, the picker (`ExercisePickerView`, `ExerciseSelection`), `CardView`, `PrimaryButton`, `SectionHeader`, `Theme`. SwiftData is Apple's (macOS 14+ matches `Package.swift`). No new dependency.

## Tests
- Server unit: AC-4–6 in `server/tests/services/test_workout_service.py`; AC-10 rules in `server/tests/services/test_user_service.py`.
- Server emulator: AC-1–3, 7, 8 in `server/tests/api/test_workouts.py`; AC-9, 10 in `server/tests/api/test_users.py`.
- iOS unit: AC-11 in `Tests/ModelsTests/FixtureTests.swift`; AC-12–20 in `Tests/LiftCoreTests/{ActiveWorkoutTests,SetEntryRulesTests,PlateLoadTests,RestTimerTests}.swift`; AC-21, 22, 22a in `Tests/LiftCoreTests/{WorkoutOutboxTests,LiftSessionTests}.swift` (fake sender).
- AC-23–25 by hand; a UI smoke test comes later.

## Build order
1. Contract PR (small, alone). 2. Server: `users/me` and `GET /workouts` first; `POST /workouts` with UserExercise after #8 merges (it needs the picker's `models.py` helpers; rebase then). 3. LiftCore rules. 4. Phone storage and outbox. 5. Screens.
- Stages 2 and 3–4 run in parallel after stage 1. Stage 5 waits for the picker (#8/#15) to merge. Each stage is a commit that builds and passes its tests.
- The build runs in lane 1: `/Users/santunovic/Developer/ecs191-impl-1` (Datastore emulator on `localhost:8082`). Paths in this plan stay relative to the repo root.

## Test-writer may read
- `server/services/workout_service.py`
- `server/services/user_service.py`
- `server/api/workouts.py`
- `server/api/users.py`
- `server/models.py`
- `server/services/auth.py`
- `ios/MuscleMapKit/Sources/LiftCore/ActiveWorkout.swift`
- `ios/MuscleMapKit/Sources/LiftCore/SetEntryRules.swift`
- `ios/MuscleMapKit/Sources/LiftCore/SetTexts.swift`
- `ios/MuscleMapKit/Sources/LiftCore/PlateSet.swift`
- `ios/MuscleMapKit/Sources/LiftCore/RestTimer.swift`
- `ios/MuscleMapKit/Sources/LiftCore/WorkoutStorage.swift`
- `ios/MuscleMapKit/Sources/LiftCore/WorkoutOutbox.swift`
- `ios/MuscleMapKit/Sources/LiftCore/LiftSession.swift`
- `ios/MuscleMapKit/Sources/Models/Workout.swift`
- `ios/MuscleMapKit/Sources/Models/User.swift`
- `ios/MuscleMapKit/Sources/Models/Exercise.swift`
- `ios/MuscleMapKit/Sources/Models/Weight.swift`
- `ios/MuscleMapKit/Sources/Networking/APIClient.swift`

## Decided (Sasa, Nov 3, 2026)
1. **DailyStats and totals.** (a) Now, in the same transaction. (b) Later, with Home/Goals. **Decided: (b).** Volume needs the dumbbell rule and streak rules are not set; both can be rebuilt from stored sets.
2. **`best_e1rm_kg`.** (a) Epley now. (b) Null until History/Goals. **Decided: (b).**
3. **`Template.last_done_at`.** (a) Update it now if the template exists. (b) With spec B. **Decided: (b).** `template_id` is stored now; #43 adds `record_done` (see Scope).
4. **Which set is `last_set`.** (a) The last set. (b) The last working or failure set, else the last set. **Decided: (b).** A drop set or warm-up is a poor pre-fill.
5. **Strict server checks.** Unknown `exercise_id`, no sets, over 300 sets → `400`; same id with a new body → `200` with the saved one (not `409`). **Decided: all as listed in AC-3, AC-4.**
6. **Another user's workout id.** (a) `404`. (b) `403`. **Decided: (a).** Keys sit under the user, so it is simply not found, and it tells nothing.
7. **`set_count`/`exercise_count`.** (a) Store on the Workout at save (workouts don't change after Finish). (b) Count sets on each list request (20 queries). **Decided: (a).**
8. **New user profile.** `display_name` null (Swift `String?`), `units` "lb" when unset. **Decided: yes.**
9. **No sign-in screens yet**, but Finish needs a token. (a) Debug builds sign in with the course test number on launch if no token. (b) Build sign-in first. **Decided: (a).** Release keeps workouts in the outbox until sign-in exists.
10. **When a block is done.** (a) Done button. (b) Target sets reached. (c) Both. **Decided: (c).** Empty workouts have no targets.
11. **Superset rest.** No timer between exercises in a round; timer after the round. **Decided: yes.**
12. **Rest and set times.** (a) Time between Log taps; `started_at` null; `time_source` "rest_timer" if a timer ran, else "manual". (b) Time until the timer ends or Skip. **Decided: (a).** It stores what happened, and `ended_at` keeps the raw times.
13. **Defaults with no history.** Empty bar (barbell), 0 (others), 8 reps, 30 s (timed), rest 90 s, effort 80 %, type Working. **Decided: these.**
14. **lb/kg toggle in the sheet.** (a) Changes the app's unit and sends `PUT /users/me`. (b) This sheet only. **Decided: (a).** One setting.
15. **Body weight entry.** (a) Tap "BW" in the sheet to set it (`PUT /users/me`). (b) Later, in a profile screen; send null for now. **Decided: (b).**
16. **One active workout; Finish with no sets.** One at a time, a Resume card, Empty workout disabled meanwhile; "Discard workout?" when there are no sets; also Discard in a ··· menu. **Decided: yes.**
17. **Server rejects (400).** Keep it, show the message, Try again and Delete; no automatic retry. **Decided: yes.**
18. **Edit and delete sets** (not in the mockups). Tap to edit, swipe to delete. **Decided: in scope.**
19. **Workout name** for an empty workout. "Workout"; rename later. **Decided: yes.**
20. **Phone storage format.** (a) One SwiftData row per workout holding its JSON. (b) A SwiftData model per field and set. **Decided: (a).** No migrations when fields change. Fallback: a JSON file, if SwiftData does not work under `swift test`.
21. **Where the outbox lives.** (a) `LiftCore`, which then also depends on `Networking`. (b) A new module. **Decided: (a).** One line in `Package.swift`.
22. **Dumbbell rule (the team still has to confirm it, llm.md).** Log one dumbbell's weight now, labelled "per dumbbell". Only `entryKind(for:)` and its label change if the team decides otherwise; `implement_count` belongs to volume (Home). **Decided: yes.**

## Open questions
None.

## Progress
- [x] Plan approved (369fb8b)
- [x] Scaffold (d8c220a)
- [x] Tests red (5ab278d)
- [ ] Build green
- [ ] Review
- [ ] PR
