Status: Approved by Sasa, Nov 3, 2026
Branch: feat/8-exercise-search

# Plan: exercise search and picker (#8 server, #15 app; spec #2)
LLM-written. This is the plan for `specs/exercise-search.md`. Sasa's spec wins where they differ.

## What the user sees (mockup: `client_architecture.llm.md`, "Lift screens", `ExercisePickerView`)
- A sheet titled "New workout", with Cancel at the top left.
- A search box. Below it, group chips: All, Chest, Back, Shoulders, Arms, Legs, Core.
- YOUR EXERCISES, with a Recent / Most used toggle (Recent first, as in the mockup). Each row: name, "Last: 155 lb × 5 · 2 days ago", a checkbox.
- ALL EXERCISES. Each row: name, "Glutes, Lower back, Hamstrings · Barbell", a + button (a check when picked).
- At the bottom: "Pair as superset" (only with 2 or more picks) and a primary button with the count ("Add 2", "Add 2 as superset").

## Search rules and result order
- The server does the matching. The app sends a request 0.3 s after the last keystroke. An empty box shows the whole library.
- Text is compared without case. Spaces at the start and end are ignored.
- A *word start* is the start of a name or alias, or the position after a space or a hyphen.
- An exercise matches when, at a word start in its name or one of its aliases, the text begins with the typed text. So "split squat" matches "Bulgarian Split Squat", and "up" matches "Push-up".
- Order: (1) the name starts with the text; (2) a later word in the name starts with it; (3) only an alias matches. Ties are A–Z by name.
- An exercise's `groups` are the groups (in `shared/muscles.json`) of all its primary-role muscles. The group of the strongest primary comes first; no duplicates. Today only three exercises have two groups: Deadlift (legs, back), Dips (chest, arms), Hanging Leg Raise (core, legs).
- A chip other than All sends `group=<id>`. The server returns only matches whose `groups` contain it.
- The search text and the chip also filter "Your exercises": it shows only your exercises that are in the current results.

## Empty and error states
- No match: "No exercises match '<text>'".
- Server unreachable: a short error message and a "Try again" button. While a request runs, the last results stay on screen.
- "Your exercises" is hidden when the list is empty, when signed out (no `/mine` call), and when only `/mine` fails.

## Scope for this feature
- In: `GET /exercises?q=&group=` (public), `GET /exercises/mine` (sign-in), the full picker, and an "Empty workout" tile on Lift that opens it. After "Add", a placeholder list shows the picks.
- Later: "Add exercise" during a workout and editing a saved workout open the picker. The real Lift home. Sign-in screens. `POST /workouts`, which fills "Your exercises". The user's own units (lb until `GET /users/me` exists).
- Build order: the contract PR, then the server's plain search, then the app search screen, so Milestone 0 (due 2026-11-04) gets a real app→server call early. Groups, "Your exercises" and multi-select follow.

## Filled in from chat decisions
Each item below is not written in the spec. All are (Sasa, Nov 3, 2026).
- The full picker as in the mockup, with the superset toggle and the count on "Add".
- Matching on the server, 0.3 s after typing stops. The word-start rule (space or hyphen), three tiers, A–Z ties.
- `GET /exercises` is public and gets a `group` parameter. An unknown group is `400 bad_request`.
- Chips: All plus the 6 groups in `shared/muscles.json`. An exercise is in every group of its primary-role muscles.
- Each returned exercise gets `groups` and `primary_muscles` (parent display names, strongest first, no duplicates). Rows show "<primary_muscles joined by ', '> · <load type>".
- The server reads its own copy, `server/muscles.json`. A test fails if it differs from `shared/muscles.json`; copy shared → server.
- "Your exercises": hidden when empty or signed out; filtered by text and chip; Recent ties A–Z, Most used ties by last used, then name. Weights show in lb for now.
- Tap to pick, tap again to unpick. Picks keep tap order and show as picked in both sections. The superset toggle shows only with 2 or more picks; below 2 the flag turns off. "Add" is disabled with 0 picks.
- The texts and states in "Empty and error states" above.
- The picker forgets everything (text, chip, sort, picks, superset) when it closes.
- Only "Empty workout" opens the picker for now; a placeholder list shows the picks. Server plain search is built first.
- Sorting and picking rules go in `LiftCore`; `searchExercises` gets a group parameter.

