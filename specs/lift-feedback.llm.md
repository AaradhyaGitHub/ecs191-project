Status: Approved by Sasa, Nov 4, 2026
Branch: feat/67-lift-feedback

# Plan: rest countdown and saved-workout changes (#67; spec `specs/lift-feedback.md`)
LLM-written. Sasa's spec wins where they differ. Built on main (195af30); assumes PR #68 (the #63 polish) merges first.

## Decided (Sasa, Nov 4, 2026)
1. **App open:** short beep each second from 10 s left, long beep at 0, a haptic tap with each. Beeps mix over music (no ducking, Q-6), follow the silent switch (on silent: vibration only, no Critical Alerts).
2. **Closed or locked:** at rest start, schedule "10 seconds left" (our 10-s countdown sound) and "Rest is over" at 0. While open, the delegate hides them. Leaving with ≤10 s: remove pending, send one now with `countdown_<n>` for the time left, keep "Rest is over". Back in the app: remove pending and delivered. About 1 s precision is fine.
3. Sounds made by our own script, each under 30 s. Time Sensitive level (entitlement if needed). Permission asked the first time a rest timer starts.
4. "Save as a workout" keeps every exercise; unlogged ones get 3 sets and the default rest, 90 s (`SetDraft.defaultRestS`, `TemplateLimits.defaultRest`). Warm-ups still don't count; max 30 exercises.
5. A changed workout from a saved workout asks after Finish "Update '<name>' with your changes?" (Update, Save as new, Not now) in place of the save sheet. Changed = exercises added, removed, reordered, or targets changed. Update keeps name and focus via `PUT /templates/{id}` (no contract change). Save as new opens the existing sheet. Live Activity is 🟪 #66.

## Acceptance criteria
LiftCore (`swift test`)
- **AC-1** `countdownCues`: `.tick(n)` at n = 10…1 s before `endsAt`, `.end` at `endsAt`, only times after `now`. A 5-s rest starts at `.tick(5)`. No timer or ended → `[]`.
- **AC-2** `restNotices(…, leavingApp: false)`: >10 s left → "10 seconds left" at `endsAt − 10` with `countdown_10.caf`, and "Rest is over" at `endsAt` (sound: Q-9). ≤10 s → only "Rest is over". No timer or ended → `[]`.
- **AC-3** `leavingApp: true` with ≤10 s: one notice now (`fireAt` nil) with `countdown_<n>.caf`, n = seconds left rounded, 1–10, plus "Rest is over". >10 s → as AC-2. Fixed ids, so a new plan replaces the old.
- **AC-4** `templateInput(from: ActiveWorkout, …)`: every exercise once; logged ones by today's rules; unlogged or warm-up-only ones take their block's targets, else 3 sets, 90 s, reps nil (Q-2); `supersetGroup` from the block; order per Q-1; first 30. `canSaveAsTemplate` keeps today's rule.
- **AC-5** `hasChanges` true for an added, removed or reordered exercise or a changed target (Q-3, Q-4), else false. `updateInput`: the template's `id`, `name`, `focus`, exercises from the workout, no `lastDoneAt`.
- **AC-6** `afterFinish`: not from a saved workout → `.saveAsWorkout` if `canSaveAsTemplate`; from one in `templates` and changed → `.askToUpdate`; unchanged, missing, or signed out → `.nothing`.

App (by hand; a device for sound, taps, lock screen, silent switch)
- **AC-7** Beeps and taps as Decided 1 on any screen while open (Q-7). −30s, +30s, Skip, a new set, Finish and Discard update or cancel beeps and notices. Permission prompt at the first rest, not at launch; denied → beeps and taps still work.
- **AC-8** Locked or closed: notices as Decided 2, Time Sensitive. Back in the app: no banner, no double sound.
- **AC-9** `scripts/make_sounds.py` makes `countdown_1`…`_10`, `beep_short`, `beep_long` (.caf), each under 30 s (`afinfo`).
- **AC-10** The update question after Finish, from the workout screen and from #63's Resume-card Finish. Update → the card shows the new exercises; Save as new → existing sheet; Not now → nothing; failure per Q-5.

