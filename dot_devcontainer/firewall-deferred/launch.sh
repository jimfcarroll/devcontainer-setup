#!/bin/sh
#
# firewall-deferred Feature -- CONTAINER START step (the Feature's `entrypoint`).
#
# Spliced into PID 1's startup script by the devcontainer tool, exactly like
# jcodemunch-watch/launch.sh, and for the same reason it documents: a background
# process started from a lifecycle hook does not survive the hook. Measured
# 2026-10-25: launched from postStartCommand with setsid, the deferred firewall
# died before its first echo and left the container with unrestricted egress for
# the whole session. PID 1 never exits while the container runs, so a child of
# PID 1 is never cleaned up behind a hook that has finished.
#
# ONE RULE: RETURN AT ONCE. PID 1 runs this in the foreground; if it blocked,
# `docker stop` would hang (see jcodemunch-watch/launch.sh).
#
# What it starts waits for two things and then locks the network down:
#   1. post-create to finish   -- marker written by post-create.sh's EXIT trap,
#                                 because post-create fetches from hosts the
#                                 allowlist does not carry (huggingface.co)
#   2. extension installs to settle -- VSIX bytes come from per-publisher Akamai
#                                 hostnames the ipset allowlist cannot enumerate
# Both waits are bounded, and every exit from them applies the rules anyway.
# Progress is in $LOG; the first line below proves the launch itself happened.

LOG=/tmp/init-firewall.log
: > "$LOG"
echo "firewall-deferred: launched from PID $$ at $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LOG"
/usr/bin/setsid /usr/bin/sudo /usr/local/bin/init-firewall.sh --after-extensions </dev/null >>"$LOG" 2>&1 &
