# Muscle Map: rules for Claude Code

Muscle Map is a workout tracker that shows which muscles you've trained. It's an ECS 191 (Software Design, UC Davis) group project: a SwiftUI iOS app in `ios/`, and a Flask server on Google App Engine with Firestore in Datastore mode in `server/`. Several teammates work in parallel, and each may run their own Claude Code session.

## Human-authored files (do not edit)
`proposal.md`, `overview.md`, `client_architecture.md`, `server_architecture.md`, everything in `specs/` except `*.llm.md` files, and the user-research files (`discovery_*.md`, `new_user_*.md`, `user_experience_*.md`) are written by the team. Never create, modify, move or reformat them. Read them for context.

When someone wants help with one, help in chat: an outline, questions to answer, feedback on their draft, grammar suggestions. They type it themselves. `.claude/hooks/guard.py` enforces this.

Keep your own notes in `llm.md`, `client_architecture.llm.md` and `server_architecture.llm.md`. A feature's plan goes in `specs/<feature>.llm.md`.

## Where things are
| Path | What |
|---|---|
| `llm.md` | Claude's notes: decisions made so far, open questions. **Read this first.** |
| `server_architecture.llm.md` | Datastore kinds and fields, server layers, write path |
| `client_architecture.llm.md` | iOS tabs, folders, design tokens, Lift screens |
| `API.md` | Every endpoint with request and response JSON. The contract between app and server |
| `specs/` | One human-written spec per feature, plus Claude's plan next to it (`<feature>.llm.md`) |
| `shared/` | `muscles.json` (muscle IDs used by both sides) and contract fixtures |
| `ios/MuscleMap/` | The app target, screens only: `App/`, `DesignSystem/`, `Features/{Home,Lift,Goals,Camera}/` (views), `PreviewData/` |
| `ios/MuscleMapKit/` | Local Swift package with the app's logic, one module per area: `Sources/Models/`, `Sources/Networking/`, `Sources/LiftCore/` (later `HomeCore`, `GoalsCore`), each with a test target in `Tests/<Module>Tests/` |
| `server/` | `main.py`, `api/` (one Blueprint per resource), `services/`, `models.py`, `seed/`, `tests/` |
| `.private/` | Gitignored, per person. Keys go in `.private/secrets/`, which Claude never reads |

## Design rules (from the team's setup guide)
- **The iOS app never talks to the database** and never uses the Firebase SDK. Every read and write goes through our Flask API.
- **Server layers:** handlers in `api/` only parse requests and return JSON; logic lives in `services/`, with no Flask imports; all Datastore reads and writes go through `models.py`.
- **Store what happened, compute everything else.** Sets are stored; style, e1RM, volume, muscle levels and goal progress are computed on request.
- **Weights are stored in kg** and converted to the user's units only at the edges.
- **IDs for workouts and sets are made on the phone** (UUIDs), so `POST /workouts` is safe to retry.
- **The active workout lives on the phone** (SwiftData) and is sent once, on Finish.
- **Errors** are `{"error": {"code": "...", "message": "..."}}` with the matching HTTP status.
- **iOS code split:** logic and models go in the `MuscleMapKit` package; the app target holds only views and wiring. Package code must also build on macOS (no UIKit), so its tests run with `swift test` in seconds, without the simulator. Things the app uses are marked `public`.
- **iOS:** iOS 17+, `@Observable` view models, `Codable` models with `.convertFromSnakeCase` and ISO 8601 dates, sign-in token in the Keychain. Colors, fonts and spacing come from `DesignSystem/Theme.swift` only.
- **Cloud:** one region for everything, `us-west2`. Use the Datastore emulator for development; never point local runs at the real database.
- **No secrets in the repo.** Server keys go in Secret Manager; local keys in `.private/secrets/` or a gitignored `.env`.

**Never make a design decision silently.** If the spec, `llm.md` and the design docs don't settle something (data model, UX, naming users see, a new dependency), give the options with a recommendation and wait. Record the answer, and who decided, under "Decisions" in `llm.md`.

## Workflow
A human is in the loop at two points: **approving the plan** and **merging the PR**.