## Interface (no API change)
```swift
// LiftCore/RestAlerts.swift (new)
public enum CountdownCue: Equatable, Sendable { case tick(secondsLeft: Int), end }
public struct TimedCue: Equatable, Sendable { public let at: Date; public let cue: CountdownCue }
public func countdownCues(endsAt: Date?, after now: Date) -> [TimedCue]
public enum RestNoticeID { public static let tenLeft = "rest.ten-left"; public static let over = "rest.over" }
public struct RestNotice: Equatable, Sendable { public let id: String; public let fireAt: Date?; public let title: String; public let sound: String? }
public func restNotices(endsAt: Date?, now: Date, leavingApp: Bool) -> [RestNotice]
public func countdownSound(secondsLeft: Int) -> String          // "countdown_7.caf", kept in 1…10
// LiftCore/SaveAsWorkout.swift (new)
public func canSaveAsTemplate(_ workout: ActiveWorkout) -> Bool
public func templateInput(from workout: ActiveWorkout, name: String, focus: String?) -> TemplateInput?
public func hasChanges(_ workout: ActiveWorkout, from template: Template) -> Bool
public func updateInput(for template: Template, from workout: ActiveWorkout) -> TemplateInput
public enum AfterFinish: Equatable, Sendable { case nothing, saveAsWorkout, askToUpdate(Template) }
public func afterFinish(_ workout: ActiveWorkout, templates: [Template], signedIn: Bool) -> AfterFinish
```
The `Workout` versions in `SavedWorkouts.swift` stay (their tests stay green); the app moves to these. `onFinished` passes the `ActiveWorkout` as it was at Finish.

## Files
- New: `LiftCore/RestAlerts.swift`, `LiftCore/SaveAsWorkout.swift`; `Features/Lift/RestAlertController.swift` (notices, delegate, `AVAudioPlayer` beeps, taps), `Features/Lift/UpdateWorkoutSheet.swift`; `ios/MuscleMap/Resources/Sounds/*.caf`; `scripts/make_sounds.py`; `ios/MuscleMap/MuscleMap.entitlements`. All through the Xcode MCP.
- Changed: `SavedWorkouts.swift` (3 private helpers → internal), `ActiveWorkoutModel.swift` (rest-end vibration moves to the controller), `ActiveWorkoutView.swift`, `SetLogView.swift` (drop `.sensoryFeedback`), `LiftView.swift`, `SavedWorkoutsModel.swift`, `SaveAsWorkoutSheet.swift` (takes `ActiveWorkout`), `PreviewData.swift`.
- **Hot spots:** `ios/MuscleMap/App/MuscleMapApp.swift` (make the controller, set the delegate at launch, watch `session.active?.restTimer` and `scenePhase`); the Xcode project (entitlement, sounds). `Package.swift` doesn't change.
- **Also changed by #63:** `LiftView.swift`, `ActiveWorkoutView.swift`, `SetLogView.swift`, `SavedWorkouts.swift`. Rebase on #63 first. Not touched: `SetEntrySheet`, `SavedWorkoutCard`, `SetTexts`, `RestStrip`.

## Reuse
`RestTimer.endsAt`, `LiftSession`, `mostCommonReps`, `medianRest`, `TemplateLimits`, `SavedWorkoutsModel.save`, `APIClient.updateTemplate`, `SaveAsWorkoutSheet`, `NoticeLine`, `PrimaryButton`, `Theme`. Apple: `UNUserNotificationCenter` (time-interval trigger, nil trigger = now, `UNNotificationSound(named:)`, `.timeSensitive`, `willPresent` → `[]`), `AVAudioSession` `.ambient`, `UIImpactFeedbackGenerator`. Script: Python `wave` + `afconvert`. No new dependency.

