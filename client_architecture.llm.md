# Client architecture: Claude's notes

LLM-written summary of the team's setup guide and the Lift Tab UI mockups. The human-written `client_architecture.md` takes precedence.

## App
Xcode iOS App, SwiftUI, Swift, iOS 17+: SwiftData for local storage and `@Observable` for view models. Dark mode only.

| Folder (`ios/MuscleMap/`) | Holds |
|---|---|
| `App/` | App entry and `RootView` (the `TabView`) |
| `DesignSystem/` | `Theme.swift` and the shared components |
| `Models/` | `Codable` structs that mirror the API JSON exactly: `Exercise`, `Template`, `Workout`, `SetEntry`, `User`. Decoded with `.convertFromSnakeCase` and ISO 8601 dates |
| `Networking/` | `APIClient.swift`: one async client, a method per endpoint. Base URL from the build configuration: `http://localhost:5000` for Debug, the App Engine URL for Release. Sign-in token in the Keychain, never UserDefaults |
| `Features/{Home,Lift,Goals,Camera}/` | One folder per tab |
| `PreviewData/` | Mock data for SwiftUI previews |
| `Resources/ThirdParty/` | The paid 3D model. Gitignored; never commit it |

A real phone needs the laptop's network address and `NSAllowsLocalNetworking` in Info.plist for plain HTTP to the local server.

## Tabs
| Tab | SF Symbol | Contents | First build |
|---|---|---|---|
| Home | `house.fill` | Muscle map, streak, goal rings, today's summary, past workouts (History) | Placeholder |
| Lift | `dumbbell.fill` | Create tiles, saved workouts with Start, the active workout, set entry | **Real** |
| Goals | `target` | Frequency, volume, strength, balance and style goals | Placeholder |
| Camera | `camera.viewfinder` | Record a set and count reps (stretch goal) | Placeholder, behind `FeatureFlags.cameraTab` |

Every tab shows its icon and its label; the selected tab uses `accent`.

## Lift screens (from the mockups)
1. **`LiftHomeView`:** large title "Lift" with Edit. CREATE section: an *Empty workout* tile ("Add exercises as you go") and a *Custom plan* tile ("A multi-week program", disabled, "Soon" pill). SAVED WORKOUTS · n: cards with name, focus, exercise count, last-done time ("6 days ago"), muscle chips and Start. The next workout in rotation is highlighted with an accent border, an UP NEXT badge and an accent Start button.
2. **`ExercisePickerView`** ("New workout", Cancel): search field, muscle-group filter chips (All, Chest, Back, Legs, Shoulders, …). YOUR EXERCISES with a Recent / Most used toggle, each row showing the last set ("Last: 155 lb × 5 · 2 days ago") and a checkbox. ALL EXERCISES rows show muscles and load type with a + button. Bottom: a "Pair as superset" toggle and a primary button ("Add 2 as superset").
3. **`ActiveWorkoutView`:** back to Lift, workout clock, workout name, a segmented progress bar. An UP NEXT card (supersets show "Push-up + Inverted Row", rounds and rest pattern, and Start), then the next exercise ("then"), then DONE with a count and each finished exercise's set count. Bottom: Add exercise and Finish.
4. **`SetLogView`** (e.g. "Superset A"): filter chips (All and one per exercise); "7 sets · in the order you did them"; each row has a set badge (W for warm-up, F for failure, else a number), exercise, rest before the set (or "First set · 6:02 PM"), reps, load (BW, BW +10 lb, or weight) and an effort battery. A rest strip with −30s, +30s and Skip, and a + button.
5. **`SetEntrySheet`** (bottom sheet over the exercise): set number and type (Warm-up, Working, Drop set, Failure); a hero weight with "Same as last set" and the plate breakdown ("45 bar + 55 per side"); a plate loader (bar drawing; plate buttons 45, 35, 25, 10, 5, 2.5 add pairs; tap the bar to remove; Reset); REPS stepper; REST AFTER with ±30; EFFORT 60–100% (100% = failure); a primary "Log 6 × 155 lb" button. Bodyweight exercises show bodyweight ± load, timed holds show seconds.

## Design tokens (Lift Tab UI)
Dark only. Inter in the mockups, SF Pro on device. 8 pt spacing.

| Token | Use | Value |
|---|---|---|
| `background` | Screen background | `#111214` |
| `surface` | Cards, rows, inputs | `#1C1D21` |
| `surfaceRaised` | Steppers, secondary buttons | `#2A2C31` |
| `border` | Card and input outlines (same value as `surfaceRaised` for now) | `#2A2C31` |
| `sheet` | Bottom sheets | `#17181C` |
| `accent` | Primary buttons, selected tab, Up next | `#F08A4B` |
| `onAccent` | Text and icons on accent | `#1A0F08` |
| `textPrimary` | Titles, values | `#F2F2F0` |
| `textSecondary` | Captions, labels, inactive tabs | `#9AA0AA` |
| `intensity` 0–4 | Muscle shades, none to heavy | `#2F343E`, `#5C3B2E`, `#9C4A2A`, `#E0662E`, `#FFB46E` |

Decided Nov 3, 2026: this is the token set for `Theme.swift`. The setup guide's `surfaceBorder` is replaced by `surfaceRaised` and `border`.

**Type:** large title 34/700; hero number 52/700, tabular; card title 20/700; row title 16/600; secondary 14/400; section header 12/600 caps, +0.1em tracking.

**Shape:** cards radius 16; buttons 12–14; chips 8; pills 999. Screen gutter 16. Touch targets at least 44 pt. Primary button 52–54 tall.

## Shared components
| Component | What |
|---|---|
| `TabBar` | Four tabs, icon over label; accent = selected |
| `CardView` | Surface, radius 16, 1 pt `border`; accent border when highlighted |
| `PrimaryButton` | Accent fill, onAccent text, 52 tall |
| `MuscleChip` | Muscle name with an intensity square |
| `SectionHeader` | Caps label with optional count |
| `EffortBattery` | Battery drains from 60% to 90%; flame at 100% |
| `RestStrip` | Countdown with −30s, +30s, Skip |
| `PlateLoader` | Bar drawing plus plate buttons; adds pairs |
