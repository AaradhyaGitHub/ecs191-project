"""The seed loader: refuses to touch a real database by accident, and loads the library
into the emulator so it reads back unchanged."""
import json
from pathlib import Path

import pytest

from seed import load_exercises

SEED = json.loads((Path(__file__).resolve().parents[1] / "seed" / "exercises.json").read_text())["exercises"]


def test_refuses_without_emulator_or_project(monkeypatch, capsys):
    monkeypatch.delenv("DATASTORE_EMULATOR_HOST", raising=False)
    assert load_exercises.main([]) == 2
    assert "Refusing to run" in capsys.readouterr().err


@pytest.mark.emulator
def test_loads_every_exercise(emulator):
    import models

    assert load_exercises.main([]) == 0
    assert len(models.all_exercises()) == len(SEED)


@pytest.mark.emulator
def test_loading_twice_changes_nothing(emulator):
    import models

    load_exercises.main([])
    load_exercises.main([])
    assert len(models.all_exercises()) == len(SEED)


@pytest.mark.emulator
def test_an_exercise_reads_back_exactly(emulator):
    import models

    load_exercises.main([])
    bench = next(e for e in SEED if e["id"] == "barbell_bench_press")
    assert models.get_exercise("barbell_bench_press") == bench


@pytest.mark.emulator
def test_library_is_sorted_by_name(emulator):
    import models

    load_exercises.main([])
    names = [e["name"].lower() for e in models.all_exercises()]
    assert names == sorted(names)


@pytest.mark.emulator
def test_missing_exercise_is_none(emulator):
    import models

    assert models.get_exercise("no_such_exercise") is None
