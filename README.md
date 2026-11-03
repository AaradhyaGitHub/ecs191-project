# Muscle Map

An iOS workout tracker that shows which muscles you've trained. ECS 191 group project, UC Davis.

- **App:** SwiftUI, iOS 17+ (`ios/`)
- **Server:** Flask on Google App Engine, Firestore in Datastore mode (`server/`)

> The app and server don't exist yet. The steps below are the plan from the team's setup guide; they'll be checked as each part is built.

## Run the server locally
Requires Python 3.13 and the Google Cloud CLI.

```sh
# one time
gcloud auth application-default login
cd server
python3.13 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt -r requirements-dev.txt

# terminal 1: Datastore-mode emulator, so nobody touches the real database
gcloud emulators firestore start --database-mode=datastore-mode --host-port=localhost:8081

# terminal 2
export DATASTORE_EMULATOR_HOST=localhost:8081
cd server && flask --app main run --port 5000
```

## Run the app
Open `ios/MuscleMap.xcodeproj` in Xcode and run on a simulator. Debug builds talk to `http://localhost:5000`. On a real phone, use your laptop's network address instead.

## Tests
```sh
cd server && pytest -m "not emulator"   # fast: logic only
cd server && pytest -m emulator         # endpoints; emulator must be running
```
```sh
# iOS logic lives in a local Swift package (ios/MuscleMapKit), so its tests run on the Mac, no simulator
swift test --package-path ios/MuscleMapKit                       # all modules
swift test --package-path ios/MuscleMapKit --filter LiftCoreTests # one module
```
The app's few UI smoke tests run from Xcode (⌘U).

## Code layout
- `server/`: Flask app. `api/` handlers stay thin, `services/` holds the logic, `models.py` is the only Datastore access.
- `ios/MuscleMap/`: the iOS app target, screens only.
- `ios/MuscleMapKit/`: a local Swift package with the app's logic, one module per area (`Models`, `Networking`, `LiftCore`, …), each with its own tests. New logic goes here, not in the app target.
- `shared/`: files both sides use, such as `muscles.json` and the API example JSON.
- Why it's laid out this way: see `client_architecture.md` and `server_architecture.md`.

## Deploy
```sh
cd server && gcloud app deploy app.yaml index.yaml
```
Live URL: _not deployed yet_.

## Keys and test credentials
No keys are in this repo. _To be listed here: which keys are needed and where to get them, plus test sign-in credentials._

## Working on this repo
- Work is claimed through GitHub Issues: assign yourself, then branch `feat/<issue>-<slug>`.
- Every change goes through a PR; a teammate merges.
- Claude Code users: the rules are in [CLAUDE.md](CLAUDE.md). Claude never edits the human-written docs (`overview.md`, the architecture docs, `specs/`).
- Keep personal notes and keys in `.private/` (gitignored).
