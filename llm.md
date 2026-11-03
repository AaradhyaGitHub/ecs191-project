# Claude's notes

LLM-written. This is Claude's running record of the design: what's been decided, where it came from, and what's still open. The team's own descriptions live in the human-authored files (`overview.md`, the architecture docs, `specs/`), which take precedence over anything here.

## Sources
- **Muscle Map — Project Setup Guide** (team doc, Nov 3, 2026): stack, repo layout, Google Cloud setup, data model, first endpoints, iOS setup, required course files, setup checklist.
- **Lift Tab UI** (team mockups): the four Lift screens and the design tokens.

These two documents aren't in the repo. Their content is summarized in `server_architecture.llm.md` (data model, server), `client_architecture.llm.md` (app, design tokens) and `API.md` (endpoints).

## Decisions
| Decision | Source |
|---|---|
| Stack: SwiftUI app (iOS 17+), Flask on App Engine (Python 3.13), Firestore in Datastore mode via `google-cloud-datastore` | Setup guide |
| The app never talks to the database and doesn't use the Firebase SDK; everything goes through the Flask API | Setup guide (course requirement) |
| One repo: `ios/`, `server/`, `shared/`, course docs at the root | Setup guide |
| Four tabs, each with icon and label: Home, Lift, Goals, Camera. Only Lift is built for real first; Camera is behind a feature flag, hidden from testers | Setup guide |
| The Exercise library tile is dropped: exercise search lives in Create workout, per-exercise records in History (on Home) | Setup guide |
| "Custom plan" is a disabled tile marked "Soon" until multi-week programs are designed | Setup guide |
| Region `us-west2` for App Engine and the database (both permanent) | Setup guide |
| Sign-in by SMS code, adapted from the course's SMS authentication example | Setup guide |
| Store sets; compute style, e1RM, volume, muscle levels and goal progress on request | Setup guide |
| Weights stored in kg | Setup guide |
| The active workout lives on the phone (SwiftData) and is sent once on Finish | Setup guide |
| Dark mode only | Setup guide (`.preferredColorScheme(.dark)`), Lift Tab UI |
| Workflow: spec → approved plan → scaffold → tests → build → review → PR; humans approve the plan and merge | Team setup session, Nov 3, 2026 |
| Design tokens: the Lift Tab UI set (`background`, `surface`, `surfaceRaised`, `sheet`, `accent`, `onAccent`, `textPrimary`, `textSecondary`, `intensity` 0–4), plus `border`, which has the same value as `surfaceRaised` for now so borders can change on their own. The setup guide's `surfaceBorder` name is dropped | Sasa, Nov 3, 2026 |
| Muscles are tracked at head level (`triceps_long`), each with a `parent` muscle (`triceps`) and a `group` (`arms`), so the Home body map can shade small regions while chips and filters roll up. Start with about 45 heads. IDs are stable: new muscles are only ever added, never renamed or reused. An exercise may point at a parent ID, which spreads its weight evenly across that muscle's heads | Sasa, Nov 3, 2026 |
| The muscle list isn't limited to what the body map can show. The map starts as a 2D drawing, and mapping IDs to its regions is the Home tab's job, not part of `shared/muscles.json`. A muscle with no region of its own still counts, and can appear in a detailed list view later | Sasa, Nov 3, 2026 |
| "UP NEXT" on Lift home is the saved workout done longest ago (from `Template.last_done_at`; never-done workouts first) | Sasa, Nov 3, 2026 |
| Saved workout (Template) IDs are UUIDs made on the phone, like workouts and sets, so saving is safe to retry | Sasa, Nov 3, 2026 |
| Muscle chips on a saved-workout card: the 3 parent muscles (not heads) the workout works most, summed over its exercises' target sets × muscle weights, each shaded by its share of that work (intensity 0–4). Computed by the server and returned with `GET /templates`. Heads only matter for the body map | Sasa, Nov 3, 2026 |
| API conventions: lists wrapped in an object; six error codes (`bad_request`, `unauthorized`, `forbidden`, `not_found`, `conflict`, `internal`); a repeated `POST /workouts` returns `200` with the same body (first time `201`); `PUT /users/me` is a partial update | Sasa, Nov 3, 2026 |
| `POST /workouts` body = the guide's example plus phone-made `id`s on the workout and each set, `timezone` and `local_date`, as the guide's data model requires | Sasa, Nov 3, 2026 |
| Weights are stored as the exact kg conversion, never rounded (157.5 lb → 71.4408 kg); the app rounds only for display, so values round-trip exactly | Sasa, Nov 3, 2026 |
| The plate loader supports both lb (45 lb bar; 45, 35, 25, 10, 5, 2.5) and kg (20 kg bar; 25, 20, 15, 10, 5, 2.5, 1.25), with a kg/lb toggle. lb is the expected default. Details (whether the toggle also changes the profile's units) go in the Lift set-entry spec | Sasa, Nov 3, 2026 |
| **Pending team agreement:** dumbbell sets log one dumbbell's weight ("the 50s" = 50). Each exercise has `implement_count` (1 or 2), and volume multiplies by it | Sasa (proposed to the team), Nov 3, 2026 |
| iOS logic lives in a local Swift package, `ios/MuscleMapKit/`, from day one: one module per area (`Models`, `Networking`, `LiftCore`; later `HomeCore`, `GoalsCore`), each with its own test target, run with `swift test` without the simulator. The app target holds only views and wiring. This replaces the setup guide's `ios/MuscleMap/Models/` and `Networking/` folders | Sasa, Nov 3, 2026 |
| Home's history must reach any point in time: `GET /workouts` gets a `before=<timestamp>` parameter when Home is built, and the muscle map will need an end date as well as a window | Sasa, Nov 3, 2026 |
| Workouts keep a `status` on the server. For now the app only sends finished workouts, so the server always stores `finished`; `active` is for when sets are saved live later | Sasa, Nov 3, 2026 |

## To do (not now)
- **Handover:** `client_architecture.md` (human-written) must explain the `MuscleMapKit` package split and why it exists, so the next team knows where code goes. Sasa writes it.
- A smarter "UP NEXT": predict which workout you're likely to do today from your recent pattern (for example, what you did on this weekday last week).
- Import a public exercise dataset, stored with `source: dataset` and mapped onto our parent IDs. Check its license first (for example `free-exercise-db` is public domain; `wger` data is share-alike).
- A detailed "every muscle used" view, beyond the regions on the body map.
- Tapping a saved-workout card shows every muscle it works, not just the 3 chips.

## Open questions
0. **For the team:** confirm the dumbbell rule above (log one dumbbell; `implement_count` on each exercise).
1. ~~Design token names~~: decided (see Decisions).
2. **`shared/muscles.json`**: the level of detail is decided (see Decisions). Still open: the actual list of about 45 heads, parents and groups. Claude drafts it as a contract PR for the team to review.
3. **Entity fields**: the setup checklist asks the team to agree on the data model in `server_architecture.llm.md` before building.
4. **Request and response shapes for sign-in** (`/auth/sms/*`) depend on the course's SMS example, which isn't in the repo yet.
5. ~~Swift package for app logic~~: decided (see Decisions).
