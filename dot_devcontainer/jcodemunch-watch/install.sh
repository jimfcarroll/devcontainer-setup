#!/usr/bin/env bash
#
# jcodemunch-watch Feature -- IMAGE BUILD step.
#
# Runs as root during the image build (devcontainer Features spec), after the
# Python Feature (`installsAfter` in devcontainer-feature.json).
#
# Installs jcodemunch-mcp WITH watchfiles for the remote user, in exactly the
# place post-create.sh used to put it -- the tool under ~/.local/share/uv/tools,
# its entry point at ~/.local/bin -- because ~/.claude/settings.json's hooks and
# start-jcodemunch-watch.sh both call it by that absolute path.
#
# Why at build and not in post-create.sh: this Feature's entrypoint starts the
# watcher from PID 1, and on a freshly rebuilt container PID 1 runs BEFORE
# postCreateCommand.  The binary has to already be in the image.
#
# `--with watchfiles` is load-bearing: `watch` needs it but jcodemunch-mcp does
# not depend on it.  Without it the watcher prints a FATAL and then stays alive
# doing nothing -- which is how the index once drifted 46 commits behind HEAD
# while reporting itself fresh.

set -euo pipefail

USERNAME="${_REMOTE_USER:-node}"
USER_HOME="${_REMOTE_USER_HOME:-/home/$USERNAME}"
PY=/usr/local/python/current/bin/python3     # provided by the Python Feature
UV=/usr/local/python/current/bin/uv

if [ ! -x "$PY" ]; then
    echo "jcodemunch-watch: $PY not found -- is the Python Feature installed?" >&2
    exit 1
fi

# Everything as the user, never as root.  /usr/local/python is owned by the
# user, and post-create.sh later runs `pip3 install` into the same interpreter
# as that user under `set -e`; root-owned files left there could make it fail
# and abort the whole post-create.
as_user() { runuser -u "$USERNAME" -- env HOME="$USER_HOME" "$@"; }

# uv is not one of the Python Feature's tools.  Installed exactly where
# post-create.sh installs it, so its later `pip3 install uv` is a no-op.
as_user "$PY" -m pip install --no-cache-dir --disable-pip-version-check uv

# --python pins the tool's venv to the Python Feature's interpreter, matching
# what post-create.sh produced.  No cache: it would only bloat the image layer.
as_user env UV_NO_CACHE=1 "$UV" tool install --force --python "$PY" \
    jcodemunch-mcp --with watchfiles

# The entrypoint the tool splices into PID 1's startup script.  It lives in the
# image and never changes; the logic it launches lives in the workspace.
install -D -m 0755 "$(dirname "$0")/launch.sh" /usr/local/share/jcodemunch-watch/launch.sh

echo "jcodemunch-watch: installed $(as_user "$USER_HOME/.local/bin/jcodemunch-mcp" --version 2>&1 | head -1)"
