#!/usr/bin/env bash
# Set up an implementation lane: a second checkout of this repo next to it, with its own
# Python environment and its own database emulator port. Safe to run again.
#
#   scripts/lane.sh 1        -> ../ecs191-impl-1, emulator on localhost:8082
#   scripts/lane.sh 2        -> ../ecs191-impl-2, emulator on localhost:8083
#
# Give a lane its next feature (from the lane folder):
#   git fetch origin && git switch -c feat/<issue>-<slug> origin/main
set -euo pipefail

n="${1:?usage: scripts/lane.sh <lane number, e.g. 1>}"
[[ "$n" =~ ^[1-9]$ ]] || { echo "Lane number must be 1-9." >&2; exit 1; }

repo="$(git rev-parse --show-toplevel)"
lane="$(dirname "$repo")/ecs191-impl-$n"
port=$((8081 + n))   # the main checkout uses 8081

# 1. The folder. A new lane starts on main's latest commit, with no branch yet.
if [ -d "$lane" ]; then
  echo "Lane $n exists: $lane"
else
  git -C "$repo" fetch -q origin main
  git -C "$repo" worktree add -q --detach "$lane" origin/main
  echo "Created lane $n: $lane"
fi

# 2. The Python environment (server/.venv is not in git, so each lane needs its own).
if [ ! -x "$lane/server/.venv/bin/python" ]; then
  echo "Making the Python environment..."
  if command -v uv >/dev/null; then
    (cd "$lane/server" && uv venv -q --python 3.13 .venv \
      && uv pip install -q --python .venv/bin/python -r requirements.txt -r requirements-dev.txt)
  else
    (cd "$lane/server" && python3.13 -m venv .venv \
      && .venv/bin/pip install -q -r requirements.txt -r requirements-dev.txt)
  fi
fi

cat <<EOF

Lane $n is ready: $lane
  Database emulator for this lane (server tests wipe it, so lanes never share one):
    gcloud emulators firestore start --database-mode=datastore-mode --host-port=localhost:$port
  Server tests in this lane:
    cd $lane/server && DATASTORE_EMULATOR_HOST=localhost:$port .venv/bin/python -m pytest
  iOS package tests (the first run builds a cache, about 1-2 minutes):
    swift test --package-path $lane/ios/MuscleMapKit
EOF
