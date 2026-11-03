#!/usr/bin/env python3
"""PreToolUse hook for the test-writer agent only (wired in .claude/agents/test-writer.md).

Keeps the test-writer independent of the implementation:
- Read / Grep: app and server source are off limits, except the files the current
  branch's approved plan lists under "## Test-writer may read". Grep needs a path.
- Glob: allowed (file names only, no contents).
- Write / Edit: only test files (server/tests/**, or an iOS folder ending in "Tests").
- Bash: only running tests, emulator reset, and git status/log/add/commit of test files.

The plan for the branch is the specs/*.llm.md file with a line `Branch: <current branch>`
and a status line containing "Approved".
Block = exit 2 with the reason on stderr. Allow = exit 0, no output.
"""
from __future__ import annotations

import glob
import json
import os
import re
import shlex
import subprocess
import sys

PROJECT = os.path.realpath(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
TAG = "test-writer guard: "


def block(reason: str) -> None:
    print(TAG + reason, file=sys.stderr)
    sys.exit(2)


def rel(path: str, cwd: str) -> str | None:
    full = os.path.realpath(os.path.join(cwd, os.path.expanduser(path or ".")))
    r = os.path.relpath(full, PROJECT).replace(os.sep, "/")
    return None if r.startswith("..") else r


def is_test_path(r: str) -> bool:
    parts = r.split("/")
    if r.startswith("server/tests/") or r == "server/tests":
        return True
    return parts[0] == "ios" and any(p.endswith("Tests") for p in parts[1:])


def is_source(r: str) -> bool:
    """App or server code (anything under server/ or ios/ that isn't a test)."""
    return r.split("/")[0] in ("server", "ios") and not is_test_path(r)


def contains_source(r: str) -> bool:
    """A directory that is source or holds source (so a recursive Grep would read it)."""
    return r in (".", "server", "ios") or is_source(r)


def current_branch() -> str:
    try:
        out = subprocess.run(["git", "-C", PROJECT, "branch", "--show-current"],
                             capture_output=True, text=True, timeout=10)
        return out.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def allowed_source_files() -> set[str]:
    branch = current_branch()
    if not branch:
        return set()
    for plan in glob.glob(os.path.join(PROJECT, "specs", "*.llm.md")):
        with open(plan, encoding="utf-8") as f:
            text = f.read()
        if not re.search(r"^\**Branch:?\**:?\s*`?" + re.escape(branch) + r"`?\s*$", text, re.M):
            continue
        if not re.search(r"^\**Status:?\**:?.*\bApproved\b", text, re.M | re.I):
            return set()
        section = re.search(r"^##\s*Test-writer may read\s*$(.*?)(?=^##\s|\Z)", text, re.M | re.S)
        files = set()
        for line in (section.group(1) if section else "").splitlines():
            m = re.match(r"\s*[-*]\s*`?([^`\s]+)`?", line)
            if m:
                files.add(m.group(1).lstrip("./"))
        return files
    return set()


def check_read(path: str, cwd: str) -> None:
    r = rel(path, cwd)
    if r and is_source(r) and r not in allowed_source_files():
        block(f"{path} is implementation code. You may read only the files the approved plan "
              "lists under '## Test-writer may read'. Work from the spec and plan.")


def check_grep(path: str | None, cwd: str) -> None:
    if not path:
        block("Grep needs a `path` outside app and server source (for example server/tests, "
              "an iOS *Tests folder, specs, shared, or an allowed file).")
    r = rel(path, cwd)
    if r is None:
        return
    if r in allowed_source_files():
        return
    if contains_source(r):
        block(f"Grep on {path} would search implementation code. Pick a path outside source.")


def check_write(path: str, cwd: str) -> None:
    r = rel(path, cwd)
    if not r or not is_test_path(r):
        block(f"{path} isn't a test file. You may write only in server/tests/ or an iOS *Tests folder.")


SEGMENT_OK = [
    re.compile(r"cd\s+\S+"),
    re.compile(r"(source|\.)\s+\S*\.?venv/bin/activate"),
    re.compile(r"export\s+[A-Z_][A-Z0-9_]*=\S+"),
    re.compile(r"([A-Z_][A-Z0-9_]*=\S+\s+)*(python3?(\.\d+)?\s+-m\s+)?pytest(\s.*)?"),
    re.compile(r"swift\s+(test|build)(\s.*)?"),
    re.compile(r"curl\s+(-s\s+)?-X\s+POST\s+http://localhost:8081/reset"),
    re.compile(r"git\s+status(\s.*)?"),
    re.compile(r"git\s+log\s+--oneline(\s+-n?\s*\d+|\s+-\d+)?"),
    re.compile(r"git\s+commit\s+-m\s+.+"),
    re.compile(r"ls(\s+-[a-zA-Z]+)*(\s+\S+)*"),
]


def check_bash(command: str, cwd: str) -> None:
    cleaned = command.replace("2>&1", "")
    if any(s in cleaned for s in (">", "<", "$(", "`")):
        block("No redirections or command substitution. Allowed: running tests, emulator reset, "
              "git status/log, and git add/commit of test files.")
    try:
        lexer = shlex.shlex(cleaned, posix=True, punctuation_chars=";&|")
        lexer.whitespace_split = True
        tokens = list(lexer)
    except ValueError:
        block("Couldn't parse that command.")
    segments, current = [], []
    for tok in tokens:
        if tok in (";", "&&", "||", "|", "&"):
            segments.append(current)
            current = []
        else:
            current.append(tok)
    segments.append(current)
    for seg in segments:
        if not seg:
            continue
        text = " ".join(seg)
        if seg[0] == "git" and len(seg) > 1 and seg[1] == "add":
            paths = [p for p in seg[2:] if not p.startswith("-")]
            bad = [p for p in paths if not (rel(p, cwd) and is_test_path(rel(p, cwd)))]
            if not paths or bad:
                block("git add only with explicit test-file paths.")
            continue
        if seg[0] == "git" and len(seg) > 1 and seg[1] == "commit" and any(
                t in ("-a", "--all", "-am") for t in seg):
            block("git commit without -a; stage test files explicitly.")
        if not any(p.fullmatch(text) for p in SEGMENT_OK):
            block(f"'{text}' isn't allowed for the test-writer. Allowed: pytest, swift test/build, "
                  "emulator reset, venv activate, git status / log --oneline, git add/commit of test files.")


def main() -> None:
    try:
        event = json.load(sys.stdin)
    except json.JSONDecodeError:
        block("could not parse the hook input; refusing to guess.")
    tool = event.get("tool_name", "")
    ti = event.get("tool_input") or {}
    cwd = event.get("cwd") or PROJECT

    if tool == "Read":
        check_read(ti.get("file_path", ""), cwd)
    elif tool == "Grep":
        check_grep(ti.get("path"), cwd)
    elif tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        check_write(ti.get("file_path") or ti.get("notebook_path") or "", cwd)
    elif tool == "Bash":
        check_bash(ti.get("command", ""), cwd)
    elif tool.startswith("mcp__xcode__") and tool in (
            "mcp__xcode__XcodeRead", "mcp__xcode__XcodeGrep",
            "mcp__xcode__XcodeWrite", "mcp__xcode__XcodeUpdate"):
        block("Use Read/Grep/Write/Edit instead of the Xcode file tools, so this guard can check paths.")


if __name__ == "__main__":
    main()
