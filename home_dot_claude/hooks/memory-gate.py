#!/usr/bin/env python3
"""PreToolUse hook: make auto-memory writes visible and vetoable.

Claude Code writes auto-memory files without pausing for review, so they
land unseen. This hook intercepts any Write/Edit aimed at the auto-memory
directory and forces a permission prompt. Claude Code then renders its
normal file preview -- full content, line numbers, syntax highlighting --
so the proposed memory can be read and rejected before it is written.

Presentation is deliberately left to Claude Code: the hook only decides
that a prompt must happen, it does not format the content itself.

Non-memory writes pass through untouched (silent exit 0), so this
composes with whatever other PreToolUse hooks are configured.

Install (user settings.json):

    { "matcher": "Write|Edit|MultiEdit",
      "hooks": [{ "type": "command",
                  "command": "/home/node/.claude/hooks/memory-gate.py" }] }

Note: answering "Yes, and allow Claude to edit its own settings" at the
prompt adds a standing allow-rule for ~/.claude and may bypass this gate.
Answer plain Yes or No to keep it in force.

Must never crash: a failing hook should not be able to wedge a session,
so anything unexpected falls through to normal permission handling.
"""

import json
import os
import re
import sys
from pathlib import Path

# Auto-memory lives at ~/.claude/projects/<sanitized-cwd>/memory/ unless
# autoMemoryDirectory overrides it. CLAUDE_CONFIG_DIR moves the root.
MEMORY_RE = re.compile(r"/projects/[^/]+/memory(/|$)")
WATCHED_TOOLS = ("Write", "Edit", "MultiEdit")


def _config_roots():
    roots = []
    env = os.environ.get("CLAUDE_CONFIG_DIR", "").strip()
    if env:
        roots.append(Path(env))
    roots.append(Path.home() / ".claude")
    return roots


def _is_memory_path(raw):
    if not isinstance(raw, str) or not raw:
        return False
    try:
        path = Path(raw).expanduser()
        resolved = str(path.resolve() if path.is_absolute() else path)
    except (OSError, RuntimeError, ValueError):
        resolved = raw

    if not MEMORY_RE.search(resolved):
        return False
    # Confirm it sits under a Claude config root, not some unrelated
    # project that happens to have a projects/*/memory/ layout.
    for root in _config_roots():
        try:
            if resolved.startswith(str(root.resolve()) + os.sep):
                return True
        except (OSError, RuntimeError):
            continue
    return False


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return
    if not isinstance(payload, dict):
        return

    if payload.get("tool_name") not in WATCHED_TOOLS:
        return

    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return

    if not _is_memory_path(tool_input.get("file_path")):
        return  # not a memory write -- stay out of the way

    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "ask",
                    "permissionDecisionReason": (
                        "Auto-memory write. Review the content above; reject "
                        "if it is a one-off, obvious, or not worth persisting."
                    ),
                }
            }
        )
    )


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # never wedge a session on a hook failure
    sys.exit(0)
