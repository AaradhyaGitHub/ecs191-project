# Muscle Map

An iOS workout tracker that shows which muscles you've trained. ECS 191 group project, UC Davis.

- **App:** SwiftUI, iOS 17+ (`ios/`)
- **Server:** Flask on Google App Engine, Firestore in Datastore mode (`server/`)

> Work in progress: the server is deployed (health check only so far) and the app has its four tabs; the Lift tab is next.

## Getting started (new teammates)
1. **Install the tools:** Xcode **27.2+**; Python **3.13**; **Java 25+**; the **Google Cloud CLI** with its Firestore emulator. Details are under [Run the server locally](#run-the-server-locally) and [Run the app](#run-the-app).
2. **Run the server and the app once** by following those two sections. Sign in with the test number (see [Signing in during development](#signing-in-during-development)).
3. **Pick your work** from [GitHub Issues](https://github.com/AaradhyaGitHub/ecs191-project/issues) and assign yourself (see [Working on this repo](#working-on-this-repo)).
4. **Building a tab** (Home, Goals, Camera): put its screens in `ios/MuscleMap/Features/<Tab>/` and its logic in `ios/MuscleMapKit` (see [Code layout](#code-layout)). Use `Theme` for every color, font and spacing value, the shared components in `DesignSystem/Components/`, and `PreviewData` for sample data in SwiftUI previews, so you don't need the server to design a screen.
5. **Using Claude Code?** It reads [CLAUDE.md](CLAUDE.md) automatically. Claude's notes on decisions so far are in [llm.md](llm.md), and the API contract is in [API.md](API.md).

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

> ⚠️ **The test account is shared and public.** The number and code are in this README and in the course's docs, so anyone can sign in as that user, including on the live server. Everyone on the team is the *same* user with it. Treat its data as throwaway: never enter anything real or personal, and expect teammates' test workouts to show up.

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
No keys are in this repo, and none should ever be committed (a secret scan runs on every PR).

| What | Needed for | Where it lives | Get it from |
|---|---|---|---|
| Course SMS `app_token` | Signing in with **real** phone numbers (not the test number) | Server environment `SMS_APP_TOKEN` (never in the app) | ECS 191 course staff |
| Google Cloud access | Deploying, reading server logs | Your own Google login (`gcloud auth login`) | Ask Sasa to add you as an editor on `musclemap-ecs191` |
| Local Google credentials | Running server code against the real database (rare; normally use the emulator) | `gcloud auth application-default login` | Your own Google login |

**Test sign-in:** phone `+15305550000`, code `123456` (shared and public; see above).

## Working on this repo
- **Claim work through GitHub Issues:** assign yourself, so everyone sees who's on what. New work gets a new Issue (there's a "Task" template).
- **Branch per Issue:** `feat/<issue>-<slug>`, `fix/<issue>-<slug>`, `chore/<issue>-<slug>`. Never commit to `main`.
- **Every change goes through a PR,** using the template. Someone other than the author merges. Checks run automatically: a secret scan, plus server and iOS tests for the parts you touched.
- **New or changed endpoint? Contract first.** Open a small PR with the `API.md` entry and example JSON in `shared/fixtures/`. Once it's merged, the server side and the iOS side can be built in parallel. Home's `GET /muscle-map` and Goals' `/goals` still need this.
- **Hot spots** that everyone touches: `server/main.py`, `server/models.py`, `server/index.yaml`, `ios/MuscleMap/App/`, `ios/MuscleMapKit/Package.swift`, `ios/MuscleMapKit/Sources/Models/`, `shared/`, `API.md`. Keep changes there small, and mention them in your Issue.
- **Human-written docs:** `overview.md`, `client_architecture.md`, `server_architecture.md`, `specs/*.md` and the user-research files must be written by people (course rule). Claude Code is blocked from editing them; it can help in chat.
- **Design decisions** made so far, and who made them, are in [llm.md](llm.md) → Decisions. If you disagree with one, say so in an Issue.
- Keep personal notes and keys in `.private/` (gitignored).
