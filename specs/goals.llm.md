Status: Approved by Gabriel, Nov 4, 2026
Branch: feat/72-goals

# Plan: Goals tab, strength and weekly frequency goals (#72; spec `specs/goals.md`)
LLM-written. Gabriel's spec wins where they differ. Built on main (1605562). Onboarding (#64) embeds this plan's goal form. Gabriel accepted every recommendation under "Decided" (Nov 4, 2026); "recommended" in the criteria means that decision.

## Acceptance criteria
Server (`goal_service` unit tests; endpoints against the emulator)
- **AC-1** `POST /goals` with a lowercase-UUID `id` creates a goal → `201` with the full goal (stored fields plus computed `progress`). The same `id` again → `200` with the stored goal; nothing changes.
- **AC-2** `400 bad_request`, nothing saved: `id` not a lowercase UUID; `type` not `strength`/`frequency`; strength with an unknown `exercise_id`, an exercise whose `load_type` is `bodyweight` or `timed` (Q-2), or a `target` that isn't a number above 0 (upper limit Q-9); frequency with a `target` not a whole number 1–7, or with an `exercise_id` or `deadline`; `start_date`/`deadline` not `YYYY-MM-DD`; `deadline` before `start_date`; NaN or infinity.
- **AC-3** A new goal when the user already has 3 active goals → `409 conflict`, nothing saved. Active = every frequency goal plus strength goals not completed (Q-3).
- **AC-4** `GET /goals` returns only this user's goals, `{"goals": []}` for a new user. Each has `status` `active` or `completed`.
- **AC-5** Strength `current` = the highest Epley e1RM, `weight_kg × (1 + reps / 30)`, over eligible sets (Q-1, Q-4): `set_type` `working` or `failure`, `weight_kg` > 0, `reps` 1–10, the goal's exercise. No eligible set → `current`, `percent` and `remaining` are `null`. `percent = min(100, current / target × 100)`; `remaining = max(0, target − current)` (kg).
- **AC-6** A strength goal whose `current` ≥ `target` has `status: completed`, `percent: 100`, `remaining: 0` and `achieved_on` (the `local_date` of the first set that reached it). Raising the target above `current` makes it active again (computed, never stored; Q-3).
- **AC-7** Frequency `current` = the number of this user's workouts whose `local_date` falls Monday–Sunday of the week containing `today` (Q-5); each workout once, whatever its sets. `percent = min(100, current / target × 100)`, `remaining = max(0, target − current)`, `met_this_week` true when `current` ≥ `target`. A frequency goal is always `active`. The response gives `week_start` (Monday).
- **AC-8** `PUT /goals/{id}` changes `target` and, for strength, `deadline` (same rules as AC-2); other fields are ignored (Q-6). → `200` with the full goal. Unknown id or another user's → `404 not_found`.
- **AC-9** `DELETE /goals/{id}` → `204`, also when already gone; the user's workouts and sets are untouched. Another user's goal is never deleted.
- **AC-10** Every goal endpoint without a token → `401 unauthorized`.

GoalsCore and Models (`swift test`)
- **AC-11** `Goal`, `GoalList` decode `shared/fixtures/goals.json` (null `current` decodes as nil); `GoalInput` encodes to `shared/fixtures/goal_post.json`.
- **AC-12** `GoalDraft.validate` returns the errors of AC-2's rules (no exercise, target ≤ 0, frequency outside 1–7, deadline before start), plus `.tooManyActive` when 3 are active. `GoalDraft.input(...)` converts a lb target to exact kg (`Weight`), never rounded, and is nil when invalid.
- **AC-13** `GoalCard(goal, unit:)` texts: title ("Bench Press 225 lb", "4 workouts a week"), value line ("185 / 225 lb", "2 of 4 this week", "No sets yet" when `current` is nil), whole-number percent, bar fraction 0–1 (capped), remaining ("40 lb to go", "2 more this week"), deadline ("By Dec 15" / Q-7 overdue text), and the completion and weekly success messages. Switching unit changes only these texts.
- **AC-14** `GoalsScreenModel` states: `.loading`, `.empty` (no goals), `.loaded(active, completed)`, `.failed(message)` with retry; a failed load never shows the old numbers.

App (UI smoke and by hand)
- **AC-15** Goals tab: active cards, New Goal (disabled at 3 active), COMPLETED section, tap a card for detail with Edit and Delete (asks first). Empty state invites to create a goal or log a workout. Error state with "Try again".