## Acceptance criteria
Server
- **AC-1** `GET /api/v1/exercises` with no `q` (or a blank `q`) and no `group` returns `200 {"exercises": [...]}`: every library exercise, A–Z by name, in the API.md shape. It needs no `Authorization` header.
- **AC-2** Matching follows the rules above. "BEN" and "bp" match Bench Press. "ench" matches nothing. "split squat" matches only Bulgarian Split Squat.
- **AC-3** Order follows the three tiers. "bench" → Bench Press, Dumbbell Bench Press, Incline Bench Press. "squat" → Back Squat, Bulgarian Split Squat, Front Squat, Goblet Squat. "press" → the 7 name matches A–Z, then Overhead Triceps Extension, Push-up, Triceps Pushdown (alias only). "up" → Chin-up, Pull-up, Push-up, then Inverted Row (alias "australian pull-up").
- **AC-4** Every exercise has `groups` and `primary_muscles`. Deadlift: `["legs", "back"]`, `["Glutes", "Lower back", "Hamstrings"]`. Dips: `["chest", "arms"]`, `["Chest", "Triceps"]`. Hanging Leg Raise: `["core", "legs"]`, `["Abs", "Hip flexors"]`. Barbell Curl: `["arms"]`, `["Biceps"]`.
- **AC-5** `group=<id>` keeps exercises whose `groups` contain it, also with `q`. `group=back` includes Deadlift; `group=arms` includes Dips; `group=legs` includes Deadlift and Hanging Leg Raise; `group=chest` includes Dips.
- **AC-6** An unknown `group` returns `400 bad_request`.
- **AC-7** `GET /api/v1/exercises/mine` without a valid token returns `401 unauthorized`.
- **AC-8** With a valid token, `/mine` returns `200 {"exercises": [...]}`: one item per `UserExercise` entity under the user, with the API.md fields. A user with none gets `{"exercises": []}`. Nothing writes `UserExercise` until `POST /workouts` exists, so today every user gets an empty list.
- **AC-9** The server reads only `server/muscles.json`. A test fails when it differs from `shared/muscles.json`.

App logic (`Models`, `LiftCore`, `Networking`)
- **AC-10** `Exercise` decodes `groups` and `primary_muscles` from `shared/fixtures/exercises_search.json`.
- **AC-11** `MuscleGroup.allCases` is chest, back, shoulders, arms, legs, core, in that order, with display names. A test checks this against `shared/muscles.json`.
- **AC-12** `ExerciseSelection.toggle` adds an exercise at the end or removes it; a re-pick goes to the end. `setSuperset(true)` works only with 2 or more picks. A toggle that leaves fewer than 2 turns the flag off. `canAdd` is false with 0 picks. `addButtonTitle`: "Add", "Add 1", "Add 2", "Add 2 as superset".
- **AC-13** `myExerciseRows` keeps only exercises in the current results. Recent: `lastUsedAt` newest first, ties A–Z. Most used: `useCount` highest first, ties by `lastUsedAt`, then A–Z.
- **AC-14** `lastSetText(_, unit: .lb)` gives "155 lb × 5", "BW × 20", "BW +10 lb × 8", "45 s". `exerciseSubtitle` gives "Glutes, Lower back, Hamstrings · Barbell".
- **AC-15** `searchExercises(_:group:)` sends `q` only when it is not blank and `group` only when it is set. `myExercises()` sends the token.

