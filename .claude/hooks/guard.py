#!/usr/bin/env python3
"""PreToolUse guard (wired in .claude/settings.json). See CLAUDE.md "Human-authored files".

- Edit/Write/MultiEdit/NotebookEdit on a human-only file: blocked.
- Bash that writes, moves or deletes a human-only file: blocked (best-effort text match).
- Bash that touches secret files (.env, .private/secrets/, service-account JSON): blocked.
- `git commit` with a human-only file staged: asks the person first, because the
  course wants those files written and committed by people.

Block = exit 2 with the reason on stderr. Ask = JSON on stdout. Allow = exit 0, no output.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys

# Course rule: these are written by people only. *.llm.md files are always Claude's.
HUMAN_ONLY_FILES = {
    "proposal.md",
    "overview.md",
    "client_architecture.md",
    "server_architecture.md",
    "discovery_summary.md",
    "discovery_details.md",
    "new_user_summary.md",
    "new_user_details.md",
    "user_experience_summary.md",
    "user_experience_details.md",
}
HUMAN_ONLY_DIRS = ("specs",)

SECRET_PATTERNS = [
    re.compile(r"\.private/secrets"),
    re.compile(r"(?<![\w.])\.env(?![\w])"),  # .env and .env.local, not .venv
    re.compile(r"service-account[^\s'\"]*\.json"),
    re.compile(r"credentials[^\s'\"]*\.json"),
]
WRITE_COMMANDS = re.compile(
    r"(^|[\s;&|(])("
    r"sed\s+(-[a-zA-Z]*\s+)*-i|perl\s+-[a-zA-Z]*i|tee|mv|cp|rm|truncate|touch|ln|patch|"
    r"git\s+(mv|rm|checkout|restore|apply)"
    r")\b"
)
TOKEN = re.compile(r"[^\s'\"<>|;&()`]+")

PROJECT = os.path.realpath(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())


def rel_to_project(path: str, cwd: str) -> str | None:
    full = os.path.realpath(os.path.join(cwd, os.path.expanduser(path)))
    rel = os.path.relpath(full, PROJECT)
    return None if rel.startswith("..") else rel.replace(os.sep, "/")


def is_human_only(rel: str | None) -> bool:
    if not rel or rel.endswith(".llm.md"):
        return False
    if rel in HUMAN_ONLY_FILES:
        return True
    return any(rel == d or rel.startswith(d + "/") for d in HUMAN_ONLY_DIRS)


def block(reason: str) -> None:
    print(reason, file=sys.stderr)
    sys.exit(2)


def ask(reason: str) -> None:
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "ask",
        "permissionDecisionReason": reason,
    }}))
    sys.exit(0)


HUMAN_ONLY_MSG = (
    "{path} is human-authored (course rule, CLAUDE.md). Claude never creates, edits, moves "
    "or deletes it. Help in chat instead (outline, questions, feedback) and let the person write it."
)


def check_bash(command: str, cwd: str) -> None:
    for pattern in SECRET_PATTERNS:
        if pattern.search(command):
            block("This command touches a secret file (.env, .private/secrets/ or a credentials "
                  "JSON). Claude stays out of those; ask a teammate to handle it.")

    if WRITE_COMMANDS.search(command) or ">" in command:
        for token in TOKEN.findall(command):
            if is_human_only(rel_to_project(token, cwd)):
                if WRITE_COMMANDS.search(command) or re.search(r">>?\s*['\"]?" + re.escape(token), command):
                    block(HUMAN_ONLY_MSG.format(path=token))

    if re.search(r"\bgit\s+commit\b", command):
        names = git_names(["diff", "--cached", "--name-only"], cwd)
        if re.search(r"\s(-[a-zA-Z]*a[a-zA-Z]*|--all)\b", command):
            names += git_names(["diff", "--name-only"], cwd)
        human = sorted({n for n in names if is_human_only(n)})
        if human:
            ask("This commit includes human-authored files: " + ", ".join(human)
                + ". The course wants people to commit these themselves. Allow anyway?")


def git_names(args: list[str], cwd: str) -> list[str]:
    try:
        out = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, timeout=10)
        return [line for line in out.stdout.splitlines() if line]
    except (OSError, subprocess.SubprocessError):
        return []


def main() -> None:
    try:
        event = json.load(sys.stdin)
    except json.JSONDecodeError:
        block("guard.py could not parse the hook input; refusing to guess.")
    tool = event.get("tool_name", "")
    tool_input = event.get("tool_input") or {}
    cwd = event.get("cwd") or PROJECT

    if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
        if is_human_only(rel_to_project(path, cwd)):
            block(HUMAN_ONLY_MSG.format(path=path))
    elif tool == "Bash":
        check_bash(tool_input.get("command", ""), cwd)


if __name__ == "__main__":
    main()