## Interface
**API: new contract** (`GET /goals?today=YYYY-MM-DD`, `POST /goals`, `PUT /goals/{id}`, `DELETE /goals/{id}`). It lands first in its own PR: the `API.md` entries (bodies, computed fields, rules, errors, `409` for the limit) and `shared/fixtures/goals.json` (one strength active with progress, one strength with no sets, one completed, one frequency), `goal_post.json` (strength), `goal_post_frequency.json`, `goal_put.json`. Goal JSON: `id`, `type`, `exercise_id`, `exercise_name` (server-added, Q-10), `target`, `start_date`, `deadline`, `created_at`, `status`, `progress {current, percent, remaining, achieved_on, met_this_week, week_start}`. The app sends `start_date` (its local date, Q-5).
```python
# services/goal_service.py (no Flask)
def epley(weight_kg: float, reps: int) -> float
def strength_progress(goal: dict, sets: list[dict]) -> dict      # sets: stored SetEntry dicts with local_date
def frequency_progress(goal: dict, workouts: list[dict], today: date) -> dict
def list_goals(user_id: str, today: date) -> list[dict]
def create_goal(user_id: str, body: dict, today: date) -> tuple[dict, bool]   # (goal, created)
def update_goal(user_id: str, goal_id: str, body: dict, today: date) -> dict
def delete_goal(user_id: str, goal_id: str) -> None
```
```swift
// Models/Goal.swift
public enum GoalType: String, Codable, Sendable { case strength, frequency }
public enum GoalStatus: String, Codable, Sendable { case active, completed }
public struct GoalProgress: Codable, Hashable, Sendable { current, percent, remaining: Double?; achievedOn: String?; metThisWeek: Bool?; weekStart: String? }
public struct Goal: Codable, Identifiable, Hashable, Sendable { id, type, exerciseId, exerciseName, target, startDate, deadline, createdAt, status, progress }
public struct GoalInput: Codable, Hashable, Sendable { id, type, exerciseId, target, startDate, deadline }
public struct GoalList: Codable, Sendable { public let goals: [Goal] }
// Networking/APIClient.swift
public func goals(today: String) async throws -> [Goal]
public func createGoal(_ goal: GoalInput) async throws -> Goal
public func updateGoal(_ goal: GoalInput) async throws -> Goal
public func deleteGoal(id: String) async throws
// GoalsCore (new module; depends on Models, Networking)
public struct GoalDraft: Equatable, Sendable { type, exercise: Exercise?, targetText: String, unit: WeightUnit, deadline: Date?; init(editing: Goal?, unit:) }
public enum GoalFormError: Equatable, Sendable { case noExercise, targetNotPositive, frequencyOutOfRange, deadlineBeforeStart, tooManyActive }
extension GoalDraft { func validate(startDate: Date, activeCount: Int, calendar: Calendar) -> [GoalFormError]; func input(id: String, startDate: Date, calendar: Calendar) -> GoalInput? }
public struct GoalCard: Equatable, Sendable { title, valueText, percentText, barFraction, remainingText, deadlineText, message: String?; init(_ goal: Goal, unit: WeightUnit, today: Date, calendar: Calendar) }
@Observable public final class GoalsScreenModel { state; load(); create(_:) ; update(_:); delete(id:) }
public protocol GoalsAPI: Sendable { goals, createGoal, updateGoal, deleteGoal }   // APIClient conforms; tests use a fake
```
**Onboarding (#64) reuse:** the app's `GoalFormView(draft:, activeCount:, onSave: (GoalInput) async throws -> Void, onCancel:)` holds no networking itself; onboarding presents it with its own Skip and `onSave` = `APIClient.createGoal`. All rules are in `GoalDraft`, so both entry points behave the same.

## Files
- Server new: `api/goals.py`, `services/goal_service.py`. Changed: **`main.py`** (one Blueprint line), **`models.py`** (`goal_key`, `put_goal`, `get_goal`, `user_goals`, `delete_goal`, `user_sets(user_id, exercise_ids)`, `user_workout_dates(user_id)`; ancestor queries filtered in Python, so **no `index.yaml` change**). `server_architecture.llm.md`: Goal fields per spec.
- iOS new: `Models/Goal.swift` (**hot spot**), `Sources/GoalsCore/{GoalDraft,GoalCard,GoalsScreenModel}.swift`, `Features/Goals/{GoalsView (rewrite),GoalCardView,GoalDetailView,GoalFormView,GoalExercisePicker}.swift`. Changed: `Networking/APIClient.swift`, **`Package.swift`** (GoalsCore + test target), `PreviewData/PreviewData.swift`. New app files through the Xcode MCP.

## Reuse
`require_user`, `ApiError`, `services/timestamps.py`, the template service's lowercase-UUID check and retry-safe create (`models.add_template` pattern), `exercise_service` lookup. iOS: `Weight`/`WeightUnit`, `APIJSON`, `ClientID.make()`, LiftCore `ExerciseSearch` + bundled library for the strength picker (single select, bodyweight/timed hidden), `CardView`, `PrimaryButton`, `SectionHeader`, `NoticeLine`, `PlaceholderScreen`, `Theme`. SwiftUI `ProgressView(value:)` tinted `accent`. No new dependency.

## Tests
- Server unit: `server/tests/services/test_goal_service.py` (AC-5–7 maths, AC-2 rules). Emulator: `server/tests/api/test_goals.py` (AC-1–4, 6, 8–10).
- iOS: `Tests/ModelsTests/GoalTests.swift` (AC-11), `Tests/GoalsCoreTests/{GoalDraftTests,GoalCardTests,GoalsScreenModelTests}.swift` (AC-12–14). AC-15: walkthrough / by hand.

## Test-writer may read
- `server/services/goal_service.py`
- `server/api/goals.py`
- `server/models.py`
- `server/services/auth.py`
- `ios/MuscleMapKit/Sources/Models/Goal.swift`
- `ios/MuscleMapKit/Sources/Models/Weight.swift`
- `ios/MuscleMapKit/Sources/Models/Exercise.swift`
- `ios/MuscleMapKit/Sources/Models/APIJSON.swift`
- `ios/MuscleMapKit/Sources/GoalsCore/GoalDraft.swift`
- `ios/MuscleMapKit/Sources/GoalsCore/GoalCard.swift`
- `ios/MuscleMapKit/Sources/GoalsCore/GoalsScreenModel.swift`

## Decided (Gabriel, Nov 4, 2026: every recommendation below accepted)
1. **Eligible sets.** Recommend `set_type` in {`working`, `failure`}; warm-ups and drop sets excluded (matches D-4's `last_set`). Every stored set counts as completed (only finished workouts are stored).
2. **Bodyweight and timed exercises.** Recommend `Exercise.load_type` `bodyweight` or `timed` → `400` on create and hidden in the picker. Weighted pull-ups (`added_load_kg`) stay out for v1.
3. **Completion and the limit.** Recommend completion is computed on every request (no stored flag), completed goals don't count toward 3, and raising a completed goal's target reopens it (`409` if that would make 4 active). Alternative: store `completed_at` the first time it's seen, so it never reopens.
4. **History window for e1RM.** (a) All history, as the spec says; a goal already met is completed at once. (b) Only sets on or after `start_date`. Recommend (a), with the form showing "Current best: 185 lb" and warning when the target is already met.
5. **"This week" and `start_date`.** Recommend `GET /goals?today=YYYY-MM-DD` sent by the app (its local date; defaults to the server's UTC date when left out), and the app sends `start_date`. Alternative: use the latest workout's `timezone`, or a `User.timezone` later.
6. **What `PUT` may change.** Recommend `target` and `deadline` only; `type`, `exercise_id` and `start_date` are ignored (new exercise = delete and create). Alternative: `400` when they differ.
7. **Deadline passed, unmet.** Recommend the goal stays active and the card reads "Deadline passed · Dec 15" until edited or deleted. Alternative: a "Missed" section.
8. **Home summary.** Recommend out of scope (spec says "may"); a follow-up Issue once Home is built.
9. **Duplicates and limits.** Recommend at most one frequency goal (`409`), strength goals may repeat an exercise, strength `target` at most 1500 kg, deadline at most 5 years after `start_date`.
10. **Exercise name in the response.** Recommend the server adds `exercise_name`, so Goals needn't load the library. Alternative: the app looks it up in LiftCore's bundled library.
11. **Order of cards.** Recommend active: oldest-created first; completed: newest `achieved_on` first.
12. **Walkthrough.** None; AC-15 is checked by hand.

## Progress
- [x] Plan approved
- [x] Scaffold (8977bea)
- [ ] Tests red
- [ ] Build green
- [ ] Review
- [ ] PR
