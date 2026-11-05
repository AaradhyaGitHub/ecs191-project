# Client architecture
## Stack

SwiftUI, iOS 17+, `@Observable` view models, and SwiftData for the open workout. Dark mode only.

## The split, and why

Screens go in the app target (`ios/MuscleMap/`); logic goes in the `MuscleMapKit` package (`Models`, `Networking`, `LiftCore`, `BodyCore`). Package code must build on macOS and avoid UIKit so its tests run quickly with `swift test`, without the simulator.

- **Models:** Codable structs matching the API JSON.
- **Networking:** `APIClient`, with one method per endpoint.
- **LiftCore:** Plate math, rest timer, supersets, and UP NEXT.
- **BodyCore:** Muscle IDs, SVG figures, and workout analysis.

## Tabs and what each holds

- **Home:** Placeholder for a muscle map, streak, goal rings, and history.
- **Body:** MuscleLab prototype using sample data.
- **Lift:** Built.
- **Goals:** Placeholder.
- **Camera:** Behind `FeatureFlags.cameraTab`.

## Lift flow

- Lift home → exercise picker → active workout → set log → set entry sheet.
- The open workout stays on the phone in SwiftData until Finish, then is sent in one `POST /workouts`. After a successful Finish, the local workout is deleted.
- Why: logging works without a connection, and retrying is safe.

## Design choices for experienced lifters

- Pick values, don't type them: plate buttons, ±30 s rest, effort chips.
- Letter badges for set types: W, F, D.
- An effort battery instead of words.

## Networking

- All calls go through `APIClient`; the app never touches the database.
- The sign-in token is kept in the Keychain.
- Debug builds call localhost:5001; Release builds call App Engine.
- The user can switch between lb and kg for the whole app. Weights are converted only for display.
- When the app is closed or the phone is locked, local notifications play the rest-timer countdown.

## Design system

Tokens are in `Theme.swift` (accent #F08A4B, intensity scale 0–4, effort colors), plus shared components.

## Testing

Run package unit tests for a module with:

```sh
swift test --package-path ios/MuscleMapKit --filter <Module>Tests