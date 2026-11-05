Status: Approved by Gabriel, Nov 4, 2026
Branch: feat/64-onboarding

# Plan: onboarding (#64; spec `specs/onboarding.md`)
LLM-written. Gabriel's spec wins where they differ. Base: main (1605562). Goal step depends on #72 (Goals, `specs/goals.md`); real phone numbers on #37; app-wide 401/log out is #38; field limits are #51.

## Acceptance criteria
Server (`server/services/user_service.py`; no `models.py` change, `update_user` is generic)
- **AC-1** `GET /users/me` always has `onboarding_completed` (bool). New users, and users stored before the field existed, get `false` (Q-3).
- **AC-2** `PUT /users/me` accepts `onboarding_completed`: `true`/`false` saved and returned; any other value → `400 bad_request`, nothing changes. Other fields keep today's rules.

OnboardingCore (`swift test --filter OnboardingCoreTests`)
- **AC-3** `PhoneNumber.e164(from:)`: 10 US digits, 11 starting with 1, or `+1…` with spaces, dashes, dots, parentheses → `"+1NNNNNNNNNN"`; anything else → nil (Q-4). `display` formats `+15305550000` as `(530) 555-0000`.
- **AC-4** `VerificationCode.sanitized` keeps digits, max 6; `isValid` is true only for exactly 6 digits.
- **AC-5** `launchRoute(api:)`: no token → `.welcome` (no call); `me` failed with 401 → `.welcome` and the token is cleared; other failure → `.retry`; `onboardingCompleted` → `.home`; else `.onboarding(.profile)` (Q-2).
- **AC-6** `SignInFlow`: `sendCode` with an invalid number sets `errorText` and makes no call; a valid one calls `startSignIn` and moves to `.enterCode`. `verify` → on success fetches `me` and ends `.signedIn(User)`. Errors become texts (Q-7): 401 → "That code isn't right.", 403/400 → the server's message, no connection → "Can't reach the server.". `changeNumber` returns to `.enterPhone` keeping the digits.
- **AC-7** Resend is allowed only `resendCooldown` (Q-5) after the last send, by injected clock; `resendAvailableIn(now:)` counts down.
- **AC-8** `ProfileDraft`: prefilled from a `User`; units default lb; switching units converts the typed body weight (via `Weight`, display rounded to 0.1); `update()` sends trimmed name (blank → omitted), `units`, body weight as exact kg, and only the optional fields set; body weight outside >0…500 kg or birth year outside 1900…this year → `validationError`, no call.
- **AC-9** `OnboardingFlow.finish(skippedGoal:)` sends `PUT {"onboarding_completed": true}` only after the goal step (done or skipped), never after the profile step (spec 3).
- **AC-10** `User` decodes `user.json` and `user_new.json` with `onboardingCompleted` (true/false); `UserUpdate(onboardingCompleted: true)` encodes `{"onboarding_completed": true}`.

App (by hand, Simulator, local server :5001, test number)
- **AC-11** No token: Welcome → phone → code → profile → goal step → Home. Token + completed → Home directly, no flash of Welcome. Token + not completed → profile prefilled. 401 at launch → Welcome. Resend and "Change number" work. Theme tokens and `PrimaryButton` only.
- **AC-12** After sign-in, the outbox sends pending workouts (`session.outbox.sendPending()`).

## Interface
API: **changed contract** (`GET`/`PUT /users/me`, API.md). `experience` already exists in API.md, the server and `User.swift`; only `onboarding_completed` is new. Contract PR (small, alone, lands first): API.md `GET /users/me` field + default rule; `PUT /users/me` editable list and its `400` case; fixtures `user.json` (`true`), `user_new.json` (`false`), new `user_update_onboarding.json` `{"onboarding_completed": true}`.
```swift
// Models/User.swift (hot spot): User.onboardingCompleted: Bool; UserUpdate.onboardingCompleted: Bool?
// Networking/APIClient.swift: public func clearSignIn() throws   // #38 reuses it
// OnboardingCore (new module)
public protocol OnboardingAPI: Sendable { var isSignedIn: Bool { get }
  func startSignIn(phoneNumber: String) async throws; func verifySignIn(phoneNumber: String, code: String) async throws -> SignIn
  func me() async throws -> User; func updateMe(_: UserUpdate) async throws -> User; func clearSignIn() throws }   // APIClient conforms
public enum PhoneNumber { static func e164(from: String) -> String?; static func display(_ e164: String) -> String }
public enum VerificationCode { static func sanitized(_: String) -> String; static func isValid(_: String) -> Bool }
public enum OnboardingStep: Equatable, Sendable { case profile, firstGoal }
public enum LaunchRoute: Equatable, Sendable { case welcome, retry, onboarding(OnboardingStep), home }
public func launchRoute(api: any OnboardingAPI) async -> LaunchRoute
@Observable public final class SignInFlow { phoneText, codeText, state, errorText, isBusy; init(api:, now: @escaping () -> Date)
  func sendCode() async; func resend() async; func verify() async; func changeNumber(); func resendAvailableIn() -> Int }
public struct ProfileDraft: Equatable { init(user: User); displayName, units, bodyweightText, sex, birthYear, experience
  mutating func setUnits(_: WeightUnit); var validationError: String? { get }; func update() -> UserUpdate }
@Observable public final class OnboardingFlow { step; func saveProfile(_: ProfileDraft) async; func finish(skippedGoal: Bool) async }
```
## Files
- Server: `server/services/user_service.py`; tests `server/tests/services/test_user_service.py`, `server/tests/api/test_users.py`.
- iOS package: **hot spots** `Package.swift` (+`OnboardingCore`, `OnboardingCoreTests`) and `Sources/Models/User.swift`; `Sources/Networking/APIClient.swift`; new `Sources/OnboardingCore/{OnboardingAPI,PhoneNumber,VerificationCode,LaunchRoute,SignInFlow,ProfileDraft,OnboardingFlow}.swift`; tests `Tests/OnboardingCoreTests/`, `Tests/ModelsTests/FixtureTests.swift`.
- App: new `Features/Onboarding/{LaunchGate,WelcomeView,PhoneNumberView,CodeView,ProfileSetupView,FirstGoalStep}.swift`, `PreviewData/PreviewData.swift`; **hot spot** `App/MuscleMapApp.swift` (show `LaunchGate { RootView() }`, remove `signInForDevelopment`, Q-8). `RootView.swift` unchanged.

