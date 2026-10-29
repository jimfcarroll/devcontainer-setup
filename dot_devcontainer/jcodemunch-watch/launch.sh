#!/bin/sh
#
# jcodemunch-watch Feature -- CONTAINER START step (the Feature's `entrypoint`).
#
# The devcontainer tool splices every Feature's entrypoint into PID 1's startup
# script as one line, ahead of its keep-alive loop (devcontainers/cli
# singleContainer.ts: `${customEntrypoints.join('\n')}` before `exec "$@"`).
#
# ONE RULE: RETURN AT ONCE.  PID 1 runs this in the foreground.  If it blocked,
# PID 1 would never reach its loop, and sh defers its `trap "exit 0" 15` until
# the foreground command ends -- so `docker stop` would hang until Docker's
# timeout and then SIGKILL.  Other Features' entrypoints would never run either.
#
# So this only STARTS the project's script, in the background, and returns.  It
# knows nothing about jcodemunch.  The script owns all of that, may grow a
# watchdog and run forever, and is read from the workspace on every start, so
# changing it needs a restart, not a rebuild.
#
# A plain background launch is safe here.  Under postStartCommand it was not:
# that ran in a PTY whose controlling process exited immediately, SIGHUP-ing
# everything still in its foreground process group.  PID 1 does not exit while
# the container runs, so nothing is hung up.

SCRIPT=/workspace/.devcontainer/start-jcodemunch-watch.sh

if [ -f "$SCRIPT" ]; then
    bash "$SCRIPT" </dev/null &
else
    echo "jcodemunch-watch: $SCRIPT not found -- nothing started"
fi