1. **Claim.** Every piece of work is a GitHub Issue. Assigning yourself claims it. The Issue says what it depends on and which paths it owns. Work on a branch: `feat/<issue>-<slug>`, `fix/<issue>-<slug>` or `chore/<issue>-<slug>`.
2. **Spec.** A human writes `specs/<feature>.md`. No spec, no feature work.
3. **Plan.** `implementer` (plan mode) writes `specs/<feature>.llm.md`. **✋ A human reads it and approves it** by changing its status line to `Approved by <name>, <date>`, or tells you to.
4. **Scaffold.** `implementer` (scaffold mode) creates the interface as stubs.
5. **Tests.** `test-writer` writes tests from the spec and plan and shows they fail. A guard (`.claude/hooks/test_writer_guard.py`) stops it reading any source file except those the approved plan for the current branch lists under `## Test-writer may read`.
6. **Build.** `implementer` (build mode) makes them pass, then runs the full fast suite.
7. **Review.** `reviewer` does one read-only round. A human picks fix or defer for each finding; deferred ones become Issues. If a blocker or should-fix was fixed, `reviewer` checks only those fixes.
8. **PR.** Open it with the template. **✋ A human merges it.** Claude never merges or approves a PR.

**Where am I?** Each plan ends with a `## Progress` checklist (plan approved, scaffold, tests red, build green, review, PR) that `implementer` ticks as steps finish, with the commit for each. Across features, the open and assigned Issues show who's doing what.

The main session runs this: it passes each agent its full brief (the format is at the top of each file in `.claude/agents/`), shows the human the plan and the review, and never skips the two checkpoints.

**Small changes** (docs, config, a typo, a one-line fix) skip steps 2–7: branch, change, PR.

## Contract first, and hot spots
- A new or changed endpoint starts with its own small PR: the `API.md` entry plus example JSON in `shared/fixtures/`. After that merges, the server side and the iOS side can be built in parallel; iOS works against the fixtures until the server is ready.
- **Hot spots** that everyone touches: `server/main.py`, `server/models.py`, `server/index.yaml`, `ios/MuscleMap/App/`, `ios/MuscleMapKit/Package.swift`, `ios/MuscleMapKit/Sources/Models/`, `shared/`, `API.md`. Keep changes to them small and on their own when possible, and say so in the Issue.

## Testing
Run the tests for what you changed, not everything. Run the full fast suite before opening a PR.

| Tier | What | Command | When |
|---|---|---|---|
| Unit (server) | `server/services/` and pure functions, no database | `cd server && pytest tests/<path> -m "not emulator"` | every change, affected files only |
| Integration (server) | endpoints via Flask's test client and the Datastore emulator | `cd server && pytest -m emulator` (emulator running) | before the PR |
| Unit (iOS) | `MuscleMapKit` modules: models, networking, feature logic | `swift test --package-path ios/MuscleMapKit --filter <Module>Tests` (no simulator) | every change, affected modules only |
| UI smoke (iOS) | a few end-to-end flows on the simulator | Xcode MCP `RunSomeTests` | before a milestone |

- Tests mirror the source layout: `server/services/workout_service.py` → `server/tests/services/test_workout_service.py`; an iOS module's tests sit in its own test target.
- Changes to `shared/` or `API.md` run the contract tests on both sides.
- Logic tests go in the package and run with `swift test`. The app target only gets a few UI smoke tests.
- iOS app builds and UI tests go through the Xcode MCP when it's available. Never hand-edit `project.pbxproj`.

## Git
- **Never commit to `main`** and never force-push. Work on a branch, and only on branches you or your human own.
- Commit messages: `feat(<area>): …`, `fix(<area>): …`, `test(<area>): …`, `docs: …`, `chore: …`.
- Stage explicit paths; never `git commit -a`.
- `git push` and `gh pr create` ask first.

## Cloud commands
`gcloud app create`, `gcloud firestore databases create`, deploys, and anything touching projects, services, secrets or buckets ask first. The App Engine region and database location can never be changed, and deploys cost money.