## Reuse
`APIClient.startSignIn/verifySignIn/me/updateMe`, `KeychainTokenStore`, `Weight`, `WorkoutLimits.maxBodyweightKg` value (copied as a constant, so OnboardingCore needn't import LiftCore), `Experience`, `PrimaryButton`, `CardView`, `NoticeLine`, `Theme`. Server: `user_service._RULES`/`EDITABLE_FIELDS`, `auth.sign_in` in tests. Goal step: #72's goal form and `GoalsCore`, not a copy. Fake `OnboardingAPI` in tests, like `WorkoutSending`.

## Tests
AC-1–2 server unit + emulator integration; AC-3–9 `OnboardingCoreTests`; AC-10 `ModelsTests`; AC-11–12 by hand (no UI smoke test unless you want one).

## Test-writer may read
- `server/services/user_service.py`
- `server/api/users.py`
- `server/services/auth.py`
- `ios/MuscleMapKit/Sources/Models/User.swift`
- `ios/MuscleMapKit/Sources/Models/Weight.swift`
- `ios/MuscleMapKit/Sources/Networking/APIClient.swift`
- `ios/MuscleMapKit/Sources/OnboardingCore/OnboardingAPI.swift`
- `ios/MuscleMapKit/Sources/OnboardingCore/PhoneNumber.swift`
- `ios/MuscleMapKit/Sources/OnboardingCore/VerificationCode.swift`
- `ios/MuscleMapKit/Sources/OnboardingCore/LaunchRoute.swift`
- `ios/MuscleMapKit/Sources/OnboardingCore/SignInFlow.swift`
- `ios/MuscleMapKit/Sources/OnboardingCore/ProfileDraft.swift`
- `ios/MuscleMapKit/Sources/OnboardingCore/OnboardingFlow.swift`

## Decided (Gabriel, Nov 4, 2026: the bold recommendation in each is accepted)
- **Q-1 Display name required?** Data table says no; Description says users enter one. **Optional**; Continue works with it blank (spec: no unnecessary info).
- **Q-2 Resume point.** No server flag says "profile saved". (a) **Always resume at profile, prefilled from `GET /users/me`**; one tap to go on. (b) Resume at goal step if `display_name` is set (fails when the name is skipped). (c) A second flag, `profile_completed` (contract change).
- **Q-3 Existing accounts.** **Missing field = `false`**: only team/test accounts exist, they redo onboarding once, prefilled. Alternative: `true` when the user has a name or any workout.
- **Q-4 Phone numbers.** **US only, fixed "+1" prefix, shown as (530) 555-0000, sent E.164** (the server already requires E.164). Other countries later.
- **Q-5 Resend cooldown.** **30 s, app side only.** The course service's own limits are unknown (#37).
- **Q-6 Experience.** Already in the contract and model, but nothing uses it. **Keep it as an optional chip row (Beginner / Intermediate / Advanced), stored only**; uses (goal suggestions, defaults) decided later. Or drop it from onboarding.
- **Q-7 Texts and screens.** Proposed: Welcome "Log workouts, see which muscles you trained, and work toward your goals." + "Get Started"; code screen "Resend code" ("Resend in 0:24"), "Change number". Is the "final screen" the goal step's own "Get Started" (**recommended**, with "Skip for now") or a separate "You're all set" screen? Sex choices (#51 says a fixed list): **Female / Male / Prefer not to say (= null)**.
- **Q-8 Debug auto-sign-in** (`signInForDevelopment`, D-9 in #42) would skip Welcome and sign-in. **Remove it; Debug builds prefill the test number and show "Test code: 123456"** on the code screen. Note: everyone shares the test account (same `user_id`) on the deployed server, so after one teammate onboards it skips for all; **a Debug-only "Reset onboarding" (PUT `false`) is included.**
- **Q-9 Goal step vs #72.** (a) **Build welcome, sign-in and profile now with the goal step as `FirstGoalStep` embedding #72's form; if #72 hasn't merged when build starts, ship the step with only "Skip for now" and a follow-up Issue swaps in the form** (flag still set at that step). (b) Wait for #72. (c) Drop the step from #64 entirely.
- **Q-10 401 scope.** **#64 handles 401 only for its own calls (launch `GET /users/me`, onboarding PUTs): clear token, go to Welcome.** The app-wide "any 401 → sign-in" and log out stay in #38, which reuses `clearSignIn()` and `LaunchGate`.
- **Q-11 #51 limits.** **Client checks birth year 1900…this year and name ≤60 now; the server limits stay in #51.**
- **Q-12 Module name** **`OnboardingCore`** (like `LiftCore`, `GoalsCore`). **No walkthrough**; AC-11–12 by hand.

## Progress
- [x] Plan approved
- [ ] Scaffold
- [ ] Tests red
- [ ] Build green
- [ ] Review
- [ ] PR
