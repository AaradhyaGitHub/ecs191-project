"""Checks the layer rules from CLAUDE.md, so they can't drift silently.

- services/ never imports Flask (it must be testable without a request).
- Only models.py imports google.cloud.datastore.
"""
from pathlib import Path

SERVER = Path(__file__).resolve().parents[1]


def python_files(folder: str):
    return sorted((SERVER / folder).rglob("*.py"))


def imports(path: Path, module: str) -> bool:
    for line in path.read_text().splitlines():
        line = line.strip()
        if line.startswith((f"import {module}", f"from {module}")):
            return True
    return False


def test_services_never_import_flask():
    offenders = [p.name for p in python_files("services") if imports(p, "flask") or imports(p, "werkzeug")]
    assert offenders == []


def test_only_models_touches_datastore():
    code = [p for p in SERVER.rglob("*.py") if "tests" not in p.parts and ".venv" not in p.parts]
    offenders = [str(p.relative_to(SERVER)) for p in code
                 if p.name != "models.py" and imports(p, "google.cloud")]
    assert offenders == []
