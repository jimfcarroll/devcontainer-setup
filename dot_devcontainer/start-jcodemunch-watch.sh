#!/usr/bin/env bash
#
# Start the jCodeMunch file watcher in the background.
#
# Launched at every container start by the jcodemunch-watch Feature's entrypoint
# (.devcontainer/jcodemunch-watch/launch.sh), which PID 1 runs and which starts
# this script in the background and returns.  This script is read from the
# workspace each time, so changing it needs a restart, not a rebuild -- and it is
# free to grow a watchdog and run forever without holding up container startup.
#
# Why a watcher exists
# --------------------
# The code index only auto-updates through Claude Code's PostToolUse hook, which
# fires on the Edit/Write tools alone.  Anything else that changes a file is
# invisible to it:
#
#   * git operations  (checkout, pull, reset, rebase, stash)
#   * shell edits     (sed, heredocs, scripts)
#   * the VS Code editor
#
# The packaged watcher ships as a systemd unit, and this container has no init
# system, so it had never run.  On 2026-09-18 that was found to have left the
# index 46 COMMITS BEHIND HEAD while `list-repos` still reported it "fresh"
# (freshness is measured from the last incremental write, not from agreement
# with the tree).  It served a pre-epic-019 file body containing two patterns
# the active epic forbids.
#
# `jcodemunch-mcp watch` runs an initial index before it starts watching, so this
# also catches up whatever changed while the container was down.

set -u

BIN=/home/node/.local/bin/jcodemunch-mcp
TOOL_PY=/home/node/.local/share/uv/tools/jcodemunch-mcp/bin/python
LOG=/home/node/.code-index/watch.log
REPO=/workspace

if [ ! -x "$BIN" ]; then
    echo "jcodemunch: $BIN not executable -- skipping watcher"
    exit 0
fi

# The watcher needs `watchfiles`, which is NOT a dependency of the tool itself.
# Without it the watcher starts, prints a FATAL to stderr, and then STAYS ALIVE
# doing nothing -- so pgrep shows it running and watch-status keeps reporting
# healthy.  That is precisely how the drift above went unnoticed.
#
# The jcodemunch-watch Feature installs it at image build (`--with watchfiles`),
# so it is in uv-receipt.toml and survives `uv tool upgrade`.  The check stays
# anyway: it turns a silent do-nothing watcher into a loud message.
if ! "$TOOL_PY" -c "import watchfiles" >/dev/null 2>&1; then
    echo "jcodemunch: WATCHER DISABLED -- the 'watchfiles' package is missing."
    echo "jcodemunch: reinstall with:"
    echo "  uv tool install --force jcodemunch-mcp --with watchfiles"
    echo "jcodemunch: until then the index updates on Edit/Write only, and WILL drift."
    exit 0
fi

# One watcher per repo -- guards against a second launch, e.g. a hand-run while
# one is already up.  The bracket stops the pattern matching the shell that is
# running this very script.
if pgrep -f "jcodemunch-mcp wat[c]h $REPO" >/dev/null 2>&1; then
    echo "jcodemunch: watcher already running -- nothing to do"
    exit 0
fi

# ~/.code-index is container-overlay, not a bind mount.  On a freshly rebuilt
# container this runs from PID 1 BEFORE post-create.sh has indexed anything, so
# the directory does not exist yet -- and without it the redirections below fail
# and the watcher never starts.
mkdir -p "$(dirname "$LOG")"

echo "--- watcher launch $(date -Is) (script pid $$) ---" >>"$LOG" 2>&1

# WHY THIS IS NOT LAUNCHED FROM postStartCommand -- reproduced 2026-09-18/19.
#
# It used to be, and the watcher died silently before printing a byte.  The
# devcontainer runner executes postStartCommand as `/bin/sh -c ...` inside a PTY
# (devcontainers/cli injectHeadless.ts: runRemoteCommand with pty: true), so that
# sh is the terminal's CONTROLLING PROCESS.  It exits immediately, and when it
# does the kernel sends SIGHUP to the terminal's FOREGROUND process group.  A
# non-interactive shell has no job control, so a background `cmd &` was still
# in that group.  Reproduced under a real PTY, 40 launches each:
#
#     setsid nohup cmd &          0/40 survive   (what shipped first)
#     ( setsid nohup cmd & )      0/40           (a double fork -- the same race)
#     trap '' HUP; setsid ...    40/40           (by IGNORING SIGHUP -- rejected)
#     set -m; cmd &              40/40           (own process group, synchronously)
#
# Launching from PID 1 removes the cause instead of working around it: PID 1
# does not exit while the container runs, so nothing is hung up, and a plain
# background launch needs no set -m, setsid, nohup or trap.
#
# stdout AND stderr are captured because the watcher's progress lines and fatal
# errors go to stderr -- the CLI does not forward --log-file to watch_folders, so
# that flag only carries logging-module output.  No --idle-timeout: that shuts
# the watcher down after N quiet minutes, which is wrong for a long-lived one.
"$BIN" watch "$REPO" --log-file "$LOG" >>"$LOG" 2>&1 </dev/null &
echo "--- watcher pid $! ---" >>"$LOG" 2>&1
disown 2>/dev/null || true

echo "jcodemunch: watcher launched -- logging to $LOG"
exit 0
