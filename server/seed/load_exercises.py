"""Loads seed/exercises.json into Datastore. Safe to run again: exercises are replaced by slug.

Locally (emulator running):
    cd server && DATASTORE_EMULATOR_HOST=localhost:8081 python -m seed.load_exercises

Against the real Cloud database, only on purpose:
    cd server && python -m seed.load_exercises --project <project-id>
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

SEED = Path(__file__).with_name("exercises.json")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--project", help="real Google Cloud project to load into (skip for the emulator)")
    args = parser.parse_args(argv)

    if args.project:
        os.environ.pop("DATASTORE_EMULATOR_HOST", None)
        os.environ["GOOGLE_CLOUD_PROJECT"] = args.project
    elif not os.environ.get("DATASTORE_EMULATOR_HOST"):
        print("Refusing to run: set DATASTORE_EMULATOR_HOST for the emulator, "
              "or pass --project to load the real database on purpose.", file=sys.stderr)
        return 2

    import models  # imported after the environment is settled, so the right client is made

    exercises = json.loads(SEED.read_text())["exercises"]
    count = models.put_exercises(exercises)
    target = args.project or f"emulator at {os.environ['DATASTORE_EMULATOR_HOST']}"
    print(f"Loaded {count} exercises into {target}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
