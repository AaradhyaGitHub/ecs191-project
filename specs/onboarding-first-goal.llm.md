Status: Approved by Gabriel, Nov 5, 2026
Branch: feat/79-onboarding-first-goal

# Plan: onboarding first goal (#79; follow-up to Q-9 in `specs/onboarding.llm.md`)
LLM-written. Implements `specs/onboarding.md` §1 step 4 "First goal" (and its last paragraph of §3 Data) and `specs/goals.md` §2 "Both entry points use the same goal creation form". The specs win where they differ. Base: main (e2d7434). No contract change: uses `POST /goals` as in API.md.

## Acceptance criteria
OnboardingCore (`swift test --filter OnboardingCoreTests`)
- **AC-1** `OnboardingFlow.saveGoal(_:)` sends the `GoalInput` once through `OnboardingAPI.createGoal`. On success `savedGoal` is the returned `Goal`, `errorText` is nil, and `onboarding_completed` is **not** sent yet (Q-2).
- **AC-2** A failed `saveGoal` throws (so the form stays open with its message, same id on retry), leaves `savedGoal` nil and `isFinished` false. A `409` or `400` keeps the server's message for the form.
- **AC-3** A 401 on `saveGoal` clears the token and sets `isSignedOut`, like the onboarding PUTs (Q-10, Q-5 here).
- **AC-4** `saveGoal` does nothing (no call) unless `step == .firstGoal`, nothing is saving, and no goal was saved yet (one goal per onboarding, Q-2).
- **AC-5** `units` is the unit from the profile just saved (the `User` that `PUT /users/me` returns in `saveProfile`); before that it is `.lb` (Q-4).
- **AC-6** `finish(skippedGoal:)` keeps today's behavior (AC-9 of #64): one `PUT {"onboarding_completed": true}` whether skipped or not. Existing `OnboardingFlowTests` still pass.

App (by hand, Simulator, local server :5001, test number)
- **AC-7** Goal step shows "Set a goal" (opens `GoalFormView` as a sheet, Q-1) and "Skip for now". Skip → `finish(skippedGoal: true)` → Home, no goal created.
- **AC-8** Saving a valid goal closes the sheet; the step shows the goal's title (`GoalCard(...).title`) and one "Get Started" → `finish(skippedGoal: false)` → Home; the goal appears in the Goals tab (Q-2). Cancel closes the sheet and changes nothing.
- **AC-9** The form uses the profile's unit (a kg user sees kg) and `activeCount` per Q-3. Theme tokens and shared components only; no new warnings.

## Interface
```swift
// OnboardingCore/OnboardingAPI.swift: one new requirement (APIClient already has it, so it still conforms)
func createGoal(_ goal: GoalInput) async throws -> Goal       // Goal, GoalInput are in Models
// OnboardingCore/OnboardingFlow.swift: new members
public private(set) var savedGoal: Goal?                       // nil until a goal is saved
public private(set) var units: WeightUnit                      // .lb until saveProfile succeeds
public func saveGoal(_ input: GoalInput) async throws          // the form's onSave
```
`Goal`/`GoalInput` live in `Models`, so OnboardingCore needs **no GoalsCore dependency and no `Package.swift` change** (Q-6). The app's `FirstGoalStep` imports GoalsCore for `GoalDraft` and `GoalCard`, as `GoalsView` does.

## Files
- Package: `Sources/OnboardingCore/OnboardingAPI.swift`, `Sources/OnboardingCore/OnboardingFlow.swift`. Tests: new `Tests/OnboardingCoreTests/FirstGoalTests.swift`; `TestSupport.swift`'s fake gains `createGoal` (test-writer's file).
- App: `Features/Onboarding/FirstGoalStep.swift` (sheet, saved state, buttons); `PreviewData/PreviewData.swift` (preview fake gains `createGoal`; a "goal saved" preview). `LaunchGate.swift` unchanged. No hot spot touched.

## Reuse
`GoalFormView(draft:activeCount:onSave:onCancel:)` unchanged (already a sheet with its own Cancel, Save and error line), `GoalDraft(unit:)`, `GoalCard(_:unit:today:calendar:).title`, `APIClient.createGoal`, `OnboardingErrors.isUnauthorized`, `OnboardingPage`, `PrimaryButton`, `SecondaryTextButton`, `NoticeLine`, `Theme`.

## Tests
AC-1–6 unit in `FirstGoalTests.swift` (fake `OnboardingAPI` with a scripted `createGoal`); AC-7–9 by hand. Full fast suite before the PR.

## Test-writer may read
- `ios/MuscleMapKit/Sources/OnboardingCore/OnboardingFlow.swift`
- `ios/MuscleMapKit/Sources/OnboardingCore/OnboardingAPI.swift`
- `ios/MuscleMapKit/Sources/OnboardingCore/ProfileDraft.swift`
- `ios/MuscleMapKit/Sources/Models/Goal.swift`
- `ios/MuscleMapKit/Sources/Models/User.swift`
- `ios/MuscleMapKit/Sources/Models/Weight.swift`
- `ios/MuscleMapKit/Sources/Networking/APIErrorBody.swift`

## Open questions (recommendation in bold)
- Decided (Gabriel, Nov 5, 2026): every recommendation in bold below.
- **Q-1 Inline or sheet.** (a) **"Set a goal" button opens `GoalFormView` as a sheet**: the form is built as a sheet (own NavigationStack, Cancel, Save), so it is reused unchanged, as goals.md §2 asks. (b) Inline in the step: needs a variant of the form without Cancel and the nav bar, i.e. editing Goals' file.
- **Q-2 After a save.** (a) **Sheet closes; the step shows "Goal set: Bench Press 225 lb" and one "Get Started"** (Q-7 of #64 made the step's Get Started the spec's "final screen"); Skip and "Set a goal" are hidden, one goal per onboarding, more in the Goals tab. (b) Finish and go Home right after Save (one tap fewer, no confirmation).
- **Q-3 `activeCount`.** (a) **Pass 0 and rely on the server's `409`**, whose message the form shows; onboarding always resumes at profile and a goal is normally saved just before finishing, so a returning user with goals here is rare. (b) Fetch `GET /goals` when the step opens (one more call, loading and error states).
- **Q-4 Unit.** (a) **`OnboardingFlow.units` from the `User` returned by the profile PUT** (the `user` LaunchGate holds is the pre-profile one, so it can be stale if units changed). (b) Read it from the `ProfileDraft` the view holds.
- **Q-5 401 on the goal save.** **Same as onboarding's PUTs (Q-10): clear the token, `isSignedOut`, gate shows Welcome** (the sheet goes with the step). The app-wide rule stays in #38.
- **Q-6 Where the logic lives.** (a) **`OnboardingFlow.saveGoal` with `createGoal` added to `OnboardingAPI`**: testable in OnboardingCore, no `Package.swift` change. (b) The view calls `APIClient.createGoal` directly (logic in the view, untested). (c) Make OnboardingCore depend on GoalsCore's `GoalsAPI` (hot-spot edit, not needed).
- **Q-7 `skippedGoal`.** It changes nothing on the wire today. **Keep the parameter (no server field for it); the view passes `savedGoal == nil`.** Or drop it in a later cleanup.

## Progress
- [x] Plan approved
- [x] Scaffold (3aef1fa)
- [x] Tests red (1061157)
- [x] Build green (544714a)
- [x] Review (0 blockers, 0 should-fix; N-1 nit)
- [x] PR (#81)
