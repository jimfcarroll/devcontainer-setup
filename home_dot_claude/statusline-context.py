#!/usr/bin/env python3
"""Claude Code status line: context-usage bar.

Reads the status-line JSON payload on stdin and renders how full the
context window is.

Both the token count and the window size come from the payload's
`context_window` block, which Claude Code populates on every render:

    context_window: {
        total_input_tokens,      # input + cache_creation + cache_read
        total_output_tokens,
        context_window_size,     # the real window for this session
        current_usage,           # the raw usage block
        used_percentage,
        remaining_percentage,
    }

The window is never inferred from how many tokens happen to be in use --
that is what made an earlier version of this script report a 1M-window
session as if it were a 200k one.

Must never crash: a traceback would replace the status line, so every
stage degrades to a partial line instead.
"""

import json
import os
import sys
from pathlib import Path

# Set CLAUDE_CONTEXT_WINDOW to pin the window size and ignore the payload.
BAR_WIDTH = 20
FULL, EMPTY = "█", "░"
RESET, DIM = "\033[0m", "\033[2m"
GREEN, YELLOW, RED = "\033[32m", "\033[33m", "\033[31m"


def _dict(value):
    """A dict, or an empty one. Payload shapes are not guaranteed."""
    return value if isinstance(value, dict) else {}


def _int(value):
    """Coerce to a positive int, else None. Payload fields are untrusted."""
    if isinstance(value, bool) or not isinstance(value, (int, float, str)):
        return None
    try:
        n = int(value)
    except (TypeError, ValueError):
        return None
    return n if n > 0 else None


def _resolve(payload):
    """(tokens, window) from the payload, or None if unavailable."""
    block = _dict(payload.get("context_window"))
    if not block:
        return None

    window = _int(os.environ.get("CLAUDE_CONTEXT_WINDOW", "").strip()) or _int(
        block.get("context_window_size")
    )
    if window is None:
        return None

    tokens = _int(block.get("total_input_tokens"))
    if tokens is None:
        # Absent or zero at session start; recompute from the raw usage block.
        usage = _dict(block.get("current_usage"))
        tokens = sum(
            _int(usage.get(k)) or 0
            for k in (
                "input_tokens",
                "cache_creation_input_tokens",
                "cache_read_input_tokens",
            )
        )
    return tokens, window


def _human(n):
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.0f}k"
    return str(n)


def _color(pct):
    return RED if pct >= 80 else YELLOW if pct >= 50 else GREEN


def _bar(pct):
    filled = min(BAR_WIDTH, max(0, round(pct / 100 * BAR_WIDTH)))
    return f"{_color(pct)}{FULL * filled}{DIM}{EMPTY * (BAR_WIDTH - filled)}{RESET}"


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        payload = {}
    if not isinstance(payload, dict):
        payload = {}

    parts = []

    model = _dict(payload.get("model")).get("display_name")
    if isinstance(model, str) and model:
        parts.append(f"{DIM}{model}{RESET}")

    resolved = _resolve(payload)
    if resolved:
        tokens, window = resolved
        pct = min(100.0, tokens / window * 100)
        parts.append(
            f"{_bar(pct)} {_color(pct)}{pct:.0f}%{RESET} "
            f"{DIM}({_human(tokens)}/{_human(window)}){RESET}"
        )
    else:
        parts.append(f"{DIM}context: —{RESET}")

    cwd = _dict(payload.get("workspace")).get("current_dir") or payload.get("cwd")
    if isinstance(cwd, str) and cwd:
        parts.append(f"{DIM}{Path(cwd).name}{RESET}")

    print(f" {DIM}│{RESET} ".join(parts))


if __name__ == "__main__":
    try:
        main()
    except Exception:  # never let the status line vanish
        print(f"{DIM}context: unavailable{RESET}")
