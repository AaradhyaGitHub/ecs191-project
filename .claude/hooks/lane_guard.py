#!/usr/bin/env python3
"""PreToolUse guard (wired in .claude/settings.json): one agent, one checkout.

The repo can have several checkouts: the main folder and the lanes made by
scripts/lane.sh (git worktrees). One Claude session may send agents to several of them.
The first time an agent changes something in a checkout, that checkout is claimed for
the agent. After that, the agent is blocked from changing any other checkout.

- Only subagents are limited (their hook input has `agent_id`). The main session isn't.
- Edit/Write/MultiEdit/NotebookEdit: the checkout that holds the file.
- Bash: the checkouts named by `cd <dir>`, `git -C <dir>` or a path in the command;
  if there are none, the command's working folder.
- Read, Grep and Glob are not checked, so an agent can still read another checkout.
- Paths outside every checkout (for example a scratch folder) are not checked.

Claims are kept per Claude session in the system temp folder.
Block = exit 2 with the reason on stderr. Allow = exit 0, no output.
"""
from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys
import tempfile

PROJECT = os.path.realpath(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
TAG = "lane guard: "


def block(reason: str) -> None:
    print(TAG + reason, file=sys.stderr)
    sys.exit(2)


def worktree_roots() -> list[str]:
    """The main checkout and every lane (git worktree) of this repo, longest path first."""
    roots = {PROJECT}
    try:
        out = subprocess.run(["git", "-C", PROJECT, "worktree", "list", "--porcelain"],
                             capture_output=True, text=True, timeout=10)
        for line in out.stdout.splitlines():
            if line.startswith("worktree "):
                roots.add(os.path.realpath(line[len("worktree "):]))
    except (OSError, subprocess.SubprocessError):
        pass
    return sorted(roots, key=len, reverse=True)


ROOTS = worktree_roots()


def root_of(path: str, cwd: str) -> str | None:
    full = os.path.realpath(os.path.join(cwd, os.path.expanduser(path)))
    for root in ROOTS:
        if full == root or full.startswith(root + os.sep):
            return root
    return None


def bash_roots(command: str, cwd: str) -> set[str]:
    """Checkouts a Bash command works in: cd / git -C targets and paths it names."""
    try:
        tokens = shlex.split(command, posix=True)
    except ValueError:
        tokens = command.split()
    found: set[str] = set()
    where = cwd
    for i, tok in enumerate(tokens):
        target = None
        if tok == "cd" and i + 1 < len(tokens):
            target = tokens[i + 1]
            where = os.path.realpath(os.path.join(where, os.path.expanduser(target)))
        elif tok == "-C" and i > 0 and tokens[i - 1] == "git" and i + 1 < len(tokens):
            target = tokens[i + 1]
        elif tok.startswith(("/", "~", "../")) or "=/" in tok:
            target = tok.split("=", 1)[1] if "=/" in tok else tok
        if target:
            root = root_of(target, cwd)
            if root:
                found.add(root)
    if not found:
        root = root_of(cwd, cwd)
        if root:
            found.add(root)
    return found


def claims_file(session_id: str) -> str:
    folder = os.path.join(tempfile.gettempdir(), "claude-lane-claims")
    os.makedirs(folder, exist_ok=True)
    safe = re.sub(r"[^A-Za-z0-9_-]", "_", session_id or "unknown")
    return os.path.join(folder, safe + ".json")


def load(path: str) -> dict:
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save(path: str, claims: dict) -> None:
    tmp = path + f".{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(claims, f)
    os.replace(tmp, path)


def name(root: str) -> str:
    return os.path.basename(root)


def main() -> None:
    try:
        event = json.load(sys.stdin)
    except json.JSONDecodeError:
        block("could not parse the hook input; refusing to guess.")
    agent = event.get("agent_id")
    if not agent:
        sys.exit(0)  # the main session coordinates every checkout
    tool = event.get("tool_name", "")
    ti = event.get("tool_input") or {}
    cwd = event.get("cwd") or PROJECT

    if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        root = root_of(ti.get("file_path") or ti.get("notebook_path") or "", cwd)
        touched = {root} if root else set()
    elif tool == "Bash":
        touched = bash_roots(ti.get("command", ""), cwd)
    else:
        sys.exit(0)
    if not touched:
        sys.exit(0)

    path = claims_file(event.get("session_id", ""))
    claims = load(path)
    mine = claims.get(agent)
    if mine is None:
        if len(touched) > 1:
            block("this command works in more than one checkout ("
                  + ", ".join(sorted(name(r) for r in touched))
                  + "). Work in one: cd into your lane first.")
        claims[agent] = touched.pop()
        save(path, claims)
        sys.exit(0)
    other = sorted(name(r) for r in touched if r != mine)
    if other:
        block(f"you work in {name(mine)} ({mine}). This would change "
              + ", ".join(other) + ". Stay in your own checkout: use absolute paths "
              f"inside {mine}, or cd into it first. Reading other checkouts with Read or "
              "Grep is fine.")


if __name__ == "__main__":
    main()