## Tests
`Tests/LiftCoreTests/RestAlertsTests.swift` (AC-1–3), `SaveAsWorkoutTests.swift` (AC-4–6): `swift test --package-path ios/MuscleMapKit --filter LiftCoreTests`. AC-7–10: walkthrough plus a device check by Sasa.

## Test-writer may read
- `ios/MuscleMapKit/Sources/LiftCore/RestAlerts.swift`
- `ios/MuscleMapKit/Sources/LiftCore/SaveAsWorkout.swift`
- `ios/MuscleMapKit/Sources/LiftCore/SavedWorkouts.swift`
- `ios/MuscleMapKit/Sources/LiftCore/ActiveWorkout.swift`
- `ios/MuscleMapKit/Sources/LiftCore/SetEntryRules.swift`
- `ios/MuscleMapKit/Sources/Models/Template.swift`
- `ios/MuscleMapKit/Sources/Models/Workout.swift`
- `ios/MuscleMapKit/Sources/Models/Exercise.swift`

## Decided from the open questions, Q-1 to Q-10 (Sasa, Nov 4, 2026)
1. **Save order:** logged exercises in first-set order (today), then unlogged ones in block order.
2. **Unlogged, no target:** reps nil (the sheet uses the last set, else 8).
3. **"Targets changed":** more non-warm-up sets than the target, or different most common reps. Fewer sets and rest don't count. Update writes sets = max(target, done), reps = done, rest kept.
4. **Reordered/removed:** compare block order. The app can't reorder or remove blocks yet, so only "added" and targets fire now. Exercises skipped at Start (not in the library) aren't "removed"; Update keeps them at the end.
5. **Update UI and failure:** a sheet like the save sheet; it keeps the error with Try again; Not now drops it. No offline queue.
6. **Music and the silent switch:** `.ambient`: beeps mix over music at full volume (no ducking) and the silent switch mutes them; taps still work. Replaces "ducking" in Decided 1. The build may try `.ambient` + `.duckOthers` on a device; if iOS refuses, no ducking.
7. **Beeps outside the workout screen:** yes, anywhere in the app while it is open.
8. **Back in the app:** after removing, schedule the plan again (hidden while open), so a lock needs no background time.
9. **"Rest is over" sound:** none; the countdown sound already ends with the long beep.
10. **Time Sensitive signing:** if our team can't sign the entitlement, stop and ask (fallback: normal level).
11. **Control Center or the app switcher** count as open (`.inactive`): the app keeps beeping. (Sasa, Nov 4, 2026)
12. **Time Sensitive entitlement stays:** Sasa signs with a paid Apple Developer account. A teammate with a free Personal Team may get a signing error and can remove the capability locally (not committed). (Sasa, Nov 4, 2026)

## Walkthrough
Setup: lane 2, server on 5001 with emulator 8093 (`seed.load_exercises`), Debug test sign-in, "Push 1" (2 exercises) made with `POST /templates`. Video has no sound and the Simulator has no haptics: beeps and taps are checked on a device; banners are best effort.
1. Lift → Start "Push 1". Log a set with REST AFTER 0:30. Check: permission prompt (screenshot). Tap Allow.
2. Wait in the app to 0:00. Check: no banner.
3. Log a set with 0:30 rest, go to the Home screen. Check: "10 seconds left", then "Rest is over" (screenshot). None in 40 s → skip, say so.
4. Open the app. Add exercise → Push-up → Finish. Check: the update question (screenshot).
5. Tap Update. Check: the "Push 1" card shows 3 exercises (screenshot).
6. Empty workout, 2 exercises, log 1 set of the first, Finish → Save. Check: new card shows 2 exercises (screenshot).

## Progress
- [x] Plan approved (1ad72a0)
- [x] Scaffold (4e6ab19)
- [x] Tests red (af40a0c)
- [x] Build green (a3b7ece)
- [x] Review (0 blockers, 0 should-fix, 1 nit fixed: 07abc29)
- [ ] PR