App screens (by hand on the simulator and in previews)
- **AC-16** Typing sends one request 0.3 s after the last keystroke. A reply for older text never replaces newer results.
- **AC-17** "Empty workout" on Lift opens the picker. Cancel closes it with no change. "Add" closes it, and the placeholder list shows the picks in tap order, marked "Superset" when the flag is on. On reopen, the picker starts empty: no text, All, Recent, no picks.
- **AC-18** Typing "bench" shows results from the local server (Issue #15, Milestone 0).
- **AC-19** The empty and error states above. Signed out, the app makes no `/mine` call.

## Interface
API.md: `GET /exercises` **changes**: public, new `group` parameter, `400` for an unknown group, and new fields `groups` and `primary_muscles` on each exercise. It lands first in its own small PR. `GET /exercises/mine` keeps its shape.
```python
# server/services/exercise_service.py  (no Flask). `muscles` = parsed server/muscles.json
def load_muscles() -> dict                                    # reads server/muscles.json only
def groups_of(exercise: dict, muscles: dict) -> list[str]
def primary_muscles_of(exercise: dict, muscles: dict) -> list[str]
def search(exercises: list[dict], q: str | None, group: str | None, muscles: dict) -> list[dict]  # adds both fields
def find_exercises(q: str | None, group: str | None) -> list[dict]   # ApiError("bad_request") for unknown group
def my_exercises(user_id: str) -> list[dict]
# server/models.py (hot spot): user_exercises(user_id) -> list[dict]; put_user_exercise(user_id, slug, data) -> None
# server/api/exercises.py: bp; GET "" (public), GET "/mine" (@require_user)
```
```swift
// Models/Exercise.swift (hot spot): Exercise gains `public var groups: [String]`, `public var primaryMuscles: [String]` (init defaults [])
// LiftCore/ExercisePicker.swift
public enum MuscleGroup: String, CaseIterable, Sendable { case chest, back, shoulders, arms, legs, core; public var name: String }
public enum MyExerciseSort: Sendable { case recent, mostUsed }
public struct MyExerciseRow: Identifiable, Hashable, Sendable { public let exercise: Exercise; public let history: UserExercise }
public func myExerciseRows(_ mine: [UserExercise], in results: [Exercise], sort: MyExerciseSort) -> [MyExerciseRow]
public struct ExerciseSelection: Equatable, Sendable {
    public private(set) var picked: [Exercise]; public private(set) var isSuperset: Bool
    public mutating func toggle(_ exercise: Exercise); public mutating func setSuperset(_ on: Bool)
    public func contains(_ id: String) -> Bool
    public var canSuperset: Bool { get }; public var canAdd: Bool { get }; public var addButtonTitle: String { get } }
public func lastSetText(_ set: LastSet, unit: WeightUnit) -> String
public func exerciseSubtitle(_ exercise: Exercise) -> String
// Networking/APIClient.swift (changed): func searchExercises(_ query: String? = nil, group: String? = nil) async throws -> [Exercise]
```

## Files
- Contract PR first (all hot spots): `API.md`; `shared/fixtures/exercises_search.json`, the only fixture with exercise objects (`exercises_mine.json` and `templates.json` hold only `exercise_id`); `ios/MuscleMapKit/Sources/Models/Exercise.swift`.
- Server: new `server/api/exercises.py`, `server/services/exercise_service.py`, `server/muscles.json` (copy of `shared/`); changed `server/main.py` (hot spot: one line), `server/models.py` (hot spot: two helpers).
- iOS package: new `Sources/LiftCore/ExercisePicker.swift`; changed `Sources/Networking/APIClient.swift`. Issue #15 lists only `Features/Lift/`; I will add these paths to it.
- iOS app: new `Features/Lift/ExercisePickerView.swift`, `ExercisePickerModel.swift` (`@Observable`), `PickedExercisesPlaceholder.swift`; changed `LiftView.swift`, `PreviewData/PreviewData.swift` (new fields), `App/MuscleMapApp.swift` (hot spot: one shared `APIClient` in the environment). New files go in through the Xcode MCP.

## Reuse
`models.all_exercises()`, `require_user`, `ApiError`; `APIClient.searchExercises` / `myExercises`, `Exercise`, `UserExercise`, `LastSet`, `Weight`, `KeychainTokenStore`; `SectionHeader`, `PrimaryButton`, `CardView`, `Theme`; `PreviewData.exercises` / `myExercises`. No new dependency.

## Tests
- Server unit (AC-2–6): `server/tests/services/test_exercise_service.py`, on `seed/exercises.json` in memory. AC-9: `server/tests/test_muscles_copy.py`.
- Server integration, emulator (AC-1, 6–8): `server/tests/api/test_exercises.py`.
- iOS unit: AC-10 in `Tests/ModelsTests/FixtureTests.swift`; AC-11–14 in `Tests/LiftCoreTests/ExercisePickerTests.swift`; AC-15 in `Tests/NetworkingTests/APIClientTests.swift`.
- AC-16–19: by hand on the simulator, with a screenshot in the PR. A UI smoke test comes later.

## Test-writer may read
- `server/services/exercise_service.py`
- `server/api/exercises.py`
- `server/models.py`
- `server/services/auth.py`
- `ios/MuscleMapKit/Sources/LiftCore/ExercisePicker.swift`
- `ios/MuscleMapKit/Sources/Networking/APIClient.swift`
- `ios/MuscleMapKit/Sources/Networking/TokenStore.swift`
- `ios/MuscleMapKit/Sources/Models/Exercise.swift`
- `ios/MuscleMapKit/Sources/Models/Weight.swift`

## Open questions
None.

## Progress
- [x] Plan approved (ff83fa6)
- [x] Scaffold (638e175)
- [x] Tests red (23209ef)
- [ ] Build green
- [ ] Review
- [ ] PR
