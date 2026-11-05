"""Writes the app's bundled copy of the exercise library (Sasa, Nov 4, 2026).

The app ships the whole library, so Lift never downloads it (Start uses the bundled copy). The
file is exactly what `GET /exercises` returns for the seed library: `{"exercises": [...]}`, A–Z,
with `groups` and `primary_muscles` worked out by the server's own code. No database needed.

Run it after changing seed/exercises.json or muscles.json:
    cd server && .venv/bin/python -m seed.export_library
tests/test_exercise_library_copy.py fails while the file is out of date.
"""
from __future__ import annotations

import json
from pathlib import Path

from services import exercise_service

SEED = Path(__file__).with_name("exercises.json")
LIBRARY_PATH = (Path(__file__).resolve().parents[2]
                / "ios" / "MuscleMapKit" / "Sources" / "LiftCore" / "Resources" / "exercise_library.json")


def library() -> dict:
    """The whole seed library in API.md's `GET /exercises` shape (no query, no group)."""
    exercises = json.loads(SEED.read_text())["exercises"]
    return {"exercises": exercise_service.search(exercises, None, None, exercise_service.load_muscles())}


def library_text() -> str:
    """The file's exact text: sorted keys, 2-space indent, one newline at the end."""
    return json.dumps(library(), indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def main() -> int:
    LIBRARY_PATH.parent.mkdir(parents=True, exist_ok=True)
    LIBRARY_PATH.write_text(library_text())
    print(f"Wrote {len(library()['exercises'])} exercises to {LIBRARY_PATH}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
