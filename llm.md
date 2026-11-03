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

## Open questions
1. ~~Design token names~~: decided (see Decisions).
2. **`shared/muscles.json`**: the muscle IDs, names and groups. The setup checklist says the team agrees on it together.
3. **Entity fields**: the setup checklist asks the team to agree on the data model in `server_architecture.llm.md` before building.
4. **Request and response shapes for sign-in** (`/auth/sms/*`) depend on the course's SMS example, which isn't in the repo yet.
5. **Swift package for app logic**: putting models, networking and feature logic in a local Swift package would let those tests run in seconds without the simulator. It's an architecture choice for `client_architecture.md`.
