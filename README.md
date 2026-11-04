# Muscle Map

An iOS workout tracker that shows which muscles you've trained. ECS 191 group project, UC Davis.

- **App:** SwiftUI, iOS 17+ (`ios/`)
- **Server:** Flask on Google App Engine, Firestore in Datastore mode (`server/`)

> Work in progress: the server is deployed (health check only so far) and the app has its four tabs; the Lift tab is next.

## Run the server locally
**Prerequisites**
- **Python 3.13.** With [uv](https://docs.astral.sh/uv/): `uv python install 3.13`. Or install it from python.org.
- **Google Cloud CLI** (`gcloud`): [install guide](https://cloud.google.com/sdk/docs/install). Then `gcloud components install cloud-firestore-emulator`.
- **Java 25 or newer**, which the database emulator runs on (it refuses older Java). With Homebrew: `brew install openjdk`, then put it first on your PATH: `export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"` (add that line to `~/.zshrc` to keep it).

```sh
# one time, from the repo root
cd server
uv venv --python 3.13 .venv          # or: python3.13 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt -r requirements-dev.txt   # with uv: uv pip install -r ...

# terminal 1: Datastore-mode emulator, so nobody touches the real database
gcloud emulators firestore start --database-mode=datastore-mode --host-port=localhost:8081

# terminal 2, from server/ with the venv active
export DATASTORE_EMULATOR_HOST=localhost:8081
python -m seed.load_exercises   # loads the 45 starter exercises (safe to re-run; the emulator forgets them when it stops)
flask --app main run --port 5000
curl http://localhost:5000/api/v1/health   # → {"status": "ok"}
```

## Signing in during development
Use the course's **test number `+15305550000` with code `123456`**: no text message is sent and nothing needs setting up. Real phone numbers only work once the course `app_token` is configured on the server.

To get a token for trying endpoints by hand (server running locally):
```sh
curl -s -X POST localhost:5000/api/v1/auth/sms/verify -H 'Content-Type: application/json' \
  -d '{"phone_number": "+15305550000", "code": "123456"}'
# → {"token": "...", "user_id": "..."}; then send: -H "Authorization: Bearer <token>"
```
In server tests, the `signed_in` fixture gives you a signed-in user in one line, and `course_auth` fakes the course service so tests never touch the network.

## Run the app
Requires **Xcode 27.2 or newer**: the project uses Xcode 27's project format, which older Xcode versions can't open. The app itself runs on iOS 17 and later, iPhone only.

Open `ios/MuscleMap.xcodeproj` in Xcode and run on a simulator. If no simulators are listed, install the matching iOS simulator in Xcode → Settings → Components. Debug builds talk to `http://localhost:5000`. On a real phone, use your laptop's network address instead.

## Tests
```sh
cd server && pytest                      # everything; emulator tests skip if the emulator isn't running
cd server && pytest -m "not emulator"   # fast: no database
cd server && pytest -m emulator         # needs the emulator and DATASTORE_EMULATOR_HOST
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
Live server: **https://musclemap-ecs191.wl.r.appspot.com** (check: `/api/v1/health`). Release builds of the app use it.

Google Cloud project: `musclemap-ecs191` (App Engine and the Datastore-mode database in `us-west2`). To load the starter exercises into it: `python -m seed.load_exercises --project musclemap-ecs191`.

## Keys and test credentials
No keys are in this repo. _To be listed here: which keys are needed and where to get them, plus test sign-in credentials._

## Working on this repo
- Work is claimed through GitHub Issues: assign yourself, then branch `feat/<issue>-<slug>`.
- Every change goes through a PR; a teammate merges.
- Claude Code users: the rules are in [CLAUDE.md](CLAUDE.md). Claude never edits the human-written docs (`overview.md`, the architecture docs, `specs/`).
- Keep personal notes and keys in `.private/` (gitignored).
